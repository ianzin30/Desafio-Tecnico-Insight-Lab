//! Where authentication secrets are kept: the operating system's credential
//! store (macOS Keychain, Windows Credential Manager, Secret Service on
//! Linux), through the `keyring` crate. Nothing secret is written to plain
//! files.

use std::collections::HashMap;
use std::fmt;
use std::sync::{Arc, LazyLock, Mutex};

use crate::error::BoxError;

/// Name under which the secrets appear in the credential store.
const SERVICE: &str = "Insight Lab";

/// Which secret store a core uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SecretStorage {
    /// The operating system's credential store. Use this in the app.
    #[default]
    System,
    /// Process memory only (secrets are lost when the process exits). For
    /// automated tests, which must not touch the user's credential store.
    InMemory,
}

/// The secret store failed (locked, unavailable, ...): distinct from "no
/// secret", so a valid session is never discarded because of it.
#[derive(Debug, thiserror::Error)]
#[error("the secure credential store is unavailable")]
pub(crate) struct SecretStoreError(#[source] pub BoxError);

pub(crate) trait SecretStore: Send + Sync {
    fn get(&self, key: &str) -> Result<Option<String>, SecretStoreError>;
    fn set(&self, key: &str, value: &str) -> Result<(), SecretStoreError>;
    /// Deleting a missing secret is not an error.
    fn delete(&self, key: &str) -> Result<(), SecretStoreError>;
}

impl fmt::Debug for dyn SecretStore {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("SecretStore")
    }
}

pub(crate) fn secret_store(kind: SecretStorage) -> Arc<dyn SecretStore> {
    match kind {
        SecretStorage::System => Arc::new(SystemSecrets),
        SecretStorage::InMemory => Arc::new(MemorySecrets),
    }
}

struct SystemSecrets;

impl SystemSecrets {
    fn entry(key: &str) -> Result<keyring::Entry, SecretStoreError> {
        keyring::Entry::new(SERVICE, key).map_err(|err| SecretStoreError(err.into()))
    }
}

impl SecretStore for SystemSecrets {
    fn get(&self, key: &str) -> Result<Option<String>, SecretStoreError> {
        match Self::entry(key)?.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(err) => Err(SecretStoreError(err.into())),
        }
    }

    fn set(&self, key: &str, value: &str) -> Result<(), SecretStoreError> {
        Self::entry(key)?
            .set_password(value)
            .map_err(|err| SecretStoreError(err.into()))
    }

    fn delete(&self, key: &str) -> Result<(), SecretStoreError> {
        match Self::entry(key)?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(err) => Err(SecretStoreError(err.into())),
        }
    }
}

/// Shared by every core of the process, like the system store would be.
static MEMORY: LazyLock<Mutex<HashMap<String, String>>> = LazyLock::new(Mutex::default);

struct MemorySecrets;

impl SecretStore for MemorySecrets {
    fn get(&self, key: &str) -> Result<Option<String>, SecretStoreError> {
        Ok(MEMORY.lock().expect("not poisoned").get(key).cloned())
    }

    fn set(&self, key: &str, value: &str) -> Result<(), SecretStoreError> {
        MEMORY
            .lock()
            .expect("not poisoned")
            .insert(key.to_owned(), value.to_owned());
        Ok(())
    }

    fn delete(&self, key: &str) -> Result<(), SecretStoreError> {
        MEMORY.lock().expect("not poisoned").remove(key);
        Ok(())
    }
}

/// Random 256-bit key for the Matrix SDK's store encryption, hex-encoded.
pub(crate) fn random_store_key() -> Result<String, SecretStoreError> {
    let mut bytes = [0u8; 32];
    getrandom::getrandom(&mut bytes).map_err(|err| SecretStoreError(Box::new(err)))?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;

    /// A secret store that is always unavailable.
    pub struct UnavailableSecrets;

    impl SecretStore for UnavailableSecrets {
        fn get(&self, _: &str) -> Result<Option<String>, SecretStoreError> {
            Err(SecretStoreError("locked".into()))
        }
        fn set(&self, _: &str, _: &str) -> Result<(), SecretStoreError> {
            Err(SecretStoreError("locked".into()))
        }
        fn delete(&self, _: &str) -> Result<(), SecretStoreError> {
            Err(SecretStoreError("locked".into()))
        }
    }

    /// Whether the in-memory store holds a secret under `key`.
    pub fn memory_contains(key: &str) -> bool {
        MEMORY.lock().unwrap().contains_key(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Real credential store round trip. Ignored by default: it writes to the
    /// user's keychain (macOS may ask for permission). Run with
    /// `cargo test -p messenger_core system_secret_store -- --ignored`.
    #[test]
    #[ignore = "uses the operating system's credential store"]
    fn system_secret_store_round_trip() {
        let store = secret_store(SecretStorage::System);
        let key = format!("messenger_core-test-{}", random_store_key().unwrap());

        assert_eq!(store.get(&key).unwrap(), None);
        store.set(&key, "value").unwrap();
        assert_eq!(store.get(&key).unwrap().as_deref(), Some("value"));
        store.delete(&key).unwrap();
        assert_eq!(store.get(&key).unwrap(), None);
        store.delete(&key).unwrap();
    }

    #[test]
    fn store_keys_are_random_256_bit_hex() {
        let a = random_store_key().unwrap();
        assert_eq!(a.len(), 64);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, random_store_key().unwrap());
    }
}
