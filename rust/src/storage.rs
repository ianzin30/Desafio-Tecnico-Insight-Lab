//! On-disk layout of the core's data directory, and session persistence.
//!
//! ```text
//! <data_dir>/
//! ├── session.json   # non-secret session metadata (format 2)
//! └── stores/<id>/   # SQLite stores owned by the Matrix SDK, one per login
//! ```
//!
//! The Matrix SDK persists room state and encryption keys in its SQLite
//! store, but not the authentication tokens: per the SDK documentation the
//! application must persist the session itself. The non-secret part (user
//! and device IDs, homeserver, store name) goes to `session.json`; the
//! secrets (access/refresh tokens and the store's encryption key) go
//! to the OS credential store (see [`crate::secrets`]), under one entry per
//! data directory. Format 1 kept the tokens in `session.json`: it is migrated
//! on first read.
//!
//! Each login gets a brand new store directory, so data from one identity is
//! never reused by another. Store directories not referenced by a restorable
//! session are deleted.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use matrix_sdk::SessionMeta;
use matrix_sdk::authentication::SessionTokens;
use matrix_sdk::authentication::matrix::MatrixSession;
use serde::{Deserialize, Serialize};

use crate::error::BoxError;
use crate::secrets::{SecretStore, SecretStoreError};

const SESSION_FILE: &str = "session.json";
const STORES_DIR: &str = "stores";
const FORMAT_VERSION: u32 = 2;

/// `session.json`, format 2: no secret.
#[derive(Serialize, Deserialize)]
struct SessionFile {
    version: u32,
    homeserver: String,
    store: String,
    #[serde(flatten)]
    meta: SessionMeta,
}

/// `session.json`, format 1 (tokens in plain text). Read for migration only.
#[derive(Deserialize)]
struct SessionFileV1 {
    homeserver: String,
    store: String,
    session: MatrixSession,
}

#[derive(Deserialize)]
struct Versioned {
    version: u32,
}

/// What the credential store holds for a session. Not `Debug`: secrets.
#[derive(Serialize, Deserialize)]
struct SessionSecrets {
    #[serde(flatten)]
    tokens: SessionTokens,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    store_key: Option<String>,
}

/// Everything needed to restore a login. Not `Debug`: it holds secrets.
pub(crate) struct StoredSession {
    pub homeserver: String,
    pub store: String,
    pub session: MatrixSession,
    /// Hex-encoded key of the store's encryption; `None` for stores created
    /// before it was introduced.
    pub store_key: Option<String>,
}

/// Why a persisted session cannot be loaded.
#[derive(Debug)]
pub(crate) enum LoadError {
    /// Corrupted, incomplete or unknown: it can be discarded.
    Invalid(BoxError),
    /// The credential store could not be read: try again later, keep it.
    Unavailable(SecretStoreError),
}

#[derive(Debug, Clone)]
pub(crate) struct Storage {
    data_dir: PathBuf,
    secrets: Arc<dyn SecretStore>,
}

impl Storage {
    pub fn open(data_dir: &Path, secrets: Arc<dyn SecretStore>) -> io::Result<Self> {
        fs::create_dir_all(data_dir.join(STORES_DIR))?;
        let storage = Self {
            data_dir: fs::canonicalize(data_dir)?,
            secrets,
        };
        // A secret without its session file is a leftover (e.g. the store
        // was unavailable when the session was removed): drop it.
        if !storage.has_session() {
            let _ = storage.secrets.delete(&storage.secret_key());
        }
        Ok(storage)
    }

    /// Key of this data directory's secrets in the credential store.
    fn secret_key(&self) -> String {
        self.data_dir.to_string_lossy().into_owned()
    }

    fn session_path(&self) -> PathBuf {
        self.data_dir.join(SESSION_FILE)
    }

    pub fn store_path(&self, store: &str) -> PathBuf {
        self.data_dir.join(STORES_DIR).join(store)
    }

    pub fn has_session(&self) -> bool {
        self.session_path().exists()
    }

    /// Reads the persisted session: `Ok(None)` if there is none. A format 1
    /// file is migrated (secrets moved to the credential store); if that is
    /// not possible yet, it is used as is and migrated on a later read.
    pub fn load_session(&self) -> Result<Option<StoredSession>, LoadError> {
        let bytes = match fs::read(self.session_path()) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(err) => return Err(LoadError::Invalid(err.into())),
        };
        let invalid = |err: serde_json::Error| LoadError::Invalid(err.into());
        let version = serde_json::from_slice::<Versioned>(&bytes)
            .map_err(invalid)?
            .version;
        let stored = match version {
            1 => {
                let file: SessionFileV1 = serde_json::from_slice(&bytes).map_err(invalid)?;
                let stored = StoredSession {
                    homeserver: file.homeserver,
                    store: file.store,
                    session: file.session,
                    store_key: None,
                };
                // Best effort: on failure the plain-text file stays valid.
                if is_valid_store_name(&stored.store) {
                    let _ = self.save_session(&stored);
                }
                stored
            }
            FORMAT_VERSION => {
                let file: SessionFile = serde_json::from_slice(&bytes).map_err(invalid)?;
                let secrets = self
                    .secrets
                    .get(&self.secret_key())
                    .map_err(LoadError::Unavailable)?
                    .ok_or_else(|| LoadError::Invalid("missing session secrets".into()))?;
                let secrets: SessionSecrets = serde_json::from_str(&secrets).map_err(invalid)?;
                StoredSession {
                    homeserver: file.homeserver,
                    store: file.store,
                    session: MatrixSession {
                        meta: file.meta,
                        tokens: secrets.tokens,
                    },
                    store_key: secrets.store_key,
                }
            }
            other => {
                return Err(LoadError::Invalid(
                    format!("unsupported session format version {other}").into(),
                ));
            }
        };
        if !is_valid_store_name(&stored.store) {
            return Err(LoadError::Invalid(
                "invalid store name in session file".into(),
            ));
        }
        Ok(Some(stored))
    }

    /// Persists a session: secrets to the credential store first, then the
    /// metadata file (atomically, owner-only on Unix). On failure nothing
    /// restorable is left behind.
    pub fn save_session(&self, stored: &StoredSession) -> Result<(), BoxError> {
        let secrets = SessionSecrets {
            tokens: stored.session.tokens.clone(),
            store_key: stored.store_key.clone(),
        };
        self.secrets
            .set(&self.secret_key(), &serde_json::to_string(&secrets)?)?;
        let file = SessionFile {
            version: FORMAT_VERSION,
            homeserver: stored.homeserver.clone(),
            store: stored.store.clone(),
            meta: stored.session.meta.clone(),
        };
        if let Err(err) = self.write_session_file(&serde_json::to_vec(&file)?) {
            let _ = self.secrets.delete(&self.secret_key());
            return Err(err.into());
        }
        Ok(())
    }

    fn write_session_file(&self, json: &[u8]) -> io::Result<()> {
        let tmp = self.data_dir.join(format!("{SESSION_FILE}.tmp"));

        let mut options = fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);

        let mut file = options.open(&tmp)?;
        file.write_all(json)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp, self.session_path())
    }

    /// Makes the session unrestorable: the metadata file is removed (this
    /// must succeed), the secrets too (best effort; a leftover is removed by
    /// the next [`Storage::open`]).
    pub fn remove_session(&self) -> io::Result<()> {
        let _ = self.secrets.delete(&self.secret_key());
        match fs::remove_file(self.session_path()) {
            Err(err) if err.kind() != io::ErrorKind::NotFound => Err(err),
            _ => Ok(()),
        }
    }

    /// Creates a new, empty store directory and returns its name.
    pub fn create_store(&self) -> io::Result<String> {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        for attempt in 0u32.. {
            let name = format!("{nanos:x}-{attempt}");
            match fs::create_dir(self.store_path(&name)) {
                Ok(()) => return Ok(name),
                Err(err) if err.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(err) => return Err(err),
            }
        }
        unreachable!("store name space exhausted")
    }

    /// Best-effort removal of every store directory except `keep`.
    ///
    /// Failures are ignored (e.g. a store still open on Windows); leftovers
    /// are retried the next time a core is created.
    pub fn remove_stores_except(&self, keep: &str) {
        let Ok(entries) = fs::read_dir(self.data_dir.join(STORES_DIR)) else {
            return;
        };
        for entry in entries.flatten() {
            if entry.file_name() != keep {
                let _ = fs::remove_dir_all(entry.path());
            }
        }
    }
}

/// Store names are generated by [`Storage::create_store`]; anything else
/// (e.g. a path read from a tampered session file) is rejected.
fn is_valid_store_name(name: &str) -> bool {
    !name.is_empty() && name.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
}

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::{device_id, user_id};

    use super::*;
    use crate::secrets::testing::{UnavailableSecrets, memory_contains};
    use crate::secrets::{SecretStorage, secret_store};

    fn memory() -> Arc<dyn SecretStore> {
        secret_store(SecretStorage::InMemory)
    }

    fn open(dir: &tempfile::TempDir) -> Storage {
        Storage::open(dir.path(), memory()).unwrap()
    }

    fn session() -> MatrixSession {
        MatrixSession {
            meta: SessionMeta {
                user_id: user_id!("@alice:example.org").to_owned(),
                device_id: device_id!("DEVICE").to_owned(),
            },
            tokens: SessionTokens {
                access_token: "secret-access-token".to_owned(),
                refresh_token: None,
            },
        }
    }

    fn stored(store: &str) -> StoredSession {
        StoredSession {
            homeserver: "https://matrix.org/".to_owned(),
            store: store.to_owned(),
            session: session(),
            store_key: Some("00ff".to_owned()),
        }
    }

    fn session_file(dir: &tempfile::TempDir) -> String {
        fs::read_to_string(dir.path().join(SESSION_FILE)).unwrap()
    }

    #[test]
    fn missing_session_is_not_an_error() {
        let dir = tempfile::tempdir().unwrap();

        assert!(open(&dir).load_session().unwrap().is_none());
    }

    #[test]
    fn malformed_session_is_invalid() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);

        for content in ["", "{", r#"{"version": 2}"#, r#"{"version": 9}"#, "null"] {
            fs::write(dir.path().join(SESSION_FILE), content).unwrap();
            assert!(
                matches!(storage.load_session(), Err(LoadError::Invalid(_))),
                "{content:?} should be rejected"
            );
        }
    }

    #[test]
    fn secrets_stay_out_of_the_session_file() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);

        storage.save_session(&stored("ab-0")).unwrap();

        let file = session_file(&dir);
        assert!(file.contains("@alice:example.org"));
        assert!(!file.contains("secret-access-token"));
        assert!(!file.contains("00ff"));
        let loaded = storage.load_session().unwrap().unwrap();
        assert_eq!(loaded.session.tokens.access_token, "secret-access-token");
        assert_eq!(loaded.store_key.as_deref(), Some("00ff"));
        assert_eq!(loaded.store, "ab-0");
    }

    #[test]
    fn a_format_1_session_is_migrated_once() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);
        let v1 = serde_json::json!({
            "version": 1,
            "homeserver": "https://matrix.org/",
            "store": "ab-0",
            "session": session(),
        });
        fs::write(dir.path().join(SESSION_FILE), v1.to_string()).unwrap();
        assert!(session_file(&dir).contains("secret-access-token"));

        let loaded = storage.load_session().unwrap().unwrap();

        assert_eq!(loaded.session.tokens.access_token, "secret-access-token");
        assert_eq!(loaded.store_key, None);
        // Plain-text token gone; the secret moved to the credential store.
        assert!(!session_file(&dir).contains("secret-access-token"));
        assert!(session_file(&dir).contains(r#""version":2"#));
        assert!(memory_contains(&storage.secret_key()));
        let again = storage.load_session().unwrap().unwrap();
        assert_eq!(again.session.tokens.access_token, "secret-access-token");
    }

    #[test]
    fn a_failed_migration_keeps_the_session_usable() {
        let dir = tempfile::tempdir().unwrap();
        let storage = Storage::open(dir.path(), Arc::new(UnavailableSecrets)).unwrap();
        let v1 = serde_json::json!({
            "version": 1,
            "homeserver": "https://matrix.org/",
            "store": "ab-0",
            "session": session(),
        });
        fs::write(dir.path().join(SESSION_FILE), v1.to_string()).unwrap();

        let loaded = storage.load_session().unwrap().unwrap();

        assert_eq!(loaded.session.tokens.access_token, "secret-access-token");
        // Still format 1: migrated on a later start.
        assert!(session_file(&dir).contains(r#""version":1"#));
    }

    #[test]
    fn missing_secrets_make_the_session_invalid() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);
        storage.save_session(&stored("ab-0")).unwrap();
        memory().delete(&storage.secret_key()).unwrap();

        assert!(matches!(storage.load_session(), Err(LoadError::Invalid(_))));
    }

    #[test]
    fn an_unavailable_store_is_not_an_invalid_session() {
        let dir = tempfile::tempdir().unwrap();
        open(&dir).save_session(&stored("ab-0")).unwrap();

        let locked = Storage::open(dir.path(), Arc::new(UnavailableSecrets)).unwrap();

        assert!(matches!(
            locked.load_session(),
            Err(LoadError::Unavailable(_))
        ));
        assert!(dir.path().join(SESSION_FILE).exists());
    }

    #[test]
    fn removing_the_session_removes_its_secrets() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);
        storage.save_session(&stored("ab-0")).unwrap();

        storage.remove_session().unwrap();

        assert!(storage.load_session().unwrap().is_none());
        assert!(!memory_contains(&storage.secret_key()));
    }

    #[test]
    fn leftover_secrets_without_a_session_are_removed_on_open() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);
        memory().set(&storage.secret_key(), "orphan").unwrap();

        let reopened = open(&dir);

        assert!(!memory_contains(&reopened.secret_key()));
    }

    #[test]
    fn store_names_cannot_escape_the_stores_directory() {
        assert!(is_valid_store_name("18f2a-0"));
        for name in ["", "..", "../x", "/tmp", "a/b", "a\\b"] {
            assert!(!is_valid_store_name(name), "{name:?} should be rejected");
        }
    }

    #[test]
    fn create_store_returns_distinct_directories() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);

        let first = storage.create_store().unwrap();
        let second = storage.create_store().unwrap();

        assert_ne!(first, second);
        assert!(storage.store_path(&first).is_dir());
        assert!(storage.store_path(&second).is_dir());
    }

    #[test]
    fn remove_stores_except_keeps_only_the_given_store() {
        let dir = tempfile::tempdir().unwrap();
        let storage = open(&dir);
        let keep = storage.create_store().unwrap();
        let stale = storage.create_store().unwrap();

        storage.remove_stores_except(&keep);

        assert!(storage.store_path(&keep).is_dir());
        assert!(!storage.store_path(&stale).exists());
    }
}
