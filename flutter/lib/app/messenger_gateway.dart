import 'package:flutter/foundation.dart';

import '../messenger_core.dart';

/// What the application layer needs from the Rust engine.
///
/// A 1:1 view of [MessengerApi] so the state layer can be tested with a fake;
/// the data types (rooms, messages, events, errors) are the bridge's own.
abstract interface class MessengerGateway {
  String? currentUser();
  SyncState syncState();

  /// Events of the engine. Listened to once for the gateway's lifetime.
  Stream<CoreEvent> events();

  Future<RestoreOutcome> restoreSession();
  Future<void> login({required String username, required String password});
  Future<LogoutOutcome> logout();

  Future<List<RoomSummary>> cachedRooms();
  Future<List<RoomSummary>> refreshRooms();

  Future<List<Message>> loadMessages({
    required String roomId,
    required int limit,
  });
  Future<SentMessage> sendTextMessage({
    required String roomId,
    required String body,
  });

  Future<void> startSync();
  Future<void> stopSync();

  /// Releases the engine; closes the event stream immediately.
  void dispose();
}

/// [MessengerGateway] backed by the Rust engine through the bridge.
final class RustMessengerGateway implements MessengerGateway {
  RustMessengerGateway._(this._api);

  final MessengerApi _api;

  /// Loads the Rust library (once per process) and creates the engine.
  /// Session secrets stay in Rust, in the OS credential store unless
  /// [secretStorage] says otherwise (automated tests).
  static Future<RustMessengerGateway> create({
    required String homeserverUrl,
    required String dataDir,
    SecretStorage secretStorage = SecretStorage.system,
  }) async {
    if (!RustLib.instance.initialized) await RustLib.init();
    return RustMessengerGateway._(
      await MessengerApi.create(
        homeserverUrl: homeserverUrl,
        dataDir: dataDir,
        secretStorage: secretStorage,
      ),
    );
  }

  @override
  String? currentUser() => _api.currentUser();

  @override
  SyncState syncState() => _api.syncState();

  @override
  Stream<CoreEvent> events() => _api.events();

  @override
  Future<RestoreOutcome> restoreSession() => _api.restoreSession();

  @override
  Future<void> login({required String username, required String password}) =>
      _api.login(username: username, password: password);

  @override
  Future<LogoutOutcome> logout() => _api.logout();

  @override
  Future<List<RoomSummary>> cachedRooms() => _api.cachedRooms();

  @override
  Future<List<RoomSummary>> refreshRooms() => _api.refreshRooms();

  @override
  Future<List<Message>> loadMessages({
    required String roomId,
    required int limit,
  }) => _api.loadMessages(roomId: roomId, limit: limit);

  @override
  Future<SentMessage> sendTextMessage({
    required String roomId,
    required String body,
  }) => _api.sendTextMessage(roomId: roomId, body: body);

  @override
  Future<void> startSync() => _api.startSync();

  @override
  Future<void> stopSync() => _api.stopSync();

  @override
  void dispose() => _api.dispose();

  /// Whether [dispose] was called (diagnostics for tests).
  @visibleForTesting
  bool get isDisposed => _api.isDisposed;

  /// Event streams still fed by the engine (diagnostics for tests).
  @visibleForTesting
  int activeEventStreams() => _api.activeEventStreams();
}
