use std::error::Error as StdError;

pub(crate) type BoxError = Box<dyn StdError + Send + Sync>;

/// Errors exposed by the core.
///
/// Callers depend on these variants only; underlying Matrix SDK errors are
/// kept as an opaque [`source`](StdError::source) for debugging.
#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    /// The provided homeserver address is not a usable `http(s)` URL.
    #[error("invalid homeserver URL `{url}`: {reason}")]
    InvalidHomeserver { url: String, reason: String },

    /// The Matrix SDK failed to build the client.
    #[error("failed to initialize the Matrix client")]
    ClientInitialization(#[source] BoxError),

    /// A user is already authenticated in this core instance.
    #[error("a user is already authenticated")]
    AlreadyAuthenticated,

    /// The username or password is empty or was rejected by the homeserver.
    #[error("invalid username or password")]
    InvalidCredentials,

    /// The homeserver could not be reached (connection or timeout error).
    #[error("the homeserver could not be reached")]
    HomeserverUnreachable(#[source] BoxError),

    /// Login failed for any other reason (unexpected server response,
    /// rate limiting, ...).
    #[error("authentication failed")]
    AuthenticationFailed(#[source] BoxError),

    /// A persisted session exists but cannot be restored (corrupted file,
    /// unknown format, other homeserver, unusable store, ...). It has been
    /// discarded: the core is unauthenticated and ready for a new login.
    #[error("the stored session is invalid and was discarded")]
    InvalidSession(#[source] BoxError),

    /// The operation requires an authenticated user.
    #[error("no user is authenticated")]
    NotAuthenticated,

    /// The homeserver rejected the access token (e.g. revoked from another
    /// device). The local session has been discarded: log in again.
    #[error("the session is no longer valid on the homeserver")]
    SessionRevoked,

    /// Synchronization failed for a reason other than connectivity or an
    /// invalid session (unexpected server response, ...).
    #[error("synchronization with the homeserver failed")]
    SyncFailed(#[source] BoxError),

    /// Reading or writing the data directory failed.
    #[error("failed to access the data directory")]
    Storage(#[source] BoxError),
}
