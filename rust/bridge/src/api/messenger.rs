//! `MessengerApi`: the object Dart holds. It owns one `MessengerCore` for its
//! whole lifetime and forwards every call to it.

use std::ops::{Deref, DerefMut};
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

use flutter_rust_bridge::frb;
use messenger_core::MessengerCore;

use super::types::{
    ApiError, CoreEvent, LogoutOutcome, Message, RestoreOutcome, RoomSummary, SecretStorage,
    SentMessage, SyncState,
};
use crate::frb_generated::StreamSink;

/// Messaging client backed by `messenger_core`.
///
/// Create it once per app session with [`MessengerApi::create`] and keep it:
/// every call uses the same core and Matrix client. Dispose it (Dart
/// `dispose()`) to release it; a running sync is aborted then.
///
/// Concurrency: the object is wrapped by Flutter Rust Bridge in a read-write
/// lock. Methods taking `&mut self` (login, sync, messages, ...) run one at a
/// time, as the core requires; `&self` methods (`cached_rooms`, getters,
/// `events`) only wait for a running `&mut self` call. The continuous sync
/// runs in its own task and never holds this lock.
#[frb(opaque)]
pub struct MessengerApi {
    core: DropInRuntime<MessengerCore>,
    active_event_streams: Arc<AtomicU32>,
}

impl MessengerApi {
    /// Creates the client for `homeserver_url` (e.g. `https://matrix.org`),
    /// storing its data in `data_dir` (an app data directory chosen by the
    /// caller) and its session secrets in `secret_storage`. Does not restore
    /// any session: call `restore_session`.
    pub async fn create(
        homeserver_url: String,
        data_dir: String,
        secret_storage: SecretStorage,
    ) -> Result<Self, ApiError> {
        let core =
            MessengerCore::with_secret_storage(&homeserver_url, data_dir, secret_storage.into())
                .await?;
        Ok(Self {
            core: DropInRuntime {
                value: Some(core),
                // `create` runs on the bridge's Tokio runtime.
                runtime: tokio::runtime::Handle::current(),
            },
            active_event_streams: Arc::default(),
        })
    }

    /// Homeserver URL the client is configured for.
    #[frb(sync)]
    pub fn homeserver(&self) -> String {
        self.core.homeserver()
    }

    /// Matrix ID of the authenticated user, or `None`.
    #[frb(sync)]
    pub fn current_user(&self) -> Option<String> {
        self.core.current_user()
    }

    /// Restores the session persisted by a previous login.
    pub async fn restore_session(&mut self) -> Result<RestoreOutcome, ApiError> {
        Ok(self.core.restore_session().await?.into())
    }

    /// Logs in with a username (or full Matrix ID) and password. The
    /// password is only used for this request and never stored.
    pub async fn login(&mut self, username: String, password: String) -> Result<(), ApiError> {
        Ok(self.core.login(&username, &password).await?)
    }

    /// Logs out (stopping the sync first); always removes the local session.
    pub async fn logout(&mut self) -> Result<LogoutOutcome, ApiError> {
        Ok(self.core.logout().await?.into())
    }

    /// Syncs once with the homeserver (unless the continuous sync runs) and
    /// returns the joined rooms.
    pub async fn refresh_rooms(&mut self) -> Result<Vec<RoomSummary>, ApiError> {
        Ok(convert(self.core.refresh_rooms().await?))
    }

    /// Joined rooms from the local store, without network.
    pub async fn cached_rooms(&self) -> Result<Vec<RoomSummary>, ApiError> {
        Ok(convert(self.core.cached_rooms().await?))
    }

    /// Latest text messages of a joined room from the homeserver, oldest
    /// first, at most `limit` (capped at 100).
    pub async fn load_messages(
        &mut self,
        room_id: String,
        limit: u16,
    ) -> Result<Vec<Message>, ApiError> {
        Ok(convert(self.core.load_messages(&room_id, limit).await?))
    }

    /// Sends a plain text message; returns its event ID.
    pub async fn send_text_message(
        &mut self,
        room_id: String,
        body: String,
    ) -> Result<SentMessage, ApiError> {
        Ok(self.core.send_text_message(&room_id, &body).await?.into())
    }

    /// Starts the continuous sync. Subscribe to `events` first to receive
    /// everything it emits.
    pub async fn start_sync(&mut self) -> Result<(), ApiError> {
        Ok(self.core.start_sync().await?)
    }

    /// Stops the continuous sync; does nothing if it is not running.
    pub async fn stop_sync(&mut self) -> Result<(), ApiError> {
        Ok(self.core.stop_sync().await?)
    }

    /// Current state of the continuous sync.
    #[frb(sync)]
    pub fn sync_state(&self) -> SyncState {
        self.core.sync_state().into()
    }

    /// Stream of the events emitted from now on. Independent of the sync:
    /// subscribing does not start it.
    ///
    /// Each stream is fed by a small task that ends when the client is
    /// disposed (the stream then closes) or once events can no longer be
    /// delivered after the Dart subscription was cancelled. With
    /// flutter_rust_bridge, a cancellation only takes effect when the next
    /// event reaches Dart (`cancel()` completes then) and the task ends on
    /// the following one: don't await `cancel()` when no event may follow;
    /// `dispose()` closes every stream immediately.
    pub async fn events(&self, sink: StreamSink<CoreEvent>) {
        let mut events = self.core.subscribe_events();
        let active = ActiveStream::new(self.active_event_streams.clone());
        flutter_rust_bridge::spawn(async move {
            let _active = active;
            while let Some(event) = events.recv().await {
                if sink.add(event.into()).is_err() {
                    break;
                }
            }
        });
    }

    /// Number of event streams still forwarding events (diagnostics).
    #[frb(sync)]
    pub fn active_event_streams(&self) -> u32 {
        self.active_event_streams.load(Ordering::Acquire)
    }
}

/// Drops its value inside the Tokio runtime.
///
/// Dart releases `MessengerApi` from an arbitrary thread (`dispose()` or
/// garbage collection), but the Matrix SDK needs a Tokio runtime when its
/// stores are closed: dropping the core outside of one aborts the process.
struct DropInRuntime<T> {
    value: Option<T>,
    runtime: tokio::runtime::Handle,
}

impl<T> Deref for DropInRuntime<T> {
    type Target = T;

    fn deref(&self) -> &T {
        self.value.as_ref().expect("value is present until dropped")
    }
}

impl<T> DerefMut for DropInRuntime<T> {
    fn deref_mut(&mut self) -> &mut T {
        self.value.as_mut().expect("value is present until dropped")
    }
}

impl<T> Drop for DropInRuntime<T> {
    fn drop(&mut self) {
        let _runtime = self.runtime.enter();
        drop(self.value.take());
    }
}

/// Counts a running event forwarder until dropped.
struct ActiveStream(Arc<AtomicU32>);

impl ActiveStream {
    fn new(counter: Arc<AtomicU32>) -> Self {
        counter.fetch_add(1, Ordering::AcqRel);
        Self(counter)
    }
}

impl Drop for ActiveStream {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}

fn convert<T, U: From<T>>(items: Vec<T>) -> Vec<U> {
    items.into_iter().map(U::from).collect()
}
