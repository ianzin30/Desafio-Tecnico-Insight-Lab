# messenger_app (Flutter)

Desktop app over the `messenger_core` Rust engine: login, rooms, chat and
realtime updates, implementing the high-fidelity prototype ("Grafite e
cobalto"). `lib/main.dart` is the composition root.

## UI (`lib/ui/`)

Each screen is a *view* (plain widget fed with state values and callbacks,
tested directly) plus a thin *page* connecting it to the application layer.

- `app.dart` — theme (light/dark follows the system) and one screen per
  `AppPhase`: "Abrindo…" (after 300 ms), login, chat, fatal error with retry,
  and the "Sua sessão expirou" modal when the session ends while in use.
- `login_page.dart` — server (`https://` prefix, hidden when a scheme is
  typed), username, password; field errors (invalid address, wrong
  credentials) with focus on the culprit; one alert for unreachable server
  and network, one for unexpected errors (both with retry); expired-session
  and local-only-logout notices. The username is prefilled after an expiry.
- `chat_page.dart`, `sidebar.dart`, `timeline.dart`, `composer.dart` — rooms
  split into Diretas/Grupos (alphabetical), account menu with confirmed
  logout, room header, timeline grouped by sender (5 min) with day
  separators, loading/empty/error states, "Atualizando conversa…" while
  reconciling, "N novas mensagens" pill when reading above, connection banner
  after 2 s offline ("Conectado" once back), removed-room notice, composer
  (Enter sends, Shift+Enter new line, Esc leaves; drafts kept per room;
  disabled offline; failed sends keep the text with a retry). Compact layout
  under 960 px; minimum window 720×480.
- `theme.dart` — design tokens; fonts IBM Plex Sans/Mono bundled in
  `assets/fonts` (OFL), so the app needs no network for them.

## Application layer (`lib/app/`)

The UI observes state and calls intents; it never calls the bridge.

```text
widgets (future) → MessengerController (Riverpod) → MessengerGateway → MessengerApi → Rust
```

- **Riverpod 3** (`flutter_riverpod`): dependency injection (the gateway
  factory is overridden by `main.dart` and by tests), `select` so each widget
  rebuilds only for its slice, and `ref.onDispose` for shutdown.
- `messenger_gateway.dart` — `MessengerGateway`, a 1:1 interface over
  `MessengerApi`; `RustMessengerGateway` implements it.
- `messenger_state.dart` — immutable state: `AppPhase` (initializing /
  unauthenticated / authenticated / fatalError), `AuthState`, `RoomsState`,
  `ConversationState` (selected room), `ConnectionStatus` (offline /
  connecting / online / reconnecting) and semantic failures (`AuthFailure`,
  `RoomsFailure`, `ConversationFailure`, `AuthNotice`) instead of `ApiError`.
- `messenger_controller.dart` — `MessengerController`, the single
  coordinator: one engine and one event subscription for the app's life.
- `providers.dart` — `messengerProvider` (state + intents) and slices:
  `appPhaseProvider`, `authStateProvider`, `roomsStateProvider`,
  `conversationStateProvider`, `connectionStatusProvider`.

```dart
final app = ref.read(messengerProvider.notifier);
await app.login(homeserver: 'https://matrix.org', username: 'alice', password: password);
await app.selectRoom(roomId);          // loads the latest 50 messages
await app.sendMessage('Olá!');         // appears when the sync confirms it
await app.logout();
```

Behavior:

- **Homeserver** is chosen at login. After a successful login it is saved
  (`last_homeserver` file in `getApplicationSupportDirectory()`, the URL
  only) and exposed as `MessengerState.homeserver`; the engine's data lives in
  `matrix/` next to it.
- **Startup** (`main.dart`): no saved homeserver → unauthenticated, no engine
  yet. Otherwise the engine is created for it, its event stream subscribed,
  then the session restored: no session → unauthenticated; restored → cached
  rooms, then sync → authenticated; an unusable stored session →
  unauthenticated with `AuthNotice.sessionExpired`; an unusable saved
  homeserver → unauthenticated; engine or storage failure → `fatalError`
  (`retryStartup()`).
- **Login** (only while logged out) → if the homeserver differs from the
  engine's, the engine is replaced: the old one is disposed (closing its
  stream) and the new one gets the single event subscription. Then
  authenticated, rooms from the local store, `startSync`. After a fresh login
  the rooms stay `loading` until the first sync. There is never more than one
  engine nor one subscription.
- **Logout** → `stopSync`, `logout`, state cleared. `LogoutOutcome.localOnly`
  still logs out, with `AuthNotice.loggedOutLocallyOnly`.
- **Session revoked** (event, or `SessionRevoked`/`NotAuthenticated` from any
  call) → everything cleared, unauthenticated, `AuthNotice.sessionExpired`.
- `RoomsChanged` → rooms reloaded from the engine's local state; a selected
  room that disappeared closes the conversation.
- `MessageReceived` → added to the selected room only, deduplicated by ID,
  ordered by timestamp (oldest first); messages arriving during a load are
  merged into its result.
- `TimelineGap` of the selected room → its timeline is reloaded and replaced
  (`reconciling`); gaps of other rooms cost nothing (opening a room loads
  fresh messages). `EventsLost` → rooms and conversation reloaded.
- Reloads are coalesced (one running, one queued). A late messages result
  for a previous room is dropped (request counter); results of calls made
  before a logout/revocation are dropped (session counter).
- `Recovering` only changes `ConnectionStatus.reconnecting`: data is kept.
- **Event stream (FRB 2.13):** subscribed once per engine and never cancelled
  on its own while in use (a cancellation only completes on a later event).
  When the engine is replaced or the app exits (`AppLifecycleListener`), the
  engine is disposed first, which closes the stream, so nothing waits.

## Rust ↔ Dart bridge

- **Flutter Rust Bridge 2.13.0** (Rust crate, Dart package and codegen pinned
  to the same version).
- **Build: Native Assets** (`hook/build.dart` + `flutter_rust_bridge_hooks`):
  `flutter run/build/test` compile `../rust/bridge` with cargo and bundle the
  library for the target platform. Chosen over cargokit because it needs no
  per-platform scaffolding (podspec/CMake/plugin) and no custom scripts.
- `rust/bridge` (`messenger_bridge`) is a thin adapter: `MessengerApi` owns one
  `MessengerCore` and forwards calls; FFI types mirror the core's models.

### Regenerate bindings

After changing `rust/bridge/src/api/**`, from this directory:

```bash
flutter_rust_bridge_codegen generate
```

It rewrites `lib/src/rust/**` and `../rust/bridge/src/frb_generated.rs`
(never edit them) and runs `build_runner` for the freezed classes.

## Dart API

```dart
import 'package:messenger_app/messenger_core.dart';

await RustLib.init();                       // once per process
final api = await MessengerApi.create(homeserverUrl: url, dataDir: dir);
if (await api.restoreSession() == RestoreOutcome.noSession) {
  await api.login(username: 'alice', password: password);
}
final rooms = await api.refreshRooms();     // List<RoomSummary>
final messages = await api.loadMessages(roomId: rooms.first.id, limit: 50);
final sent = await api.sendTextMessage(roomId: rooms.first.id, body: 'Olá!');

final events = api.events().listen((event) {
  switch (event) {
    case CoreEvent_MessageReceived(:final roomId, :final message): // ...
    case CoreEvent_RoomsChanged(): // api.cachedRooms()
    case CoreEvent_TimelineGap(:final roomId): // api.loadMessages(...)
    case CoreEvent_SyncStateChanged(:final state): // stopped/starting/running/recovering
    case CoreEvent_SessionRevoked(): // log in again
    case CoreEvent_EventsLost(): // reload rooms and messages
  }
});
await api.startSync();
// ...
await api.stopSync();
await api.logout();                         // LogoutOutcome.complete / localOnly
api.dispose();                              // releases the core; closes the streams
```

- Errors are thrown as the sealed class `ApiError` (`ApiError_InvalidCredentials`,
  `ApiError_HomeserverUnreachable`, `ApiError_NotAuthenticated`, ...): semantic
  variants only, no internal details or secrets.
- `dataDir` is chosen by the app (e.g. its application support directory).
- 64-bit values (`Message.timestampMs`, `EventsLost.count`) are plain Dart `int`.
- One `MessengerApi` per app session: it keeps the same core and Matrix client.
  Mutating calls run one at a time (Flutter Rust Bridge locks the object);
  the continuous sync runs in the background without holding that lock.
- `events()` and `startSync()` are independent: subscribe first, then start.
  Each stream is fed by a Rust task that ends on `dispose()` (stream closes)
  or shortly after the subscription is cancelled: with Flutter Rust Bridge a
  cancellation takes effect when the next event arrives, so don't await
  `cancel()` if no event may follow.
- `dispose()` drops the core inside the Rust async runtime (the Matrix SDK
  requires it when closing its stores).
- `MessengerApi.create(..., secretStorage:)`: `SecretStorage.system` (the OS
  credential store; the app) or `SecretStorage.inMemory` (automated tests).
  Session secrets stay in Rust: Dart never sees the access token.
- The synchronous getters (`currentUser`, `syncState`, `homeserver`) wait for
  a running mutating call; the state layer avoids them in event handlers so a
  slow request never freezes the UI.

## Tests

```bash
(cd ../rust && cargo build -p messenger_bridge)   # library loaded by `flutter test`
flutter analyze
flutter test                              # bridge, application layer, UI widgets
flutter test integration_test -d macos    # real app: bridge smoke + UI end-to-end
```

- `test/ui/` — widget tests of every screen state (built from state values),
  formatting helpers; `visual_snapshot_test.dart` renders the screens to PNG
  for visual review when `SNAPSHOT_DIR` is set (skipped otherwise).
- `integration_test/app_e2e.dart` — the whole app driven through its UI with
  the real Rust engine and a local fake homeserver: failed then successful
  login, rooms, history, sending with Enter, realtime messages, logout with
  confirmation, prefilled login, revoked session → expired modal → login.

No test needs internet. Validated on **macOS (arm64)** only; Windows and Linux
are configured (standard Flutter runners, native assets) but not built here.
