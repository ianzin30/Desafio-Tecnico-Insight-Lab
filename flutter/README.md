# messenger_app (Flutter)

Desktop app shell over the `messenger_core` Rust engine. There is no product
UI yet: `lib/main.dart` is a technical entrypoint that loads the Rust library
and calls it once.

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

## Tests

```bash
(cd ../rust && cargo build -p messenger_bridge)   # library loaded by `flutter test`
flutter analyze
flutter test                              # Dart VM, real Rust library, local fake homeserver
flutter test integration_test -d macos    # inside the real desktop app
```

No test needs internet. Validated on **macOS (arm64)** only; Windows and Linux
are configured (standard Flutter runners, native assets) but not built here.
