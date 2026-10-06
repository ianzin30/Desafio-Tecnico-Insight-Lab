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
- `refresh_rooms()` runs one finite `/sync` and returns the joined rooms;
  `cached_rooms()` returns them from the local store without network.
- `load_messages(room_id, limit)` returns the latest text messages of a joined
  room; `send_text_message(room_id, body)` sends one.
- **Not implemented yet:** continuous sync / realtime updates, media, invites.

```rust
use messenger_core::{MessengerCore, RestoreOutcome};

let mut core = MessengerCore::new("https://matrix.org", &data_dir).await?;
if core.restore_session().await? == RestoreOutcome::NoSession {
    core.login("alice", &password).await?;
}
assert_eq!(core.current_user().as_deref(), Some("@alice:matrix.org"));

let rooms = core.refresh_rooms().await?; // Vec<RoomSummary { id, display_name, is_direct }>
let messages = core.load_messages(&rooms[0].id, 50).await?; // oldest first
let sent = core.send_text_message(&rooms[0].id, "Olá!").await?; // SentMessage { event_id }
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

## Rooms

- `refresh_rooms()` performs a single `/sync` (timeout 0: no long polling, no
  background task). The Matrix SDK persists the received state in its SQLite
  store, and the next sync resumes from the stored sync token. Rooms joined
  later only show up on the next call.
- `cached_rooms()` reads the store only: after `restore_session()` it returns
  the rooms of the last sync (possibly outdated), empty if never synced.
- Only **joined** rooms are listed: invites, left rooms and **spaces** (room
  groups, not conversations) are excluded. Other room types are kept.
- `display_name` comes from the SDK (spec algorithm: name, alias, then member
  names, e.g. the other person in a DM, else `Empty Room`); `is_direct` reflects
  the user's `m.direct` account data.
- Rooms are sorted by room ID for determinism only — **not** by activity.
- Errors: `NotAuthenticated` (no request sent), `HomeserverUnreachable`,
  `SyncFailed`, and `SessionRevoked` when the homeserver rejects the token (e.g.
  revoked elsewhere): the local session is then discarded and a new login is needed.
- The sync uses a rooms-only filter: no timeline events (history stays
  reachable later through pagination), lazy-loaded members (only those needed
  to name rooms), no presence, no typing notifications. Room state and account
  data are kept in full, since anything skipped would never be resent by later
  incremental syncs.

## Messages

- `load_messages(room_id, limit)` sends one `/messages` request backwards from
  the end of the room timeline (no token needed, so it does not depend on the
  rooms-only sync) for at most `limit` message events, capped at
  `MAX_MESSAGES` (100). Results are ordered **oldest first**.
- Only `m.room.message` events with `msgtype` `m.text` become a `Message`
  (`id`, `sender`, `body`, `timestamp_ms`, `is_own`); media, edits, reactions,
  state events and undecryptable events are skipped, so fewer than `limit`
  messages may be returned.
- Messages are not cached: each call queries the homeserver. The SDK event
  cache was not enabled — it is fed by sync, which is limited to rooms until
  continuous sync is implemented.
- `send_text_message(room_id, body)` sends `m.room.message`/`m.text` with the
  body unchanged (blank bodies are rejected without a request) and returns
  the event ID. There is no local echo: the message appears on the next
  `load_messages`.
- Errors: `NotAuthenticated`, `RoomNotFound` (invalid or unknown room ID),
  `NotJoined` (invited/left rooms), `InvalidMessage`, `MessageLoadFailed`,
  `MessageSendFailed`, plus `HomeserverUnreachable` and `SessionRevoked` as for rooms.

## Network policy

Set once when the Matrix client is built (`messenger_core.rs`) and shared by
all its requests: **5 s timeout per attempt, 2 attempts** (one retry ~0.5 s
later). A homeserver that accepts connections but never answers fails in about
10 s. Exception: login, whose retry config (3 attempts of 30 s) is fixed by the SDK.

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
    cargo test --test live_login -- --ignored --nocapture
```

Add `MATRIX_TEST_ROOM_ID=!room:server` to also load that room's messages, and
`MATRIX_TEST_SEND=1` (explicit opt-in) to send a test message to it.
