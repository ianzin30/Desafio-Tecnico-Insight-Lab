//! Test helpers: a local mock homeserver and temporary data directories.

use serde_json::json;
use tempfile::TempDir;
use wiremock::matchers::{method, path, path_regex};
use wiremock::{Mock, MockServer, ResponseTemplate};

use crate::MessengerCore;

/// A local mock homeserver that advertises a supported spec version and
/// accepts logouts.
pub(crate) async fn mock_homeserver() -> MockServer {
    let server = MockServer::start().await;
    mock_versions(&server).await;
    // Rooms of these tests are not encrypted: the SDK checks it before the
    // first message sent to a room.
    Mock::given(method("GET"))
        .and(path_regex(
            r"^/_matrix/client/v3/rooms/[^/]+/state/m\.room\.encryption/$",
        ))
        .respond_with(ResponseTemplate::new(404).set_body_json(json!({
            "errcode": "M_NOT_FOUND",
            "error": "Event not found",
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

/// A `/sync` response where the user has joined `joined` rooms, is invited
/// to `invited` and has left `left`.
pub(crate) fn rooms_sync_body(
    joined: &[&str],
    invited: &[&str],
    left: &[&str],
) -> serde_json::Value {
    let empty_room = || json!({ "state": { "events": [] }, "timeline": { "events": [] } });
    let join: serde_json::Map<_, _> = joined
        .iter()
        .map(|id| (id.to_string(), empty_room()))
        .collect();
    let leave: serde_json::Map<_, _> = left
        .iter()
        .map(|id| (id.to_string(), empty_room()))
        .collect();
    let invite: serde_json::Map<_, _> = invited
        .iter()
        .map(|id| (id.to_string(), json!({ "invite_state": { "events": [] } })))
        .collect();
    json!({
        "next_batch": "s1",
        "rooms": { "join": join, "invite": invite, "leave": leave },
    })
}

/// A core logged in as `@alice:example.org` whose rooms were refreshed from
/// [`rooms_sync_body`].
pub(crate) async fn core_with_rooms(
    server: &MockServer,
    data_dir: &TempDir,
    joined: &[&str],
    invited: &[&str],
    left: &[&str],
) -> MessengerCore {
    mock_sync_response(
        server,
        ResponseTemplate::new(200).set_body_json(rooms_sync_body(joined, invited, left)),
    )
    .await;
    let mut core = logged_in_core(server, data_dir).await;
    core.refresh_rooms().await.unwrap();
    core
}
