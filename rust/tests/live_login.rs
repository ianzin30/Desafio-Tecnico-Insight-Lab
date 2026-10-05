//! Login, restore and logout against a real homeserver.
//!
//! Ignored by default: it needs network access and a real account, provided
//! through environment variables (never commit credentials):
//!
//! ```bash
//! MATRIX_HOMESERVER=https://matrix.org MATRIX_USERNAME=alice MATRIX_PASSWORD=... \
//!     cargo test --test live_login -- --ignored
//! ```

use messenger_core::{LogoutOutcome, MessengerCore, RestoreOutcome};

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| panic!("{name} must be set"))
}

#[tokio::test]
#[ignore = "requires a real homeserver and MATRIX_* credentials"]
async fn login_restore_and_logout_on_a_real_homeserver() {
    let homeserver = env("MATRIX_HOMESERVER");
    let data_dir = tempfile::tempdir().expect("temporary data dir");

    let mut core = MessengerCore::new(&homeserver, data_dir.path())
        .await
        .expect("valid homeserver");
    core.login(&env("MATRIX_USERNAME"), &env("MATRIX_PASSWORD"))
        .await
        .expect("login succeeds");
    let user = core.current_user().expect("authenticated user");
    println!("logged in as {user}");
    drop(core);

    let mut core = MessengerCore::new(&homeserver, data_dir.path())
        .await
        .expect("valid homeserver");
    assert_eq!(
        core.restore_session().await.expect("restore succeeds"),
        RestoreOutcome::Restored
    );
    assert_eq!(core.current_user(), Some(user));

    assert_eq!(
        core.logout().await.expect("logout succeeds"),
        LogoutOutcome::Complete
    );
}
