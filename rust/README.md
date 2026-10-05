# messenger_core (Rust)

Native core of the desktop messaging client. It will hold the Matrix
integration and later be exposed to Flutter via Flutter Rust Bridge.

## Status

- `matrix-sdk` 0.19 is configured (default features: E2EE, SQLite stores, rustls).
- `flutter_rust_bridge` 2.13.0 is declared (pinned; the Dart package must use the
  same version). No bridge API, codegen or Flutter project exists yet.
- **No real Matrix functionality is implemented yet** — no client, homeserver
  connection, login, session, rooms, messages or sync.

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
