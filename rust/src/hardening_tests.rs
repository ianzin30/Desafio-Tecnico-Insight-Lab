//! Session security and robustness: secrets out of plain files, migration of
//! the previous format, offline startup, unavailable credential store,
//! corrupted store, repeated sessions.

use std::fs;
use std::sync::Arc;

use serde_json::{Value, json};
use tempfile::TempDir;
use wiremock::MockServer;

use crate::secrets::testing::{UnavailableSecrets, memory_contains};
use crate::test_support::*;
use crate::{CoreError, LogoutOutcome, MessengerCore, RestoreOutcome};

const ROOM: &str = "!room:example.org";

fn secret_key(data_dir: &TempDir) -> String {
    fs::canonicalize(data_dir.path())
        .unwrap()
        .to_string_lossy()
        .into_owned()
}

fn session_json(data_dir: &TempDir) -> Value {
    serde_json::from_str(&fs::read_to_string(session_file(data_dir)).unwrap()).unwrap()
}

#[tokio::test]
async fn the_access_token_is_only_in_the_credential_store() {
    let server = alice_homeserver().await;
    let data_dir = TempDir::new().unwrap();

    drop(logged_in_core(&server, &data_dir).await);

    let file = fs::read_to_string(session_file(&data_dir)).unwrap();
    assert!(!file.contains("test-access-token"));
    assert!(file.contains("@alice:example.org"));
    assert!(memory_contains(&secret_key(&data_dir)));
}

#[tokio::test]
async fn a_session_saved_by_the_previous_version_is_migrated_and_restored() {
    let server = alice_homeserver().await;
    let data_dir = TempDir::new().unwrap();
    // The previous version: unencrypted store, tokens in session.json.
    crate::messenger_core::LEGACY_UNENCRYPTED_STORES.set(true);
    drop(logged_in_core(&server, &data_dir).await);
    crate::messenger_core::LEGACY_UNENCRYPTED_STORES.set(false);
    let v2 = session_json(&data_dir);
    let v1 = json!({
        "version": 1,
        "homeserver": v2["homeserver"],
        "store": v2["store"],
        "session": {
            "user_id": v2["user_id"],
            "device_id": v2["device_id"],
            "access_token": "test-access-token",
        },
    });
    fs::write(session_file(&data_dir), v1.to_string()).unwrap();
    crate::secrets::secret_store(crate::SecretStorage::InMemory)
        .delete(&secret_key(&data_dir))
        .unwrap();

    let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();

    // Migrated when read at startup: no plain-text token any more.
    let migrated = fs::read_to_string(session_file(&data_dir)).unwrap();
    assert!(!migrated.contains("test-access-token"));
    assert_eq!(session_json(&data_dir)["version"], 2);
    assert!(memory_contains(&secret_key(&data_dir)));
    assert_eq!(
        core.restore_session().await.unwrap(),
        RestoreOutcome::Restored
    );
    assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
    drop(core);

    // And again from the migrated format.
    let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
    assert_eq!(
        core.restore_session().await.unwrap(),
        RestoreOutcome::Restored
    );
}

#[tokio::test]
async fn startup_offline_restores_the_session_and_cached_rooms() {
    // Not pooled: the server really goes away.
    let server = MockServer::builder().start().await;
    mock_versions(&server).await;
    crate::test_support::mock_login_response(&server, login_success("@alice:example.org")).await;
    let data_dir = TempDir::new().unwrap();
    let homeserver = server.uri();
    drop(core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await);
    drop(server);

    let mut core = test_core(&homeserver, data_dir.path()).await.unwrap();

    assert_eq!(
        core.restore_session().await.unwrap(),
        RestoreOutcome::Restored
    );
    assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
    let rooms = core.cached_rooms().await.unwrap();
    assert_eq!(rooms.len(), 1);
    // Requests fail as unreachable, but the session is kept.
    assert!(matches!(
        core.load_messages(ROOM, 10).await,
        Err(CoreError::HomeserverUnreachable(_))
    ));
    assert!(core.current_user().is_some());
    assert!(session_file(&data_dir).exists());
}

#[tokio::test]
async fn an_unavailable_credential_store_never_discards_the_session() {
    let server = alice_homeserver().await;
    let data_dir = TempDir::new().unwrap();
    drop(logged_in_core(&server, &data_dir).await);

    let locked = MessengerCore::with_secret_store(
        &server.uri(),
        data_dir.path(),
        Arc::new(UnavailableSecrets),
    )
    .await;

    assert!(matches!(locked, Err(CoreError::Storage(_))));
    assert!(session_file(&data_dir).exists());
    assert_eq!(store_count(&data_dir), 1);

    // Once available again, the session is restored.
    let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
    assert_eq!(
        core.restore_session().await.unwrap(),
        RestoreOutcome::Restored
    );
}

#[tokio::test]
async fn a_corrupted_store_is_an_invalid_session_without_panic() {
    let server = alice_homeserver().await;
    let data_dir = TempDir::new().unwrap();
    drop(logged_in_core(&server, &data_dir).await);
    let stores = data_dir.path().join("stores");
    for store in fs::read_dir(&stores).unwrap().flatten() {
        for file in fs::read_dir(store.path()).unwrap().flatten() {
            fs::write(file.path(), b"not a sqlite database").unwrap();
        }
    }

    let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
    let err = core.restore_session().await.unwrap_err();

    assert!(matches!(err, CoreError::InvalidSession(_)), "{err:?}");
    assert_eq!(core.current_user(), None);
    assert!(!session_file(&data_dir).exists());
    assert!(!memory_contains(&secret_key(&data_dir)));
    core.login("alice", "secret").await.unwrap();
}

#[tokio::test]
async fn offline_logout_removes_the_local_secrets() {
    let server = MockServer::builder().start().await;
    mock_versions(&server).await;
    crate::test_support::mock_login_response(&server, login_success("@alice:example.org")).await;
    let data_dir = TempDir::new().unwrap();
    let mut core = logged_in_core(&server, &data_dir).await;
    drop(server);

    assert_eq!(core.logout().await.unwrap(), LogoutOutcome::LocalOnly);

    assert!(!session_file(&data_dir).exists());
    assert!(!memory_contains(&secret_key(&data_dir)));
    assert_eq!(core.current_user(), None);
}

#[tokio::test]
async fn repeated_sessions_leave_no_stores_or_secrets_behind() {
    let server = alice_homeserver().await;
    let data_dir = TempDir::new().unwrap();
    let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();

    for _ in 0..10 {
        core.login("alice", "secret").await.unwrap();
        assert!(memory_contains(&secret_key(&data_dir)));
        core.logout().await.unwrap();
        assert!(!memory_contains(&secret_key(&data_dir)));
        assert_eq!(store_count(&data_dir), 1);
    }
    assert!(!session_file(&data_dir).exists());
}
