use matrix_sdk::deserialized_responses::TimelineEvent;
use matrix_sdk::room::MessagesOptions;
use matrix_sdk::ruma::UInt;
use matrix_sdk::ruma::events::room::message::{MessageType, Relation};
use matrix_sdk::ruma::events::{
    AnySyncMessageLikeEvent, AnySyncTimelineEvent, SyncMessageLikeEvent,
};

/// Maximum number of events requested by a single
/// [`load_messages`](crate::MessengerCore::load_messages) call.
pub const MAX_MESSAGES: u16 = 100;

/// A text message of a room, as exposed by the core.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    /// Matrix event ID, e.g. `$abc`.
    pub id: String,
    /// Matrix user ID of the sender, e.g. `@alice:matrix.org`.
    pub sender: String,
    /// Plain text body.
    pub body: String,
    /// Server timestamp, in milliseconds since the Unix epoch.
    pub timestamp_ms: u64,
    /// Whether the authenticated user sent this message.
    pub is_own: bool,
}

/// Confirmation of a sent message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SentMessage {
    /// Matrix event ID assigned by the homeserver.
    pub event_id: String,
}

/// `/messages` request for the latest `limit` events of a room, newest first.
///
/// No `from` token: the server starts from the end of the timeline, which does
/// not depend on what the (rooms-only) sync stored. Only message events are
/// requested; `m.room.encrypted` is kept since it may decrypt to a message.
pub(crate) fn latest_messages_options(limit: u16) -> MessagesOptions {
    let mut options = MessagesOptions::backward();
    options.limit = UInt::from(limit);
    options.filter.types = Some(vec![
        "m.room.message".to_owned(),
        "m.room.encrypted".to_owned(),
    ]);
    options
}

/// Converts a timeline event to a [`Message`] if it is a supported text
/// message: an `m.room.message` with `msgtype` `m.text`, not redacted and not
/// an edit. Anything else (media, reactions, state, undecryptable events,
/// ...) yields `None`.
pub(crate) fn to_message(event: &TimelineEvent, own_user_id: &str) -> Option<Message> {
    let Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(
        SyncMessageLikeEvent::Original(event),
    ))) = event.raw().deserialize()
    else {
        return None;
    };
    if matches!(event.content.relates_to, Some(Relation::Replacement(_))) {
        return None;
    }
    let MessageType::Text(text) = event.content.msgtype else {
        return None;
    };

    let sender = event.sender.to_string();
    Some(Message {
        id: event.event_id.to_string(),
        is_own: sender == own_user_id,
        sender,
        body: text.body,
        timestamp_ms: event.origin_server_ts.0.into(),
    })
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};
    use tempfile::TempDir;
    use wiremock::matchers::{method, path_regex};
    use wiremock::{Mock, MockServer, Request, ResponseTemplate};

    use crate::test_support::*;
    use crate::{CoreError, Message, SentMessage};

    const ROOM: &str = "!room:example.org";

    fn message_event(event_id: &str, sender: &str, ts: u64, content: Value) -> Value {
        json!({
            "type": "m.room.message",
            "event_id": event_id,
            "sender": sender,
            "origin_server_ts": ts,
            "room_id": ROOM,
            "content": content,
        })
    }

    /// `/messages` chunk, newest first as the server returns it.
    fn messages_chunk() -> Value {
        json!([
            message_event("$4", "@alice:example.org", 4000,
                json!({ "msgtype": "m.text", "body": "Bom dia" })),
            {
                "type": "m.reaction", "event_id": "$reaction", "sender": "@bob:example.org",
                "origin_server_ts": 3500, "room_id": ROOM,
                "content": { "m.relates_to": {
                    "rel_type": "m.annotation", "event_id": "$1", "key": "👍" } },
            },
            message_event("$3", "@bob:example.org", 3000, json!({
                "msgtype": "m.text", "body": "* Olá!",
                "m.new_content": { "msgtype": "m.text", "body": "Olá!" },
                "m.relates_to": { "rel_type": "m.replace", "event_id": "$1" },
            })),
            message_event("$2", "@bob:example.org", 2000, json!({
                "msgtype": "m.image", "body": "foto.png", "url": "mxc://example.org/abc" })),
            {
                "type": "m.room.topic", "state_key": "", "event_id": "$topic",
                "sender": "@bob:example.org", "origin_server_ts": 1500, "room_id": ROOM,
                "content": { "topic": "Assuntos" },
            },
            message_event("$1", "@bob:example.org", 1000,
                json!({ "msgtype": "m.text", "body": "Olá" })),
        ])
    }

    async fn mock_messages(server: &MockServer, response: ResponseTemplate) {
        Mock::given(method("GET"))
            .and(path_regex(r"^/_matrix/client/v3/rooms/[^/]+/messages$"))
            .respond_with(response)
            .mount(server)
            .await;
    }

    async fn mock_send(server: &MockServer, response: ResponseTemplate) {
        Mock::given(method("PUT"))
            .and(path_regex(
                r"^/_matrix/client/v3/rooms/[^/]+/send/m\.room\.message/[^/]+$",
            ))
            .respond_with(response)
            .mount(server)
            .await;
    }

    async fn requests_matching(server: &MockServer, suffix: &str) -> Vec<Request> {
        server
            .received_requests()
            .await
            .unwrap()
            .into_iter()
            .filter(|request| request.url.path().contains(suffix))
            .collect()
    }

    fn unknown_token() -> ResponseTemplate {
        ResponseTemplate::new(401).set_body_json(json!({
            "errcode": "M_UNKNOWN_TOKEN",
            "error": "Invalid access token",
        }))
    }

    fn query_param(request: &Request, name: &str) -> Option<String> {
        request
            .url
            .query_pairs()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.into_owned())
    }

    #[tokio::test]
    async fn messages_require_authentication_without_any_request() {
        let server = mock_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();

        assert!(matches!(
            core.load_messages(ROOM, 50).await,
            Err(CoreError::NotAuthenticated)
        ));
        assert!(matches!(
            core.send_text_message(ROOM, "Olá").await,
            Err(CoreError::NotAuthenticated)
        ));
        assert!(server.received_requests().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn unknown_or_invalid_room_is_not_found() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;

        for room_id in ["!unknown:example.org", "not a room id"] {
            assert!(matches!(
                core.load_messages(room_id, 50).await,
                Err(CoreError::RoomNotFound)
            ));
            assert!(matches!(
                core.send_text_message(room_id, "Olá").await,
                Err(CoreError::RoomNotFound)
            ));
        }
    }

    #[tokio::test]
    async fn invited_and_left_rooms_are_not_joined() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(
            &server,
            &data_dir,
            &[ROOM],
            &["!invited:example.org"],
            &["!left:example.org"],
        )
        .await;

        for room_id in ["!invited:example.org", "!left:example.org"] {
            assert!(matches!(
                core.load_messages(room_id, 50).await,
                Err(CoreError::NotJoined)
            ));
            assert!(matches!(
                core.send_text_message(room_id, "Olá").await,
                Err(CoreError::NotJoined)
            ));
        }
    }

    #[tokio::test]
    async fn loads_text_messages_oldest_first() {
        let server = alice_homeserver().await;
        mock_messages(
            &server,
            ResponseTemplate::new(200).set_body_json(json!({
                "start": "t2", "end": "t1", "chunk": messages_chunk(),
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;

        let messages = core.load_messages(ROOM, 50).await.unwrap();

        // Reaction, edit, image and state events are not messages.
        assert_eq!(
            messages,
            vec![
                Message {
                    id: "$1".to_owned(),
                    sender: "@bob:example.org".to_owned(),
                    body: "Olá".to_owned(),
                    timestamp_ms: 1000,
                    is_own: false,
                },
                Message {
                    id: "$4".to_owned(),
                    sender: "@alice:example.org".to_owned(),
                    body: "Bom dia".to_owned(),
                    timestamp_ms: 4000,
                    is_own: true,
                },
            ]
        );

        let requests = requests_matching(&server, "/messages").await;
        assert_eq!(requests.len(), 1);
        assert!(
            requests[0]
                .url
                .path()
                .contains("/rooms/!room:example.org/messages")
        );
        assert_eq!(query_param(&requests[0], "dir").as_deref(), Some("b"));
        assert_eq!(query_param(&requests[0], "limit").as_deref(), Some("50"));
        assert_eq!(query_param(&requests[0], "from"), None);
        let filter: Value =
            serde_json::from_str(&query_param(&requests[0], "filter").unwrap()).unwrap();
        assert_eq!(
            filter["types"],
            json!(["m.room.message", "m.room.encrypted"])
        );
    }

    #[tokio::test]
    async fn messages_load_after_a_restart_from_the_persisted_room_list() {
        let server = alice_homeserver().await;
        mock_messages(
            &server,
            ResponseTemplate::new(200).set_body_json(json!({
                "start": "t2", "chunk": messages_chunk(),
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        drop(core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await);

        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
        core.restore_session().await.unwrap();

        // No new sync: the joined room comes from the SDK store, the messages
        // from the homeserver.
        let messages = core.load_messages(ROOM, 50).await.unwrap();
        assert_eq!(messages.len(), 2);
    }

    #[tokio::test]
    async fn limit_is_capped() {
        let server = alice_homeserver().await;
        mock_messages(
            &server,
            ResponseTemplate::new(200).set_body_json(json!({ "start": "t2", "chunk": [] })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;

        assert_eq!(core.load_messages(ROOM, 1000).await.unwrap(), vec![]);
        assert_eq!(core.load_messages(ROOM, 0).await.unwrap(), vec![]);

        let requests = requests_matching(&server, "/messages").await;
        assert_eq!(requests.len(), 1, "a zero limit sends no request");
        assert_eq!(query_param(&requests[0], "limit").as_deref(), Some("100"));
    }

    #[tokio::test]
    async fn sends_a_text_message() {
        let server = alice_homeserver().await;
        mock_send(
            &server,
            ResponseTemplate::new(200).set_body_json(json!({ "event_id": "$sent" })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;

        let sent = core
            .send_text_message(ROOM, "  Tudo certo!\n")
            .await
            .unwrap();

        assert_eq!(
            sent,
            SentMessage {
                event_id: "$sent".to_owned()
            }
        );
        let requests = requests_matching(&server, "/send/m.room.message/").await;
        assert_eq!(requests.len(), 1);
        assert!(
            requests[0]
                .url
                .path()
                .contains("/rooms/!room:example.org/send/")
        );
        let content: Value = serde_json::from_slice(&requests[0].body).unwrap();
        // The body is sent unchanged.
        assert_eq!(
            content,
            json!({ "msgtype": "m.text", "body": "  Tudo certo!\n" })
        );
    }

    #[tokio::test]
    async fn blank_messages_are_rejected_without_a_request() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;
        let requests_before = server.received_requests().await.unwrap().len();

        for body in ["", "   ", "\n\t"] {
            assert!(matches!(
                core.send_text_message(ROOM, body).await,
                Err(CoreError::InvalidMessage)
            ));
        }
        assert_eq!(
            server.received_requests().await.unwrap().len(),
            requests_before
        );
    }

    #[tokio::test]
    async fn revoked_token_discards_the_session() {
        let server = alice_homeserver().await;
        mock_messages(&server, unknown_token()).await;
        mock_send(&server, unknown_token()).await;
        let data_dir = TempDir::new().unwrap();

        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;
        let err = core.load_messages(ROOM, 50).await.unwrap_err();
        assert!(matches!(err, CoreError::SessionRevoked), "{err:?}");
        assert_eq!(core.current_user(), None);
        assert!(!session_file(&data_dir).exists());

        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;
        let err = core.send_text_message(ROOM, "Olá").await.unwrap_err();
        assert!(matches!(err, CoreError::SessionRevoked), "{err:?}");
        assert_eq!(core.current_user(), None);
    }

    #[tokio::test]
    async fn invalid_responses_are_controlled_errors() {
        let server = alice_homeserver().await;
        mock_messages(
            &server,
            ResponseTemplate::new(200).set_body_string("not json"),
        )
        .await;
        mock_send(
            &server,
            ResponseTemplate::new(403).set_body_json(json!({
                "errcode": "M_FORBIDDEN", "error": "You cannot post here",
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;

        let err = core.load_messages(ROOM, 50).await.unwrap_err();
        assert!(matches!(err, CoreError::MessageLoadFailed(_)), "{err:?}");
        let err = core.send_text_message(ROOM, "Olá").await.unwrap_err();
        assert!(matches!(err, CoreError::MessageSendFailed(_)), "{err:?}");
        assert!(core.current_user().is_some());
    }

    #[tokio::test]
    async fn offline_homeserver_is_reported() {
        // Not pooled: the server really shuts down when dropped.
        let server = MockServer::builder().start().await;
        mock_versions(&server).await;
        mock_login_response(&server, login_success("@alice:example.org")).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = core_with_rooms(&server, &data_dir, &[ROOM], &[], &[]).await;
        drop(server);

        let err = core.load_messages(ROOM, 50).await.unwrap_err();
        assert!(
            matches!(err, CoreError::HomeserverUnreachable(_)),
            "{err:?}"
        );
        let err = core.send_text_message(ROOM, "Olá").await.unwrap_err();
        assert!(
            matches!(err, CoreError::HomeserverUnreachable(_)),
            "{err:?}"
        );
        assert!(core.current_user().is_some());
    }
}
