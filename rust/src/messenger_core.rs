use matrix_sdk::Client;

use crate::CoreError;
use crate::homeserver::parse_homeserver_url;

/// An active instance of the messaging core.
///
/// Owns the single Matrix [`Client`] used for every operation of this
/// instance; the client is created once in [`MessengerCore::new`] and never
/// rebuilt.
#[derive(Debug)]
pub struct MessengerCore {
    client: Client,
}

impl MessengerCore {
    /// Creates a core bound to the given homeserver URL
    /// (e.g. `https://matrix.org`).
    ///
    /// No request is sent to the homeserver here: the address is used as-is,
    /// without `.well-known` discovery, and the client state lives in memory.
    pub async fn new(homeserver_url: &str) -> Result<Self, CoreError> {
        let url = parse_homeserver_url(homeserver_url)?;

        let client = Client::builder()
            .homeserver_url(url)
            .build()
            .await
            .map_err(|err| CoreError::ClientInitialization(err.into()))?;

        Ok(Self { client })
    }

    /// The homeserver URL the client is configured for.
    pub fn homeserver(&self) -> String {
        self.client.homeserver().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn builds_client_for_homeserver() {
        let core = MessengerCore::new("https://matrix.org").await.unwrap();

        assert_eq!(core.homeserver(), "https://matrix.org/");
    }

    #[tokio::test]
    async fn rejects_invalid_homeserver_without_building_client() {
        let err = MessengerCore::new("matrix.org").await.unwrap_err();

        assert!(matches!(err, CoreError::InvalidHomeserver { .. }));
    }
}
