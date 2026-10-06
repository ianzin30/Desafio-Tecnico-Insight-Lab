//! Continuous sync: a background task that keeps the Matrix client in sync
//! and turns new data into [`CoreEvent`]s.
//!
//! The task runs its own loop over `Client::sync_once` (the SDK's
//! `sync_stream` is the same loop without error backoff), which lets the core
//! choose the filter of each request, back off on errors and stop at any time.
//!
//! Baseline: the first sync of every run uses the rooms-only filter (no
//! timeline) and never emits messages, so history received while the app was
//! closed or before `start_sync` is not reported as new. Only events of the
//! following syncs are.

use std::collections::{HashSet, VecDeque};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use matrix_sdk::Client;
use matrix_sdk::config::SyncSettings;
use matrix_sdk::ruma::api::error::ErrorKind;
use matrix_sdk::sync::SyncResponse;
use tokio::sync::{broadcast, oneshot, watch};
use tokio::task::JoinHandle;
use tokio::time::Instant;

use crate::messages::{Message, to_message};
use crate::rooms::{RoomSummary, joined_room_summaries, realtime_sync_filter, rooms_sync_filter};
use crate::storage::Storage;

/// Capacity of the event channel; a receiver lagging further behind gets
/// [`CoreEvent::EventsLost`].
pub(crate) const EVENT_CHANNEL_CAPACITY: usize = 256;

/// How long the server may hold a sync request open when nothing happens.
const LONG_POLL_TIMEOUT: Duration = Duration::from_secs(30);

/// Minimum delay between two syncs, in case the server answers immediately.
const MIN_SYNC_INTERVAL: Duration = Duration::from_millis(500);

/// Backoff after a failed sync: doubles from the first value up to the last.
const RETRY_BACKOFF: (Duration, Duration) = (Duration::from_secs(1), Duration::from_secs(30));

/// Number of recent message IDs remembered to drop duplicates.
const RECENT_MESSAGE_IDS: usize = 1024;

/// State of the continuous sync.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncState {
    /// Not running.
    Stopped,
    /// Started; the baseline sync has not completed yet.
    Starting,
    /// Up to date with the homeserver.
    Running,
    /// The last sync failed (e.g. offline); retrying with backoff.
    Recovering,
}

/// Event emitted by the core while the continuous sync runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreEvent {
    /// A new text message arrived (including the user's own messages, once
    /// confirmed by the homeserver). Emitted once per event ID.
    MessageReceived { room_id: String, message: Message },
    /// The joined rooms list changed: call
    /// [`cached_rooms`](crate::MessengerCore::cached_rooms) for the new one.
    RoomsChanged,
    /// Some messages of this room were not delivered by the sync (too many
    /// since the previous one): reload them with
    /// [`load_messages`](crate::MessengerCore::load_messages).
    TimelineGap { room_id: String },
    /// The sync state changed.
    SyncStateChanged(SyncState),
    /// The homeserver rejected the access token: the sync stopped and the
    /// local session was removed. A new login is required.
    SessionRevoked,
    /// This receiver fell behind and `count` events were dropped: reload the
    /// rooms and the open room's messages.
    EventsLost { count: u64 },
}

/// Receiver of [`CoreEvent`]s, from
/// [`subscribe_events`](crate::MessengerCore::subscribe_events).
#[derive(Debug)]
pub struct CoreEvents(broadcast::Receiver<CoreEvent>);

impl CoreEvents {
    pub(crate) fn new(receiver: broadcast::Receiver<CoreEvent>) -> Self {
        Self(receiver)
    }

    /// Waits for the next event; `None` once the core is dropped.
    pub async fn recv(&mut self) -> Option<CoreEvent> {
        match self.0.recv().await {
            Ok(event) => Some(event),
            Err(broadcast::error::RecvError::Lagged(count)) => {
                Some(CoreEvent::EventsLost { count })
            }
            Err(broadcast::error::RecvError::Closed) => None,
        }
    }
}

/// Channels shared by the core and its sync task.
#[derive(Debug, Clone)]
pub(crate) struct EventBus {
    events: broadcast::Sender<CoreEvent>,
    state: Arc<watch::Sender<SyncState>>,
}

impl EventBus {
    pub fn new() -> Self {
        Self {
            events: broadcast::channel(EVENT_CHANNEL_CAPACITY).0,
            state: Arc::new(watch::Sender::new(SyncState::Stopped)),
        }
    }

    pub fn subscribe(&self) -> CoreEvents {
        CoreEvents::new(self.events.subscribe())
    }

    pub fn state(&self) -> SyncState {
        *self.state.borrow()
    }

    fn emit(&self, event: CoreEvent) {
        // No receiver is not an error: events are optional to consume.
        let _ = self.events.send(event);
    }

    fn set_state(&self, state: SyncState) {
        if self.state.send_replace(state) != state {
            self.emit(CoreEvent::SyncStateChanged(state));
        }
    }
}

/// Why the sync task ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SyncExit {
    Stopped,
    SessionRevoked,
}

/// Handle owning the sync task. Dropping it aborts the task.
#[derive(Debug)]
pub(crate) struct SyncHandle {
    stop: Option<oneshot::Sender<()>>,
    task: JoinHandle<SyncExit>,
    /// Set by the task when the homeserver rejected the token, so the core
    /// stops reporting a user before it reconciles its state.
    session_revoked: Arc<AtomicBool>,
}

impl SyncHandle {
    pub fn spawn(client: Client, storage: Storage, own_user_id: String, bus: EventBus) -> Self {
        let (stop, stop_rx) = oneshot::channel();
        let session_revoked = Arc::new(AtomicBool::new(false));
        let task = SyncTask {
            client,
            storage,
            own_user_id,
            bus,
            stop: stop_rx,
            session_revoked: session_revoked.clone(),
            recent_ids: RecentIds::default(),
        };
        Self {
            stop: Some(stop),
            task: tokio::spawn(task.run()),
            session_revoked,
        }
    }

    pub fn is_finished(&self) -> bool {
        self.task.is_finished()
    }

    pub fn session_revoked(&self) -> bool {
        self.session_revoked.load(Ordering::Acquire)
    }

    /// Asks the task to stop and waits for it to end.
    pub async fn stop(mut self) -> SyncExit {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        (&mut self.task).await.unwrap_or(SyncExit::Stopped)
    }
}

impl Drop for SyncHandle {
    fn drop(&mut self) {
        self.task.abort();
    }
}

struct SyncTask {
    client: Client,
    storage: Storage,
    own_user_id: String,
    bus: EventBus,
    stop: oneshot::Receiver<()>,
    session_revoked: Arc<AtomicBool>,
    recent_ids: RecentIds,
}

impl SyncTask {
    async fn run(mut self) -> SyncExit {
        self.bus.set_state(SyncState::Starting);
        let exit = self.sync_loop().await;
        self.bus.set_state(SyncState::Stopped);
        exit
    }

    async fn sync_loop(&mut self) -> SyncExit {
        let mut rooms = self.joined_rooms().await;
        let mut baseline_done = false;
        let mut backoff = RETRY_BACKOFF.0;
        let mut last_sync: Option<Instant> = None;

        loop {
            if let Some(last_sync) = last_sync {
                let elapsed = last_sync.elapsed();
                if elapsed < MIN_SYNC_INTERVAL && self.sleep(MIN_SYNC_INTERVAL - elapsed).await {
                    return SyncExit::Stopped;
                }
            }
            last_sync = Some(Instant::now());

            // The SDK reuses its stored sync token, so each sync (including
            // the first one after a restart) continues from the previous one.
            let settings = if baseline_done {
                SyncSettings::new()
                    .timeout(LONG_POLL_TIMEOUT)
                    .filter(realtime_sync_filter())
            } else {
                SyncSettings::new()
                    .timeout(Duration::ZERO)
                    .filter(rooms_sync_filter())
            };
            let result = tokio::select! {
                _ = &mut self.stop => return SyncExit::Stopped,
                result = self.client.sync_once(settings) => result,
            };

            match result {
                Ok(response) => {
                    if baseline_done {
                        self.emit_timeline_events(&response);
                    }
                    baseline_done = true;
                    backoff = RETRY_BACKOFF.0;

                    let current = self.joined_rooms().await;
                    if current != rooms {
                        rooms = current;
                        self.bus.emit(CoreEvent::RoomsChanged);
                    }
                    self.bus.set_state(SyncState::Running);
                }
                Err(err)
                    if matches!(
                        err.client_api_error_kind(),
                        Some(ErrorKind::UnknownToken(_))
                    ) =>
                {
                    // Terminal: never restore this session again. The core
                    // rebuilds its client on its next call.
                    let _ = self.storage.remove_session();
                    self.session_revoked.store(true, Ordering::Release);
                    self.bus.emit(CoreEvent::SessionRevoked);
                    return SyncExit::SessionRevoked;
                }
                Err(_) => {
                    // Anything else (offline, timeout, server error, invalid
                    // response) is retried with backoff until stopped.
                    self.bus.set_state(SyncState::Recovering);
                    if self.sleep(backoff).await {
                        return SyncExit::Stopped;
                    }
                    backoff = (backoff * 2).min(RETRY_BACKOFF.1);
                }
            }
        }
    }

    fn emit_timeline_events(&mut self, response: &SyncResponse) {
        for (room_id, update) in &response.rooms.joined {
            if update.timeline.limited {
                self.bus.emit(CoreEvent::TimelineGap {
                    room_id: room_id.to_string(),
                });
            }
            for event in &update.timeline.events {
                let Some(message) = to_message(event, &self.own_user_id) else {
                    continue;
                };
                if self.recent_ids.insert(&message.id) {
                    self.bus.emit(CoreEvent::MessageReceived {
                        room_id: room_id.to_string(),
                        message,
                    });
                }
            }
        }
    }

    async fn joined_rooms(&self) -> Vec<RoomSummary> {
        joined_room_summaries(&self.client)
            .await
            .unwrap_or_default()
    }

    /// Sleeps unless asked to stop first; returns `true` if stopped.
    async fn sleep(&mut self, duration: Duration) -> bool {
        tokio::select! {
            _ = &mut self.stop => true,
            _ = tokio::time::sleep(duration) => false,
        }
    }
}

/// Bounded set of the most recently emitted message IDs.
#[derive(Default)]
struct RecentIds {
    ids: HashSet<String>,
    order: VecDeque<String>,
}

impl RecentIds {
    /// Records `id`; returns `false` if it was already recorded.
    fn insert(&mut self, id: &str) -> bool {
        if self.ids.contains(id) {
            return false;
        }
        if self.order.len() == RECENT_MESSAGE_IDS
            && let Some(oldest) = self.order.pop_front()
        {
            self.ids.remove(&oldest);
        }
        self.ids.insert(id.to_owned());
        self.order.push_back(id.to_owned());
        true
    }
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn recent_ids_drop_duplicates_with_bounded_memory() {
        let mut ids = RecentIds::default();
        assert!(ids.insert("$a"));
        assert!(!ids.insert("$a"));

        for i in 0..RECENT_MESSAGE_IDS {
            ids.insert(&format!("$fill{i}"));
        }
        assert_eq!(ids.ids.len(), RECENT_MESSAGE_IDS);
        // "$a" was evicted as the oldest entry.
        assert!(ids.insert("$a"));
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use serde_json::{Value, json};
    use tempfile::TempDir;
    use wiremock::matchers::{method, path, query_param, query_param_is_missing};
    use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

    use crate::test_support::*;
    use crate::{CoreError, CoreEvent, CoreEvents, RoomSummary, SyncState};

    const ROOM_A: &str = "!a:example.org";
    const ROOM_B: &str = "!b:example.org";

    /// Answers any unscripted `/sync` like an idle server after a short long
    /// poll: nothing new, same token.
    struct IdleSync;

    impl Respond for IdleSync {
        fn respond(&self, request: &Request) -> ResponseTemplate {
            let since = request
                .url
                .query_pairs()
                .find(|(key, _)| key == "since")
                .map(|(_, value)| value.into_owned())
                .unwrap_or_else(|| "s0".to_owned());
            ResponseTemplate::new(200)
                .set_body_json(json!({ "next_batch": since }))
                .set_delay(Duration::from_millis(100))
        }
    }

    /// A homeserver for `@alice:example.org` whose `/sync` answers are
    /// scripted with [`script_sync`] and otherwise idle.
    async fn realtime_homeserver() -> MockServer {
        let server = alice_homeserver().await;
        Mock::given(method("GET"))
            .and(path("/_matrix/client/v3/sync"))
            .respond_with(IdleSync)
            .with_priority(10)
            .mount(&server)
            .await;
        server
    }

    /// Answers the `/sync` request with this `since` token (`None` for the
    /// first sync of a session).
    async fn script_sync(server: &MockServer, since: Option<&str>, response: ResponseTemplate) {
        let mock = Mock::given(method("GET")).and(path("/_matrix/client/v3/sync"));
        let mock = match since {
            Some(since) => mock.and(query_param("since", since)),
            None => mock.and(query_param_is_missing("since")),
        };
        mock.respond_with(response)
            .with_priority(5)
            .mount(server)
            .await;
    }

    fn sync_ok(body: Value) -> ResponseTemplate {
        ResponseTemplate::new(200).set_body_json(body)
    }

    fn text_event(event_id: &str, sender: &str, ts: u64, body: &str) -> Value {
        json!({
            "type": "m.room.message",
            "event_id": event_id,
            "sender": sender,
            "origin_server_ts": ts,
            "content": { "msgtype": "m.text", "body": body },
        })
    }

    fn name_event(name: &str) -> Value {
        json!({
            "type": "m.room.name", "state_key": "", "event_id": format!("$name-{name}"),
            "sender": "@alice:example.org", "origin_server_ts": 1, "content": { "name": name },
        })
    }

    /// A sync response where joined rooms get the given timeline events.
    fn sync_body(next_batch: &str, joined: &[(&str, Vec<Value>)]) -> Value {
        let join: serde_json::Map<_, _> = joined
            .iter()
            .map(|(room_id, events)| {
                (
                    room_id.to_string(),
                    json!({ "state": { "events": [] }, "timeline": { "events": events } }),
                )
            })
            .collect();
        json!({ "next_batch": next_batch, "rooms": { "join": join } })
    }

    /// Receives events until one matches `predicate`; returns all of them.
    async fn events_until(
        events: &mut CoreEvents,
        predicate: impl Fn(&CoreEvent) -> bool,
    ) -> Vec<CoreEvent> {
        let mut received = Vec::new();
        tokio::time::timeout(Duration::from_secs(10), async {
            while let Some(event) = events.recv().await {
                let done = predicate(&event);
                received.push(event);
                if done {
                    return;
                }
            }
            panic!("event channel closed");
        })
        .await
        .unwrap_or_else(|_| panic!("timed out; received {received:?}"));
        received
    }

    async fn until_state(events: &mut CoreEvents, state: SyncState) -> Vec<CoreEvent> {
        events_until(events, |event| *event == CoreEvent::SyncStateChanged(state)).await
    }

    /// Events already emitted, without waiting for new ones.
    async fn drain(events: &mut CoreEvents) -> Vec<CoreEvent> {
        let mut drained = Vec::new();
        while let Ok(Some(event)) =
            tokio::time::timeout(Duration::from_millis(50), events.recv()).await
        {
            drained.push(event);
        }
        drained
    }

    /// Waits until the server received a `/sync` with this `since` token.
    async fn wait_for_sync_since(server: &MockServer, since: &str) {
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let requests = server.received_requests().await.unwrap();
                if requests.iter().any(|request| {
                    request.url.path() == "/_matrix/client/v3/sync"
                        && request
                            .url
                            .query_pairs()
                            .any(|(k, v)| k == "since" && v == since)
                }) {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("no sync with since={since}"));
    }

    fn received_messages(events: &[CoreEvent]) -> Vec<(String, crate::Message)> {
        events
            .iter()
            .filter_map(|event| match event {
                CoreEvent::MessageReceived { room_id, message } => {
                    Some((room_id.clone(), message.clone()))
                }
                _ => None,
            })
            .collect()
    }

    #[tokio::test]
    async fn start_requires_authentication() {
        let server = realtime_homeserver().await;
        let data_dir = TempDir::new().unwrap();
        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();

        assert!(matches!(
            core.start_sync().await,
            Err(CoreError::NotAuthenticated)
        ));
        assert_eq!(core.sync_state(), SyncState::Stopped);
        assert!(server.received_requests().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn start_stop_lifecycle() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();

        core.start_sync().await.unwrap();
        let started = until_state(&mut events, SyncState::Running).await;
        assert_eq!(started[0], CoreEvent::SyncStateChanged(SyncState::Starting));
        assert!(started.contains(&CoreEvent::RoomsChanged));
        assert_eq!(core.sync_state(), SyncState::Running);

        // A second start never creates a second loop.
        assert!(matches!(
            core.start_sync().await,
            Err(CoreError::AlreadySyncing)
        ));
        // While syncing, refresh_rooms reads the continuously synced state.
        let syncs_before = server.received_requests().await.unwrap().len();
        let rooms = core.refresh_rooms().await.unwrap();
        assert_eq!(rooms.len(), 1);

        core.stop_sync().await.unwrap();
        assert_eq!(core.sync_state(), SyncState::Stopped);
        let stopped = drain(&mut events).await;
        assert_eq!(
            stopped.last(),
            Some(&CoreEvent::SyncStateChanged(SyncState::Stopped))
        );
        // Stopped means stopped: no request after stop_sync returned.
        let requests_after_stop = server.received_requests().await.unwrap().len();
        tokio::time::sleep(Duration::from_millis(700)).await;
        assert_eq!(
            server.received_requests().await.unwrap().len(),
            requests_after_stop
        );
        assert!(requests_after_stop >= syncs_before);
        core.stop_sync().await.unwrap(); // idempotent

        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;
        core.stop_sync().await.unwrap();
    }

    #[tokio::test]
    async fn history_is_not_reported_and_new_messages_are_reported_once() {
        let server = realtime_homeserver().await;
        // Baseline with old messages.
        script_sync(
            &server,
            None,
            sync_ok(sync_body(
                "s1",
                &[(
                    ROOM_A,
                    vec![
                        text_event("$old1", "@bob:example.org", 1000, "antiga 1"),
                        text_event("$old2", "@bob:example.org", 2000, "antiga 2"),
                    ],
                )],
            )),
        )
        .await;
        script_sync(
            &server,
            Some("s1"),
            sync_ok(sync_body(
                "s2",
                &[(
                    ROOM_A,
                    vec![
                        text_event("$new", "@bob:example.org", 5000, "Olá"),
                        json!({
                            "type": "m.reaction", "event_id": "$reaction",
                            "sender": "@bob:example.org", "origin_server_ts": 5001,
                            "content": { "m.relates_to": {
                                "rel_type": "m.annotation", "event_id": "$new", "key": "👍" } },
                        }),
                    ],
                )],
            )),
        )
        .await;
        // The server delivers the same event again (e.g. overlapping sync).
        script_sync(
            &server,
            Some("s2"),
            sync_ok(sync_body(
                "s3",
                &[(
                    ROOM_A,
                    vec![text_event("$new", "@bob:example.org", 5000, "Olá")],
                )],
            )),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();

        core.start_sync().await.unwrap();
        wait_for_sync_since(&server, "s3").await;
        core.stop_sync().await.unwrap();

        let all = drain(&mut events).await;
        assert_eq!(
            received_messages(&all),
            vec![(
                ROOM_A.to_owned(),
                crate::Message {
                    id: "$new".to_owned(),
                    sender: "@bob:example.org".to_owned(),
                    body: "Olá".to_owned(),
                    timestamp_ms: 5000,
                    is_own: false,
                }
            )]
        );
    }

    #[tokio::test]
    async fn own_sent_message_is_reported_once_when_confirmed() {
        let server = realtime_homeserver().await;
        Mock::given(method("PUT"))
            .and(wiremock::matchers::path_regex(r"/send/m\.room\.message/"))
            .respond_with(sync_ok(json!({ "event_id": "$sent" })))
            .mount(&server)
            .await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        script_sync(
            &server,
            Some("s1"),
            sync_ok(sync_body(
                "s2",
                &[(
                    ROOM_A,
                    vec![text_event("$sent", "@alice:example.org", 6000, "Oi")],
                )],
            )),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;

        let sent = core.send_text_message(ROOM_A, "Oi").await.unwrap();
        let received = events_until(&mut events, |event| {
            matches!(event, CoreEvent::MessageReceived { .. })
        })
        .await;
        wait_for_sync_since(&server, "s2").await;
        core.stop_sync().await.unwrap();

        let mut messages = received_messages(&received);
        messages.extend(received_messages(&drain(&mut events).await));
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0].1.id, sent.event_id);
        assert!(messages[0].1.is_own);
    }

    #[tokio::test]
    async fn room_changes_are_signaled() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        // Room B joined.
        script_sync(
            &server,
            Some("s1"),
            sync_ok(json!({
                "next_batch": "s2",
                "rooms": { "join": { ROOM_B: {
                    "state": { "events": [name_event("Projeto")] },
                    "timeline": { "events": [] },
                }}},
            })),
        )
        .await;
        // Room A renamed, and an invite arrives.
        script_sync(
            &server,
            Some("s2"),
            sync_ok(json!({
                "next_batch": "s3",
                "rooms": {
                    "join": { ROOM_A: {
                        "state": { "events": [] },
                        "timeline": { "events": [name_event("Equipe")] },
                    }},
                    "invite": { "!invite:example.org": { "invite_state": { "events": [] } } },
                },
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;

        events_until(&mut events, |event| *event == CoreEvent::RoomsChanged).await;
        let rooms: Vec<String> = core
            .cached_rooms()
            .await
            .unwrap()
            .into_iter()
            .map(|room| room.id)
            .collect();
        assert_eq!(rooms, vec![ROOM_A, ROOM_B]);

        events_until(&mut events, |event| *event == CoreEvent::RoomsChanged).await;
        let rooms = core.cached_rooms().await.unwrap();
        assert_eq!(
            rooms[0],
            RoomSummary {
                id: ROOM_A.to_owned(),
                display_name: "Equipe".to_owned(),
                is_direct: false,
            }
        );
        // The invite is not a joined room and does not break the sync.
        assert_eq!(rooms.len(), 2);
        wait_for_sync_since(&server, "s3").await;
        assert_eq!(core.sync_state(), SyncState::Running);
        core.stop_sync().await.unwrap();
    }

    #[tokio::test]
    async fn sync_recovers_from_a_temporary_outage() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        // Both attempts of the next sync fail (the SDK retries once)...
        Mock::given(method("GET"))
            .and(path("/_matrix/client/v3/sync"))
            .and(query_param("since", "s1"))
            .respond_with(ResponseTemplate::new(503))
            .up_to_n_times(2)
            .with_priority(1)
            .mount(&server)
            .await;
        // ...then the server is back.
        script_sync(
            &server,
            Some("s1"),
            sync_ok(sync_body(
                "s2",
                &[(
                    ROOM_A,
                    vec![text_event("$back", "@bob:example.org", 7000, "voltei")],
                )],
            )),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();

        let mut received = events_until(&mut events, |event| {
            matches!(event, CoreEvent::MessageReceived { .. })
        })
        .await;
        // Data of a sync is emitted before the state update that follows it.
        received.extend(until_state(&mut events, SyncState::Running).await);
        let states: Vec<_> = received
            .iter()
            .filter_map(|event| match event {
                CoreEvent::SyncStateChanged(state) => Some(*state),
                _ => None,
            })
            .collect();
        assert_eq!(
            states,
            vec![
                SyncState::Starting,
                SyncState::Running,
                SyncState::Recovering,
                SyncState::Running
            ]
        );
        assert_eq!(received_messages(&received)[0].1.id, "$back");
        core.stop_sync().await.unwrap();
    }

    #[tokio::test]
    async fn revoked_session_stops_the_sync() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        script_sync(
            &server,
            Some("s1"),
            ResponseTemplate::new(401).set_body_json(json!({
                "errcode": "M_UNKNOWN_TOKEN", "error": "Invalid access token",
            })),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();

        let received = until_state(&mut events, SyncState::Stopped).await;
        assert!(received.contains(&CoreEvent::SessionRevoked));
        assert_eq!(core.current_user(), None);
        assert!(!session_file(&data_dir).exists());

        // The loop ended: no retry with the rejected token.
        let syncs = server.received_requests().await.unwrap().len();
        tokio::time::sleep(Duration::from_millis(700)).await;
        assert_eq!(server.received_requests().await.unwrap().len(), syncs);
        assert!(matches!(
            core.start_sync().await,
            Err(CoreError::NotAuthenticated)
        ));
        // A new login works afterwards.
        core.login("alice", "secret").await.unwrap();
    }

    #[tokio::test]
    async fn logout_stops_the_sync_and_a_new_login_can_sync_again() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;

        core.logout().await.unwrap();

        assert_eq!(core.sync_state(), SyncState::Stopped);
        assert!(!session_file(&data_dir).exists());
        let after_logout = drain(&mut events).await;
        assert_eq!(
            after_logout,
            vec![CoreEvent::SyncStateChanged(SyncState::Stopped)]
        );
        assert!(
            tokio::time::timeout(Duration::from_millis(700), events.recv())
                .await
                .is_err(),
            "no event after logout"
        );

        core.login("alice", "secret").await.unwrap();
        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;
        core.stop_sync().await.unwrap();
    }

    #[tokio::test]
    async fn sync_resumes_after_a_restart() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        // Answered after a long poll: still pending when core A stops, so its
        // token stays `s1`.
        script_sync(
            &server,
            Some("s1"),
            sync_ok(sync_body(
                "s2",
                &[(
                    ROOM_A,
                    vec![text_event(
                        "$offline",
                        "@bob:example.org",
                        8000,
                        "enquanto fechado",
                    )],
                )],
            ))
            .set_delay(Duration::from_secs(1)),
        )
        .await;
        script_sync(
            &server,
            Some("s2"),
            sync_ok(sync_body(
                "s3",
                &[(
                    ROOM_A,
                    vec![text_event("$live", "@bob:example.org", 9000, "agora")],
                )],
            )),
        )
        .await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;
        core.stop_sync().await.unwrap();
        drop(core);

        let mut core = test_core(&server.uri(), data_dir.path()).await.unwrap();
        core.restore_session().await.unwrap();
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();

        // The baseline resumes from the persisted token: what arrived while
        // closed is state, not a new message; later events are reported.
        let received = events_until(&mut events, |event| {
            matches!(event, CoreEvent::MessageReceived { .. })
        })
        .await;
        let ids: Vec<_> = received_messages(&received)
            .into_iter()
            .map(|(_, message)| message.id)
            .collect();
        assert_eq!(ids, vec!["$live"]);
        core.stop_sync().await.unwrap();
    }

    #[tokio::test]
    async fn dropping_the_core_ends_the_sync_task() {
        let server = realtime_homeserver().await;
        script_sync(&server, None, sync_ok(sync_body("s1", &[(ROOM_A, vec![])]))).await;
        let data_dir = TempDir::new().unwrap();
        let mut core = logged_in_core(&server, &data_dir).await;
        let mut events = core.subscribe_events();
        core.start_sync().await.unwrap();
        until_state(&mut events, SyncState::Running).await;

        drop(core);

        // The channel closes once the aborted task released its sender.
        tokio::time::timeout(Duration::from_secs(5), async {
            while events.recv().await.is_some() {}
        })
        .await
        .expect("sync task still running after drop");
    }
}
