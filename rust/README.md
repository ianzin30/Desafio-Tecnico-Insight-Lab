# messenger_core (Rust)

Native core of the desktop messaging client. It will hold the Matrix
integration and later be exposed to Flutter via Flutter Rust Bridge.

## Status

- `matrix-sdk` 0.19 is configured (default features: E2EE, SQLite stores, rustls).
- `flutter_rust_bridge` 2.13.0 is declared (pinned; the Dart package must use the
  same version). No bridge API, codegen or Flutter project exists yet.
- `MessengerCore::new(homeserver_url)` validates an `http(s)` homeserver URL and
  builds the single Matrix `Client` owned by that core instance. Bare server
  names (`matrix.org`) are rejected: `.well-known` discovery is not performed.
- Building the client sends no request to the homeserver, and its state is kept
  in memory only.
- `login(username, password)` authenticates that same client with a Matrix
  username/password; `current_user()` returns the user ID read from the client.
  A second login on an authenticated core fails with `AlreadyAuthenticated`.
- The session is **in memory only**: it is lost when the process exits. The
  password is never stored by the core.
- **Not implemented yet:** session persistence/restoration, rooms, messages, sync.

```rust
let mut core = messenger_core::MessengerCore::new("https://matrix.org").await?;
core.login("alice", &password).await?;
assert_eq!(core.current_user().as_deref(), Some("@alice:matrix.org"));
```

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

`cargo test` needs no network or credentials: login is tested against a local
mock homeserver.

### Optional live login test

Ignored by default. Credentials come from the environment only — never commit them:

```bash
MATRIX_HOMESERVER=https://matrix.org MATRIX_USERNAME=alice MATRIX_PASSWORD=... \
    cargo test --test live_login -- --ignored
```
