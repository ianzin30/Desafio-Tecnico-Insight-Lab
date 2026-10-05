use matrix_sdk::ruma::api::error::ErrorKind;
use matrix_sdk::{Client, HttpError};

use crate::CoreError;
use crate::homeserver::parse_homeserver_url;

/// An active instance of the messaging core.
///
/// Owns the single Matrix [`Client`] used for every operation of this
/// instance; the client is created once in [`MessengerCore::new`] and never
/// rebuilt.
#[derive(Debug)]
pub struct MessengerCore {
    client: Client,
}

impl MessengerCore {
    /// Creates a core bound to the given homeserver URL
    /// (e.g. `https://matrix.org`).
    ///
    /// No request is sent to the homeserver here: the address is used as-is,
    /// without `.well-known` discovery, and the client state lives in memory.
    pub async fn new(homeserver_url: &str) -> Result<Self, CoreError> {
        let url = parse_homeserver_url(homeserver_url)?;

        let client = Client::builder()
            .homeserver_url(url)
            .build()
            .await
            .map_err(|err| CoreError::ClientInitialization(err.into()))?;

        Ok(Self { client })
    }

    /// The homeserver URL the client is configured for.
    pub fn homeserver(&self) -> String {
        self.client.homeserver().to_string()
    }

    /// Logs in with a username (localpart such as `alice`, or full user ID
    /// such as `@alice:matrix.org`) and password.
    ///
    /// The password is only forwarded to the Matrix SDK for this request; the
    /// core never stores it. The resulting session lives in memory only.
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

        self.client
            .matrix_auth()
            .login_username(username, password)
            .send()
            .await
            .map_err(map_login_error)?;

        Ok(())
    }

    /// The fully qualified Matrix ID of the authenticated user
    /// (e.g. `@alice:matrix.org`), or `None` before login.
    ///
    /// Read directly from the Matrix client's session state.
    pub fn current_user(&self) -> Option<String> {
        self.client.user_id().map(ToString::to_string)
    }
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
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    use super::*;

    /// A local mock homeserver that advertises a supported spec version.
    async fn mock_homeserver() -> MockServer {
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/_matrix/client/versions"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "versions": ["v1.11"]
            })))
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

    fn login_success() -> ResponseTemplate {
        ResponseTemplate::new(200).set_body_json(json!({
            "user_id": "@alice:example.org",
            "access_token": "test-access-token",
            "device_id": "TESTDEVICE"
        }))
    }

    #[tokio::test]
    async fn builds_client_for_homeserver() {
        let core = MessengerCore::new("https://matrix.org").await.unwrap();

        assert_eq!(core.homeserver(), "https://matrix.org/");
    }

    #[tokio::test]
    async fn rejects_invalid_homeserver_without_building_client() {
        let err = MessengerCore::new("matrix.org").await.unwrap_err();

        assert!(matches!(err, CoreError::InvalidHomeserver { .. }));
    }

    #[tokio::test]
    async fn new_core_is_not_authenticated() {
        let core = MessengerCore::new("https://matrix.org").await.unwrap();

        assert_eq!(core.current_user(), None);
    }

    #[tokio::test]
    async fn login_authenticates_the_existing_client() {
        let server = mock_homeserver().await;
        mock_login_response(&server, login_success()).await;
        let mut core = MessengerCore::new(&server.uri()).await.unwrap();

        core.login("alice", "secret").await.unwrap();

        assert_eq!(core.current_user().as_deref(), Some("@alice:example.org"));
    }

    #[tokio::test]
    async fn second_login_is_rejected_and_keeps_the_session() {
        let server = mock_homeserver().await;
        mock_login_response(&server, login_success()).await;
        let mut core = MessengerCore::new(&server.uri()).await.unwrap();
        core.login("alice", "secret").await.unwrap();

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
        let mut core = MessengerCore::new(&server.uri()).await.unwrap();

        let err = core.login("alice", "wrong").await.unwrap_err();

        assert!(matches!(err, CoreError::InvalidCredentials));
        assert_eq!(core.current_user(), None);
    }

    #[tokio::test]
    async fn empty_credentials_are_rejected_without_a_request() {
        // No mock is mounted: any request would fail with a different error.
        let server = MockServer::start().await;
        let mut core = MessengerCore::new(&server.uri()).await.unwrap();

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
        let mut core = MessengerCore::new(&url).await.unwrap();

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
        let mut core = MessengerCore::new(&server.uri()).await.unwrap();

        let err = core.login("alice", "s3cr3t-password").await.unwrap_err();

        assert!(
            matches!(err, CoreError::AuthenticationFailed(_)),
            "unexpected error: {err:?}"
        );
        // Neither the message nor the preserved SDK source leaks the password.
        assert!(!format!("{err} {err:?}").contains("s3cr3t-password"));
    }
}
