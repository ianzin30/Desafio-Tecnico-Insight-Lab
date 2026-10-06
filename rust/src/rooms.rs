use matrix_sdk::ruma::UInt;
use matrix_sdk::ruma::api::client::filter::{
    Filter as EventFilter, FilterDefinition, LazyLoadOptions,
};
use matrix_sdk::ruma::api::client::sync::sync_events::v3::Filter;
use matrix_sdk::{Client, Room, StoreError};

/// A joined conversation, as exposed by the core.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomSummary {
    /// Matrix room ID, e.g. `!abc:matrix.org`.
    pub id: String,
    /// Name to show, computed by the Matrix SDK following the spec algorithm:
    /// explicit name, then canonical alias, then member names (as in DMs),
    /// falling back to `Empty Room`.
    pub display_name: String,
    /// Whether the room is a direct chat (listed in the user's `m.direct`).
    pub is_direct: bool,
}

/// Joined conversation-like rooms known by `client`, sorted by room ID.
///
/// Spaces are excluded: they group rooms and are not conversations. The
/// order carries no meaning (e.g. not "most recent first"); it only makes the
/// result deterministic.
pub(crate) async fn joined_room_summaries(client: &Client) -> Result<Vec<RoomSummary>, StoreError> {
    let mut summaries = Vec::new();
    for room in client.joined_rooms() {
        if !room.is_space() {
            summaries.push(summarize(&room).await?);
        }
    }
    summaries.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(summaries)
}

/// `/sync` filter for listing rooms: no timeline events.
pub(crate) fn rooms_sync_filter() -> Filter {
    sync_filter(0)
}

/// `/sync` filter for continuous sync: at most `REALTIME_TIMELINE_LIMIT`
/// timeline events per room and sync (more are reported as a gap).
pub(crate) fn realtime_sync_filter() -> Filter {
    sync_filter(REALTIME_TIMELINE_LIMIT)
}

const REALTIME_TIMELINE_LIMIT: u32 = 50;

/// Only data that can be recovered later or is transient is reduced: room
/// state and account data skipped by a sync are never resent by the following
/// incremental syncs, so they are kept in full.
fn sync_filter(timeline_limit: u32) -> Filter {
    let mut filter = FilterDefinition::default();
    // Limited timeline: the server marks it `limited` when events were
    // skipped, so history stays reachable later through pagination.
    filter.room.timeline.limit = Some(UInt::from(timeline_limit));
    // Lazy-load members: the server only sends those needed (the room
    // summary heroes used to name DMs, timeline senders); others can be
    // fetched on demand.
    filter.room.state.lazy_load_options = LazyLoadOptions::Enabled {
        include_redundant_members: false,
    };
    // Transient data, useless once missed.
    filter.presence = EventFilter::ignore_all();
    filter.room.ephemeral.not_types = vec!["m.typing".to_owned()];
    Filter::FilterDefinition(filter)
}

async fn summarize(room: &Room) -> Result<RoomSummary, StoreError> {
    Ok(RoomSummary {
        id: room.room_id().to_string(),
        display_name: room.display_name().await?.to_string(),
        is_direct: room.is_direct().await?,
    })
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};
    use tempfile::TempDir;
    use wiremock::ResponseTemplate;

    use crate::test_support::*;
    use crate::{CoreError, RestoreOutcome, RoomSummary};

    fn state_event(event_type: &str, state_key: &str, content: Value) -> Value {
        json!({
            "type": event_type,
            "state_key": state_key,
            "content": content,
            "sender": "@alice:example.org",
            "event_id": format!("${event_type}-{state_key}"),
            "origin_server_ts": 1,
        })
    }

    fn joined_room(state: Vec<Value>, summary: Value) -> Value {
        json!({
            "state": { "events": state },
            "timeline": { "events": [] },
            "summary": summary,
        })
    }

    /// A `/sync` response with:
    /// - a group room with an explicit name;
    /// - a DM (listed in `m.direct`) whose name is computed from its member;
    /// - a space;
    /// - an invited room and a left room.
    fn sync_body() -> Value {
        json!({
            "next_batch": "s1",
            "account_data": { "events": [{
                "type": "m.direct",
                "content": { "@joao:example.org": ["!dm:example.org"] },
            }]},
            "rooms": {
                "join": {
                    "!group:example.org": joined_room(
                        vec![state_event("m.room.name", "", json!({ "name": "Desenvolvimento" }))],
                        json!({}),
                    ),
                    "!dm:example.org": joined_room(
                        vec![
                            state_event("m.room.member", "@alice:example.org",
                                json!({ "membership": "join", "displayname": "Alice" })),
                            state_event("m.room.member", "@joao:example.org",
                                json!({ "membership": "join", "displayname": "João" })),
                        ],
                        json!({
                            "m.heroes": ["@joao:example.org"],
                            "m.joined_member_count": 2,
                            "m.invited_member_count": 0,
                        }),
                    ),
                    "!space:example.org": joined_room(
                        vec![
                            state_event("m.room.create", "",
                                json!({ "creator": "@alice:example.org", "type": "m.space" })),
                            state_event("m.room.name", "", json!({ "name": "Empresa" })),
                        ],
                        json!({}),
                    ),
                },
                "invite": {
                    "!invited:example.org": { "invite_state": { "events": [{
                        "type": "m.room.name",
                        "state_key": "",
                        "content": { "name": "Convite" },
                        "sender": "@bob:example.org",
                    }]}},
                },
                "leave": {
                    "!left:example.org": {
                        "state": { "events": [] },
                        "timeline": { "events": [] },
                    },
                },
            },
        })
    }

    fn expected_rooms() -> Vec<RoomSummary> {
        vec![
            RoomSummary {
                id: "!dm:example.org".to_owned(),
                display_name: "João".to_owned(),
                is_direct: true,
            },
            RoomSummary {
                id: "!group:example.org".to_owned(),
                display_name: "Desenvolvimento".to_owned(),
                is_direct: false,
            },
        ]
    }

    #[tokio::test]
    async fn rooms_require_authentication_without_any_request() {
        let server = mock_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();

        assert!(matches!(
            core.refresh_rooms().await,
            Err(CoreError::NotAuthenticated)
        ));
        assert!(matches!(
            core.cached_rooms().await,
            Err(CoreError::NotAuthenticated)
        ));
        assert!(server.received_requests().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn refresh_lists_only_joined_conversations() {
        let server = alice_homeserver().await;
        mock_sync_response(
            &server,
            ResponseTemplate::new(200).set_body_json(sync_body()),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        let rooms = core.refresh_rooms().await.unwrap();

        // Invited, left and space rooms are excluded; order is by room ID.
        assert_eq!(rooms, expected_rooms());
    }

    /// The `/sync` requests received by the mock homeserver.
    async fn sync_requests(server: &wiremock::MockServer) -> Vec<wiremock::Request> {
        server
            .received_requests()
            .await
            .unwrap()
            .into_iter()
            .filter(|request| request.url.path() == "/_matrix/client/v3/sync")
            .collect()
    }

    fn query_param(request: &wiremock::Request, name: &str) -> Option<String> {
        request
            .url
            .query_pairs()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.into_owned())
    }

    #[tokio::test]
    async fn sync_uses_the_rooms_filter_and_continues_from_the_last_token() {
        let server = alice_homeserver().await;
        mock_sync_response(
            &server,
            ResponseTemplate::new(200).set_body_json(sync_body()),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        assert_eq!(core.refresh_rooms().await.unwrap(), expected_rooms());
        assert_eq!(core.refresh_rooms().await.unwrap(), expected_rooms());

        let requests = sync_requests(&server).await;
        assert_eq!(requests.len(), 2);
        // First sync from scratch, second one resumes from `next_batch`.
        assert_eq!(query_param(&requests[0], "since"), None);
        assert_eq!(query_param(&requests[1], "since").as_deref(), Some("s1"));
        assert_eq!(query_param(&requests[0], "timeout").as_deref(), Some("0"));
        for request in &requests {
            let filter: Value =
                serde_json::from_str(&query_param(request, "filter").expect("filter")).unwrap();
            assert_eq!(filter["room"]["timeline"]["limit"], 0);
            assert_eq!(filter["room"]["state"]["lazy_load_members"], true);
            assert_eq!(filter["presence"]["types"], json!([]));
            assert_eq!(
                filter["room"]["ephemeral"]["not_types"],
                json!(["m.typing"])
            );
            // Room state and account data are not restricted.
            assert!(filter["room"]["state"].get("types").is_none());
            assert!(filter.get("account_data").is_none());
        }
    }

    #[tokio::test]
    async fn hanging_homeserver_fails_within_the_request_policy() {
        // Not pooled, so the delayed response does not leak to other tests.
        let server = wiremock::MockServer::builder().start().await;
        mock_versions(&server).await;
        mock_login_response(&server, login_success("@alice:example.org")).await;
        // Accepts the connection but never answers in time.
        mock_sync_response(
            &server,
            ResponseTemplate::new(200)
                .set_body_json(sync_body())
                .set_delay(std::time::Duration::from_secs(60)),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        let started = std::time::Instant::now();
        let err = core.refresh_rooms().await.unwrap_err();
        let elapsed = started.elapsed();

        // 2 attempts × 5 s timeout + backoff ≈ 10.5 s, instead of ~90 s before.
        assert!(
            matches!(err, CoreError::HomeserverUnreachable(_)),
            "{err:?}"
        );
        assert!(
            elapsed < std::time::Duration::from_secs(20),
            "took {elapsed:?}"
        );
        assert_eq!(sync_requests(&server).await.len(), 2);
        assert!(core.current_user().is_some());
    }

    #[tokio::test]
    async fn cached_rooms_are_empty_before_the_first_sync() {
        let server = alice_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let core = logged_in_core(&server, &data_dir).await;

        assert_eq!(core.cached_rooms().await.unwrap(), vec![]);
    }

    #[tokio::test]
    async fn synced_rooms_survive_a_restart_without_syncing_again() {
        let server = alice_homeserver().await;
        mock_sync_response(
            &server,
            ResponseTemplate::new(200).set_body_json(sync_body()),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        core.refresh_rooms().await.unwrap();
        drop(core);
        let requests_before = server.received_requests().await.unwrap().len();

        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
        assert_eq!(
            core.restore_session().await.unwrap(),
            RestoreOutcome::Restored
        );

        assert_eq!(core.cached_rooms().await.unwrap(), expected_rooms());
        assert_eq!(
            server.received_requests().await.unwrap().len(),
            requests_before
        );
    }

    #[tokio::test]
    async fn revoked_token_discards_the_session() {
        let server = alice_homeserver().await;
        mock_sync_response(
            &server,
            ResponseTemplate::new(401).set_body_json(json!({
                "errcode": "M_UNKNOWN_TOKEN",
                "error": "Invalid access token",
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        drop(logged_in_core(&server, &data_dir).await);
        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
        core.restore_session().await.unwrap();

        let err = core.refresh_rooms().await.unwrap_err();

        assert!(matches!(err, CoreError::SessionRevoked), "{err:?}");
        assert_eq!(core.current_user(), None);
        assert!(!session_file(&data_dir).exists());
    }

    #[tokio::test]
    async fn invalid_sync_response_is_a_sync_failure() {
        let server = alice_homeserver().await;
        mock_sync_response(
            &server,
            ResponseTemplate::new(200).set_body_string("not json"),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;

        let err = core.refresh_rooms().await.unwrap_err();

        assert!(matches!(err, CoreError::SyncFailed(_)), "{err:?}");
        assert!(core.current_user().is_some());
    }

    #[tokio::test]
    async fn unreachable_homeserver_during_sync_is_reported() {
        // Not pooled: the server really shuts down when dropped.
        let server = wiremock::MockServer::builder().start().await;
        mock_versions(&server).await;
        mock_login_response(&server, login_success("@alice:example.org")).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        drop(server);

        let err = core.refresh_rooms().await.unwrap_err();

        assert!(
            matches!(err, CoreError::HomeserverUnreachable(_)),
            "{err:?}"
        );
        assert!(core.current_user().is_some());
    }
}
