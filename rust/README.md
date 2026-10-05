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
- **Not implemented yet:** login, session persistence, rooms, messages, sync.

```rust
let core = messenger_core::MessengerCore::new("https://matrix.org").await?;
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
