use std::path::Path;

use matrix_sdk::config::RequestConfig;
use matrix_sdk::ruma::api::client::session::logout;
use matrix_sdk::ruma::api::error::ErrorKind;
use matrix_sdk::store::RoomLoadSettings;
use matrix_sdk::{Client, HttpError};
use url::Url;

use crate::CoreError;
use crate::homeserver::parse_homeserver_url;
use crate::storage::{Storage, StoredSession};

/// Result of [`MessengerCore::restore_session`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RestoreOutcome {
    /// No persisted session: the core stays unauthenticated (e.g. first run).
    NoSession,
    /// The persisted session was restored; see [`MessengerCore::current_user`].
    Restored,
}

/// Result of [`MessengerCore::logout`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogoutOutcome {
    /// The session was revoked on the homeserver and removed locally.
    Complete,
    /// The session was removed locally, but the homeserver could not be told
    /// (e.g. offline): its access token may remain valid server-side.
    LocalOnly,
}

/// An active instance of the messaging core.
///
/// Owns the single Matrix [`Client`] used for every operation of this
/// instance, backed by a persistent SQLite store under `data_dir`. The client
/// is only replaced internally when a session is discarded (logout or invalid
/// session), so that the next login never reuses another identity's store.
#[derive(Debug)]
pub struct MessengerCore {
    client: Client,
    homeserver: Url,
    storage: Storage,
    /// Name of the store directory used by `client`.
    store: String,
}

impl MessengerCore {
    /// Creates a core bound to the given homeserver URL
    /// (e.g. `https://matrix.org`), persisting its data under `data_dir`.
    ///
    /// The data directory is provided by the caller (one per application
    /// installation) and created if missing. No request is sent to the
    /// homeserver here; call [`restore_session`](Self::restore_session) to
    /// resume a previous login.
    pub async fn new(homeserver_url: &str, data_dir: impl AsRef<Path>) -> Result<Self, CoreError> {
        let homeserver = parse_homeserver_url(homeserver_url)?;
        let storage = Storage::open(data_dir.as_ref()).map_err(storage_error)?;

        // Reopen the store of a session that may be restored; anything else
        // (no session, invalid file, other homeserver, unusable store) starts
        // from a fresh store and `restore_session` reports it.
        let restorable = match storage.load_session() {
            Ok(Some(stored)) if stored.homeserver == homeserver.as_str() => Some(stored.store),
            _ => None,
        };
        let reopened = match restorable {
            Some(store) => build_client(&homeserver, &storage, &store)
                .await
                .ok()
                .map(|client| (client, store)),
            None => None,
        };
        let (client, store) = match reopened {
            Some(reopened) => reopened,
            None => {
                let store = storage.create_store().map_err(storage_error)?;
                (build_client(&homeserver, &storage, &store).await?, store)
            }
        };
        storage.remove_stores_except(&store);

        Ok(Self {
            client,
            homeserver,
            storage,
            store,
        })
    }

    /// The homeserver URL the client is configured for.
    pub fn homeserver(&self) -> String {
        self.homeserver.to_string()
    }

    /// Restores the session persisted by a previous [`login`](Self::login).
    ///
    /// - No persisted session → `Ok(RestoreOutcome::NoSession)`.
    /// - Valid session → `Ok(RestoreOutcome::Restored)`.
    /// - Session that cannot be restored → [`CoreError::InvalidSession`];
    ///   it is discarded and the core is left ready for a new login.
    ///
    /// No request is sent: a token revoked server-side is only detected by
    /// the next request to the homeserver.
    pub async fn restore_session(&mut self) -> Result<RestoreOutcome, CoreError> {
        if self.current_user().is_some() {
            return Err(CoreError::AlreadyAuthenticated);
        }

        let stored = match self.storage.load_session() {
            Ok(None) => return Ok(RestoreOutcome::NoSession),
            Ok(Some(stored)) => stored,
            Err(err) => return Err(self.discard_invalid_session(err).await),
        };
        if stored.homeserver != self.homeserver.as_str() {
            return Err(self
                .discard_invalid_session("session belongs to another homeserver".into())
                .await);
        }
        if stored.store != self.store {
            return Err(self
                .discard_invalid_session("session store could not be opened".into())
                .await);
        }

        let restored = self
            .client
            .matrix_auth()
            .restore_session(stored.session, RoomLoadSettings::default())
            .await;
        match restored {
            Ok(()) => Ok(RestoreOutcome::Restored),
            Err(err) => Err(self.discard_invalid_session(err.into()).await),
        }
    }

    /// Logs in with a username (localpart such as `alice`, or full user ID
    /// such as `@alice:matrix.org`) and password, and persists the resulting
    /// session so it can be restored after a restart.
    ///
    /// The password is only forwarded to the Matrix SDK for this request; it
    /// is never stored. A persisted session that was not restored is
    /// discarded first, so the new login gets a fresh store.
    ///
    /// A core instance holds a single identity: logging in while a user is
    /// already authenticated fails with [`CoreError::AlreadyAuthenticated`]
    /// instead of replacing the session. `&mut self` ensures no two logins
    /// can run concurrently on the same instance.
    pub async fn login(&mut self, username: &str, password: &str) -> Result<(), CoreError> {
        if self.current_user().is_some() {
            return Err(CoreError::AlreadyAuthenticated);
        }
        let username = username.trim();
        if username.is_empty() || password.is_empty() {
            return Err(CoreError::InvalidCredentials);
        }
        if self.storage.has_session() {
            self.discard_local_session().await?;
        }

        self.client
            .matrix_auth()
            .login_username(username, password)
            .send()
            .await
            .map_err(map_login_error)?;

        // Login only succeeds once the session is persisted; otherwise it is
        // undone so the in-memory and on-disk states never diverge.
        if let Err(err) = self.persist_session() {
            self.revoke_remote_session().await;
            self.discard_local_session().await?;
            return Err(err);
        }
        Ok(())
    }

    /// Logs out: revokes the session on the homeserver when possible, then
    /// always deletes the persisted session and the identity's store, so the
    /// next start does not restore this user.
    ///
    /// If the homeserver cannot be reached the local logout still happens and
    /// [`LogoutOutcome::LocalOnly`] is returned. Logging out an
    /// unauthenticated core only clears leftover local state.
    pub async fn logout(&mut self) -> Result<LogoutOutcome, CoreError> {
        let revoked = if self.current_user().is_some() {
            self.revoke_remote_session().await
        } else {
            !self.storage.has_session()
        };
        self.discard_local_session().await?;

        Ok(if revoked {
            LogoutOutcome::Complete
        } else {
            LogoutOutcome::LocalOnly
        })
    }

    /// The fully qualified Matrix ID of the authenticated user
    /// (e.g. `@alice:matrix.org`), or `None` before login.
    ///
    /// Read directly from the Matrix client's session state.
    pub fn current_user(&self) -> Option<String> {
        self.client.user_id().map(ToString::to_string)
    }

    fn persist_session(&self) -> Result<(), CoreError> {
        let session = self.client.matrix_auth().session().ok_or_else(|| {
            CoreError::AuthenticationFailed("no session after successful login".into())
        })?;
        let stored = StoredSession::new(self.homeserver.to_string(), self.store.clone(), session);
        self.storage.save_session(&stored).map_err(storage_error)
    }

    /// Asks the homeserver to invalidate the access token. Returns whether
    /// the token is known to be invalid server-side.
    async fn revoke_remote_session(&self) -> bool {
        // Bounded retries: the SDK default retries network failures for
        // minutes, which would block an offline logout.
        let result = self
            .client
            .send(logout::v3::Request::new())
            .with_request_config(RequestConfig::short_retry())
            .await;
        match result {
            Ok(_) => true,
            Err(err) => matches!(
                err.client_api_error_kind(),
                Some(ErrorKind::UnknownToken(_))
            ),
        }
    }

    /// Deletes the persisted session and switches to a new client on a fresh
    /// store; the previous store is deleted.
    async fn discard_local_session(&mut self) -> Result<(), CoreError> {
        self.storage.remove_session().map_err(storage_error)?;

        let store = self.storage.create_store().map_err(storage_error)?;
        self.client = build_client(&self.homeserver, &self.storage, &store).await?;
        self.store = store;
        self.storage.remove_stores_except(&self.store);
        Ok(())
    }

    async fn discard_invalid_session(&mut self, cause: crate::error::BoxError) -> CoreError {
        match self.discard_local_session().await {
            Ok(()) => CoreError::InvalidSession(cause),
            Err(err) => err,
        }
    }
}

async fn build_client(
    homeserver: &Url,
    storage: &Storage,
    store: &str,
) -> Result<Client, CoreError> {
    Client::builder()
        .homeserver_url(homeserver)
        // Keep the configured homeserver: a session is bound to it.
        .respect_login_well_known(false)
        .sqlite_store(storage.store_path(store), None)
        .build()
        .await
        .map_err(|err| CoreError::ClientInitialization(err.into()))
}

fn storage_error(err: std::io::Error) -> CoreError {
    CoreError::Storage(err.into())
}

fn map_login_error(err: matrix_sdk::Error) -> CoreError {
    if matches!(err.client_api_error_kind(), Some(ErrorKind::Forbidden)) {
        return CoreError::InvalidCredentials;
    }
    if let matrix_sdk::Error::Http(http) = &err
        && let HttpError::Reqwest(reqwest) = http.as_ref()
        && (reqwest.is_connect() || reqwest.is_timeout())
    {
        return CoreError::HomeserverUnreachable(err.into());
    }
    CoreError::AuthenticationFailed(err.into())
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use tempfile::TempDir;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    use super::*;

    /// A local mock homeserver that advertises a supported spec version and
    /// accepts logouts.
    async fn mock_homeserver() -> MockServer {
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/_matrix/client/versions"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "versions": ["v1.11"]
            })))
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/_matrix/client/v3/logout"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
            .mount(&server)
            .await;
        server
    }

    async fn mock_login_response(server: &MockServer, response: ResponseTemplate) {
        Mock::given(method("POST"))
            .and(path("/_matrix/client/v3/login"))
            .respond_with(response)
            .mount(server)
            .await;
    }

    fn login_success(user_id: &str) -> ResponseTemplate {
        ResponseTemplate::new(200).set_body_json(json!({
            "user_id": user_id,
            "access_token": "test-access-token",
            "device_id": "TESTDEVICE"
        }))
    }

    /// A mock homeserver accepting logins as `@alice:example.org`.
    async fn alice_homeserver() -> MockServer {
        let server = mock_homeserver().await;
        mock_login_response(&server, login_success("@alice:example.org")).await;
        server
    }

    async fn logged_in_core(server: &MockServer, data_dir: &TempDir) -> MessengerCore {
        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();
        core.login("alice", "secret").await.unwrap();
        core
    }

    fn session_file(data_dir: &TempDir) -> std::path::PathBuf {
        data_dir.path().join("session.json")
    }

    fn store_count(data_dir: &TempDir) -> usize {
        std::fs::read_dir(data_dir.path().join("stores"))
            .unwrap()
            .count()
    }

    #[tokio::test]
    async fn builds_client_for_homeserver() {
        let data_dir = TempDir::new().unwrap();
        let core = MessengerCore::new("https://matrix.org", data_dir.path())
            .await
            .unwrap();

        assert_eq!(core.homeserver(), "https://matrix.org/");
    }

    #[tokio::test]
    async fn rejects_invalid_homeserver_without_building_client() {
        let data_dir = TempDir::new().unwrap();
        let err = MessengerCore::new("matrix.org", data_dir.path())
            .await
            .unwrap_err();

        assert!(matches!(err, CoreError::InvalidHomeserver { .. }));
    }

    #[tokio::test]
    async fn first_run_has_no_session_to_restore() {
        let data_dir = TempDir::new().unwrap();
        let mut core = MessengerCore::new("https://matrix.org", data_dir.path())
            .await
            .unwrap();

        assert_eq!(core.current_user(), None);
        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::NoSession
        );
        assert_eq!(core.current_user(), None);
    }

    #[tokio::test]
    async fn login_authenticates_the_existing_client() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();

        let core = logged_in_core(&server, &data_dir).await;

        assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
    }

    #[tokio::test]
    async fn login_persists_the_session_but_not_the_password() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();

        core.login("alice", "s3cr3t-password").await.unwrap();

        let saved = std::fs::read_to_string(session_file(&data_dir)).unwrap();
        assert!(saved.contains("@alice:example.org"));
        assert!(!saved.contains("s3cr3t-password"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(session_file(&data_dir))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o600);
        }
    }

    #[tokio::test]
    async fn session_survives_a_restart() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        drop(logged_in_core(&server, &data_dir).await);

        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();
        assert_eq!(core.current_user(), None);

        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::Restored
        );
        assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
        assert_eq!(store_count(&data_dir), 1);
    }

    #[tokio::test]
    async fn restore_while_authenticated_is_rejected() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        let err = core.restore_session().await.unwrap_err();

        assert!(matches!(err, CoreError::AlreadyAuthenticated));
    }

    #[tokio::test]
    async fn logout_prevents_restore_after_restart() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        assert_eq!(core.logout().await.unwrap(), LogoutOutcome::Complete);
        assert_eq!(core.current_user(), None);
        assert!(!session_file(&data_dir).exists());
        drop(core);

        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();
        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::NoSession
        );
        assert_eq!(store_count(&data_dir), 1);
    }

    #[tokio::test]
    async fn offline_logout_still_removes_the_local_session() {
        // Not pooled: the server really shuts down when dropped.
        let server = MockServer::builder().start().await;
        Mock::given(method("GET"))
            .and(path("/_matrix/client/versions"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "versions": ["v1.11"]
            })))
            .mount(&server)
            .await;
        mock_login_response(&server, login_success("@alice:example.org")).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let homeserver = server.uri();
        drop(server); // the homeserver goes offline

        assert_eq!(core.logout().await.unwrap(), LogoutOutcome::LocalOnly);
        assert_eq!(core.current_user(), None);
        drop(core);

        let mut core = MessengerCore::new(&homeserver, data_dir.path())
            .await
            .unwrap();
        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::NoSession
        );
    }

    #[tokio::test]
    async fn login_after_logout_starts_a_new_session() {
        let server = mock_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        Mock::given(method("POST"))
            .and(path("/_matrix/client/v3/login"))
            .respond_with(login_success("@alice:example.org"))
            .up_to_n_times(1)
            .mount(&server)
            .await;
        let mut core = logged_in_core(&server, &data_dir).await;
        core.logout().await.unwrap();
        mock_login_response(&server, login_success("@bob:example.org")).await;

        core.login("bob", "secret").await.unwrap();
        assert_eq!(core.current_user().as_deref(), Some("@bob:example.org"));
        drop(core);

        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();
        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::Restored
        );
        assert_eq!(core.current_user().as_deref(), Some("@bob:example.org"));
    }

    #[tokio::test]
    async fn corrupted_session_is_discarded_without_panicking() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        drop(logged_in_core(&server, &data_dir).await);
        std::fs::write(session_file(&data_dir), "{ not json").unwrap();

        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();
        let err = core.restore_session().await.unwrap_err();

        assert!(matches!(err, CoreError::InvalidSession(_)));
        assert!(!session_file(&data_dir).exists());
        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::NoSession
        );
        core.login("alice", "secret").await.unwrap();
        assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
    }

    #[tokio::test]
    async fn session_of_another_homeserver_is_discarded() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        drop(logged_in_core(&server, &data_dir).await);

        let mut core = MessengerCore::new("https://other.example.org", data_dir.path())
            .await
            .unwrap();
        let err = core.restore_session().await.unwrap_err();

        assert!(matches!(err, CoreError::InvalidSession(_)));
        assert_eq!(core.current_user(), None);
        assert!(!session_file(&data_dir).exists());
    }

    #[tokio::test]
    async fn second_login_is_rejected_and_keeps_the_session() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        let err = core.login("bob", "other").await.unwrap_err();

        assert!(matches!(err, CoreError::AlreadyAuthenticated));
        assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
    }

    #[tokio::test]
    async fn rejected_credentials_map_to_invalid_credentials() {
        let server = mock_homeserver().await;
        mock_login_response(
            &server,
            ResponseTemplate::new(403).set_body_json(json!({
                "errcode": "M_FORBIDDEN",
                "error": "Invalid username or password"
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();

        let err = core.login("alice", "wrong").await.unwrap_err();

        assert!(matches!(err, CoreError::InvalidCredentials));
        assert_eq!(core.current_user(), None);
        assert!(!session_file(&data_dir).exists());
    }

    #[tokio::test]
    async fn empty_credentials_are_rejected_without_a_request() {
        // No mock is mounted: any request would fail with a different error.
        let server = MockServer::start().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();

        for (username, password) in [("", "secret"), ("   ", "secret"), ("alice", "")] {
            let err = core.login(username, password).await.unwrap_err();
            assert!(matches!(err, CoreError::InvalidCredentials));
        }
        assert!(server.received_requests().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn unreachable_homeserver_is_reported() {
        // Bind then release a local port so nothing is listening on it.
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        drop(listener);
        let data_dir = TempDir::new().unwrap();
        let mut core = MessengerCore::new(&url, data_dir.path()).await.unwrap();

        let err = core.login("alice", "secret").await.unwrap_err();

        assert!(
            matches!(err, CoreError::HomeserverUnreachable(_)),
            "unexpected error: {err:?}"
        );
    }

    #[tokio::test]
    async fn unexpected_server_response_maps_to_authentication_failed() {
        let server = mock_homeserver().await;
        mock_login_response(&server, ResponseTemplate::new(404)).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = MessengerCore::new(&server.uri(), data_dir.path())
            .await
            .unwrap();

        let err = core.login("alice", "s3cr3t-password").await.unwrap_err();

        assert!(
            matches!(err, CoreError::AuthenticationFailed(_)),
            "unexpected error: {err:?}"
        );
        // Neither the message nor the preserved SDK source leaks the password.
        assert!(!format!("{err} {err:?}").contains("s3cr3t-password"));
    }
}
