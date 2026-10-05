use std::error::Error as StdError;

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
    ClientInitialization(#[source] Box<dyn StdError + Send + Sync>),
}
