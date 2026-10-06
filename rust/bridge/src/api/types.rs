//! FFI types mirroring the core's public models.
//!
//! They are small copies rather than the core types themselves so the
//! FFI contract stays explicit: 64-bit numbers become `i64` (a plain Dart
//! `int`, whereas `u64` would be a `BigInt`), and errors drop their internal
//! sources, which may hold SDK details.

use messenger_core as core;

/// A joined conversation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomSummary {
    /// Matrix room ID, e.g. `!abc:matrix.org`.
    pub id: String,
    /// Name to show, computed by the Matrix SDK.
    pub display_name: String,
    /// Whether the room is a direct chat.
    pub is_direct: bool,
}

/// A text message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    /// Matrix event ID.
    pub id: String,
    /// Matrix user ID of the sender.
    pub sender: String,
    /// Plain text body.
    pub body: String,
    /// Server timestamp, in milliseconds since the Unix epoch.
    pub timestamp_ms: i64,
    /// Whether the authenticated user sent this message.
    pub is_own: bool,
}

/// Confirmation of a sent message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SentMessage {
    /// Matrix event ID assigned by the homeserver.
    pub event_id: String,
}

/// Result of `restore_session`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RestoreOutcome {
    /// No persisted session (e.g. first run): log in.
    NoSession,
    /// The persisted session was restored.
    Restored,
}

/// Result of `logout`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogoutOutcome {
    /// Revoked on the homeserver and removed locally.
    Complete,
    /// Removed locally only: the homeserver could not be reached.
    LocalOnly,
}

/// State of the continuous sync.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncState {
    Stopped,
    Starting,
    Running,
    Recovering,
}

/// Event emitted while the continuous sync runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreEvent {
    /// A new text message arrived (once per event ID).
    MessageReceived { room_id: String, message: Message },
    /// The joined rooms changed: call `cached_rooms`.
    RoomsChanged,
    /// Messages of this room were skipped: reload them with `load_messages`.
    TimelineGap { room_id: String },
    /// The sync state changed.
    SyncStateChanged { state: SyncState },
    /// The access token was rejected: the session was removed, log in again.
    SessionRevoked,
    /// The stream fell behind and `count` events were dropped: reload state.
    EventsLost { count: i64 },
}

/// Errors returned to Dart. Same meaning as the core's `CoreError`, without
/// internal causes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    InvalidHomeserver { reason: String },
    ClientInitialization,
    AlreadyAuthenticated,
    InvalidCredentials,
    HomeserverUnreachable,
    AuthenticationFailed,
    InvalidSession,
    NotAuthenticated,
    SessionRevoked,
    SyncFailed,
    AlreadySyncing,
    RoomNotFound,
    NotJoined,
    InvalidMessage,
    MessageLoadFailed,
    MessageSendFailed,
    Storage,
}

impl From<core::CoreError> for ApiError {
    fn from(err: core::CoreError) -> Self {
        use core::CoreError as E;
        match err {
            E::InvalidHomeserver { reason, .. } => Self::InvalidHomeserver { reason },
            E::ClientInitialization(_) => Self::ClientInitialization,
            E::AlreadyAuthenticated => Self::AlreadyAuthenticated,
            E::InvalidCredentials => Self::InvalidCredentials,
            E::HomeserverUnreachable(_) => Self::HomeserverUnreachable,
            E::AuthenticationFailed(_) => Self::AuthenticationFailed,
            E::InvalidSession(_) => Self::InvalidSession,
            E::NotAuthenticated => Self::NotAuthenticated,
            E::SessionRevoked => Self::SessionRevoked,
            E::SyncFailed(_) => Self::SyncFailed,
            E::AlreadySyncing => Self::AlreadySyncing,
            E::RoomNotFound => Self::RoomNotFound,
            E::NotJoined => Self::NotJoined,
            E::InvalidMessage => Self::InvalidMessage,
            E::MessageLoadFailed(_) => Self::MessageLoadFailed,
            E::MessageSendFailed(_) => Self::MessageSendFailed,
            E::Storage(_) => Self::Storage,
        }
    }
}

impl From<core::RoomSummary> for RoomSummary {
    fn from(room: core::RoomSummary) -> Self {
        Self {
            id: room.id,
            display_name: room.display_name,
            is_direct: room.is_direct,
        }
    }
}

impl From<core::Message> for Message {
    fn from(message: core::Message) -> Self {
        Self {
            id: message.id,
            sender: message.sender,
            body: message.body,
            timestamp_ms: saturating_i64(message.timestamp_ms),
            is_own: message.is_own,
        }
    }
}

impl From<core::SentMessage> for SentMessage {
    fn from(sent: core::SentMessage) -> Self {
        Self {
            event_id: sent.event_id,
        }
    }
}

impl From<core::RestoreOutcome> for RestoreOutcome {
    fn from(outcome: core::RestoreOutcome) -> Self {
        match outcome {
            core::RestoreOutcome::NoSession => Self::NoSession,
            core::RestoreOutcome::Restored => Self::Restored,
        }
    }
}

impl From<core::LogoutOutcome> for LogoutOutcome {
    fn from(outcome: core::LogoutOutcome) -> Self {
        match outcome {
            core::LogoutOutcome::Complete => Self::Complete,
            core::LogoutOutcome::LocalOnly => Self::LocalOnly,
        }
    }
}

impl From<core::SyncState> for SyncState {
    fn from(state: core::SyncState) -> Self {
        match state {
            core::SyncState::Stopped => Self::Stopped,
            core::SyncState::Starting => Self::Starting,
            core::SyncState::Running => Self::Running,
            core::SyncState::Recovering => Self::Recovering,
        }
    }
}

impl From<core::CoreEvent> for CoreEvent {
    fn from(event: core::CoreEvent) -> Self {
        use core::CoreEvent as E;
        match event {
            E::MessageReceived { room_id, message } => Self::MessageReceived {
                room_id,
                message: message.into(),
            },
            E::RoomsChanged => Self::RoomsChanged,
            E::TimelineGap { room_id } => Self::TimelineGap { room_id },
            E::SyncStateChanged(state) => Self::SyncStateChanged {
                state: state.into(),
            },
            E::SessionRevoked => Self::SessionRevoked,
            E::EventsLost { count } => Self::EventsLost {
                count: saturating_i64(count),
            },
        }
    }
}

/// `u64` values crossing the FFI (timestamps in ms, counters) fit in `i64`
/// in practice; saturate rather than wrap just in case.
fn saturating_i64(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errors_keep_their_meaning_without_internal_details() {
        let err: ApiError =
            core::CoreError::HomeserverUnreachable("connection refused to secret-host".into())
                .into();
        assert_eq!(err, ApiError::HomeserverUnreachable);
        assert!(!format!("{err:?}").contains("secret-host"));
    }

    #[test]
    fn events_convert_with_their_payload() {
        let event: CoreEvent = core::CoreEvent::EventsLost { count: u64::MAX }.into();
        assert_eq!(event, CoreEvent::EventsLost { count: i64::MAX });

        let event: CoreEvent =
            core::CoreEvent::SyncStateChanged(core::SyncState::Recovering).into();
        assert_eq!(
            event,
            CoreEvent::SyncStateChanged {
                state: SyncState::Recovering
            }
        );
    }
}
