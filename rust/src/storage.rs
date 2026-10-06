//! On-disk layout of the core's data directory.
//!
//! ```text
//! <data_dir>/
//! ├── session.json   # session needed to restore the login (no password)
//! └── stores/<id>/   # SQLite stores owned by the Matrix SDK, one per login
//! ```
//!
//! The Matrix SDK persists room state and encryption keys in its SQLite
//! store, but not the authentication tokens: per the SDK documentation the
//! application must persist the `MatrixSession` itself. It is saved in
//! `session.json` together with the name of the store it belongs to.
//!
//! Each login gets a brand new store directory, so data from one identity is
//! never reused by another. Store directories not referenced by a restorable
//! session are deleted.

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use matrix_sdk::authentication::matrix::MatrixSession;
use serde::{Deserialize, Serialize};

use crate::error::BoxError;

const SESSION_FILE: &str = "session.json";
const STORES_DIR: &str = "stores";
const FORMAT_VERSION: u32 = 1;

/// Everything needed to restore a login.
///
/// Intentionally not `Debug`: it contains the access token.
#[derive(Serialize, Deserialize)]
pub(crate) struct StoredSession {
    pub version: u32,
    pub homeserver: String,
    pub store: String,
    pub session: MatrixSession,
}

impl StoredSession {
    pub fn new(homeserver: String, store: String, session: MatrixSession) -> Self {
        Self {
            version: FORMAT_VERSION,
            homeserver,
            store,
            session,
        }
    }
}

#[derive(Debug, Clone)]
pub(crate) struct Storage {
    data_dir: PathBuf,
}

impl Storage {
    pub fn open(data_dir: &Path) -> io::Result<Self> {
        fs::create_dir_all(data_dir.join(STORES_DIR))?;
        Ok(Self {
            data_dir: data_dir.to_owned(),
        })
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

    /// Reads the persisted session: `Ok(None)` if there is none, an error if
    /// it exists but is unreadable, malformed or of an unknown format.
    pub fn load_session(&self) -> Result<Option<StoredSession>, BoxError> {
        let bytes = match fs::read(self.session_path()) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(err) => return Err(err.into()),
        };
        let stored: StoredSession = serde_json::from_slice(&bytes)?;
        if stored.version != FORMAT_VERSION {
            return Err(format!("unsupported session format version {}", stored.version).into());
        }
        if !is_valid_store_name(&stored.store) {
            return Err("invalid store name in session file".into());
        }
        Ok(Some(stored))
    }

    /// Atomically writes the session file, readable by the current user only
    /// on Unix systems.
    pub fn save_session(&self, stored: &StoredSession) -> io::Result<()> {
        let json = serde_json::to_vec(stored)?;
        let tmp = self.data_dir.join(format!("{SESSION_FILE}.tmp"));

        let mut options = fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);

        let mut file = options.open(&tmp)?;
        file.write_all(&json)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp, self.session_path())
    }

    pub fn remove_session(&self) -> io::Result<()> {
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
    use super::*;

    #[test]
    fn missing_session_is_not_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let storage = Storage::open(dir.path()).unwrap();

        assert!(storage.load_session().unwrap().is_none());
    }

    #[test]
    fn malformed_session_is_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let storage = Storage::open(dir.path()).unwrap();

        for content in ["", "{", r#"{"version": 1}"#, "null"] {
            fs::write(dir.path().join(SESSION_FILE), content).unwrap();
            assert!(
                storage.load_session().is_err(),
                "{content:?} should be rejected"
            );
        }
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
        let storage = Storage::open(dir.path()).unwrap();

        let first = storage.create_store().unwrap();
        let second = storage.create_store().unwrap();

        assert_ne!(first, second);
        assert!(storage.store_path(&first).is_dir());
        assert!(storage.store_path(&second).is_dir());
    }

    #[test]
    fn remove_stores_except_keeps_only_the_given_store() {
        let dir = tempfile::tempdir().unwrap();
        let storage = Storage::open(dir.path()).unwrap();
        let keep = storage.create_store().unwrap();
        let stale = storage.create_store().unwrap();

        storage.remove_stores_except(&keep);

        assert!(storage.store_path(&keep).is_dir());
        assert!(!storage.store_path(&stale).exists());
    }
}
