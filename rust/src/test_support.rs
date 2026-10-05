//! Test helpers: a local mock homeserver and temporary data directories.

use serde_json::json;
use tempfile::TempDir;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

use crate::MessengerCore;

/// A local mock homeserver that advertises a supported spec version and
/// accepts logouts.
pub(crate) async fn mock_homeserver() -> MockServer {
    let server = MockServer::start().await;
    mock_versions(&server).await;
    Mock::given(method("POST"))
        .and(path("/_matrix/client/v3/logout"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
        .mount(&server)
        .await;
    server
}

/// Advertises a supported spec version (fetched before other requests).
pub(crate) async fn mock_versions(server: &MockServer) {
    Mock::given(method("GET"))
        .and(path("/_matrix/client/versions"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "versions": ["v1.11"]
        })))
        .mount(server)
        .await;
}

pub(crate) async fn mock_login_response(server: &MockServer, response: ResponseTemplate) {
    Mock::given(method("POST"))
        .and(path("/_matrix/client/v3/login"))
        .respond_with(response)
        .mount(server)
        .await;
}

pub(crate) fn login_success(user_id: &str) -> ResponseTemplate {
    ResponseTemplate::new(200).set_body_json(json!({
        "user_id": user_id,
        "access_token": "test-access-token",
        "device_id": "TESTDEVICE"
    }))
}

/// A mock homeserver accepting logins as `@alice:example.org`.
pub(crate) async fn alice_homeserver() -> MockServer {
    let server = mock_homeserver().await;
    mock_login_response(&server, login_success("@alice:example.org")).await;
    server
}

pub(crate) async fn logged_in_core(server: &MockServer, data_dir: &TempDir) -> MessengerCore {
    let mut core = MessengerCore::new(&server.uri(), data_dir.path())
        .await
        .unwrap();
    core.login("alice", "secret").await.unwrap();
    core
}

pub(crate) fn session_file(data_dir: &TempDir) -> std::path::PathBuf {
    data_dir.path().join("session.json")
}

pub(crate) fn store_count(data_dir: &TempDir) -> usize {
    std::fs::read_dir(data_dir.path().join("stores"))
        .unwrap()
        .count()
}

pub(crate) async fn mock_sync_response(server: &MockServer, response: ResponseTemplate) {
    Mock::given(method("GET"))
        .and(path("/_matrix/client/v3/sync"))
        .respond_with(response)
        .mount(server)
        .await;
}
