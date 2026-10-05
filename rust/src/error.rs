use std::error::Error as StdError;

type BoxError = Box<dyn StdError + Send + Sync>;

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
}
