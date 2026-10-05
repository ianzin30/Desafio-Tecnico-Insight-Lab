# messenger_core (Rust)

Native core of the desktop messaging client. It will hold the Matrix
integration and later be exposed to Flutter via Flutter Rust Bridge.

## Status

- `matrix-sdk` 0.19 is configured (default features: E2EE, SQLite stores, rustls).
- `flutter_rust_bridge` 2.13.0 is declared (pinned; the Dart package must use the
  same version). No bridge API, codegen or Flutter project exists yet.
- `MessengerCore::new(homeserver_url, data_dir)` validates an `http(s)` homeserver
  URL (bare server names such as `matrix.org` are rejected: no `.well-known`
  discovery) and builds the single Matrix `Client` owned by that core instance.
- `login(username, password)` authenticates that client and persists the session;
  `restore_session()` resumes it after a restart; `logout()` ends it;
  `current_user()` returns the user ID read from the client.
- **Not implemented yet:** rooms, messages, sync.

```rust
use messenger_core::{MessengerCore, RestoreOutcome};

let mut core = MessengerCore::new("https://matrix.org", &data_dir).await?;
if core.restore_session().await? == RestoreOutcome::NoSession {
    core.login("alice", &password).await?;
}
assert_eq!(core.current_user().as_deref(), Some("@alice:matrix.org"));
```

## Session persistence

The caller provides `data_dir` (later: the Flutter app's per-OS data
directory); the core hardcodes no platform path. Layout:

```text
<data_dir>/
├── session.json   # MatrixSession (user ID, device ID, access token) + store name
└── stores/<id>/   # Matrix SDK SQLite stores (state, encryption keys, caches)
```

- The SDK's SQLite store does not keep the access token, so — as the SDK
  documents — the core saves the `MatrixSession` in `session.json` (written
  atomically, mode `0600` on Unix). **The password is never persisted.** The
  token is stored in plain text; moving it to the OS keychain is future work.
- Each login gets a new store directory; stores not referenced by a
  restorable session are deleted, so a later account never inherits data.
- `restore_session()` returns `NoSession` (first run, not an error),
  `Restored`, or `CoreError::InvalidSession` (corrupted file, other homeserver,
  unusable store): the invalid session is discarded and the core is ready to log in.
  Restoring sends no request: a token revoked server-side surfaces on the next request.
- `logout()` revokes the token on the homeserver, then always deletes the
  session file and the store. If the homeserver is unreachable the local logout
  still happens and `LogoutOutcome::LocalOnly` is returned (the token may stay
  valid server-side).

## Requirements

Rust stable ≥ 1.96 (the `matrix-sdk` MSRV), installed via [rustup](https://rustup.rs):

```bash
rustup component add rustfmt clippy
```

## Verify

Run from this `rust/` directory:

```bash
cargo check
cargo test
cargo fmt --check
cargo clippy --all-targets -- -D warnings
```

The first build compiles the whole Matrix SDK dependency tree and takes a
couple of minutes.

`cargo test` needs no network or credentials: it uses a local mock homeserver
and temporary data directories.

### Optional live test (login, restore, logout)

Ignored by default. Credentials come from the environment only — never commit them:

```bash
MATRIX_HOMESERVER=https://matrix.org MATRIX_USERNAME=alice MATRIX_PASSWORD=... \
    cargo test --test live_login -- --ignored
```
