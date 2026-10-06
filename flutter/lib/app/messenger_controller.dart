import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../messenger_core.dart';
import 'homeserver_store.dart';
import 'messenger_gateway.dart';
import 'messenger_state.dart';

/// Creates the engine gateway for a homeserver; provided by the composition
/// root.
typedef GatewayFactory = Future<MessengerGateway> Function(
  String homeserverUrl,
);

/// Gateway factory, overridden by the composition root (and by tests).
final gatewayFactoryProvider = Provider<GatewayFactory>(
  (ref) => throw UnimplementedError('Provided by the composition root'),
);

/// Where the last homeserver is remembered; overridden by the composition
/// root (and by tests).
final homeserverStoreProvider = Provider<HomeserverStore>(
  (ref) => throw UnimplementedError('Provided by the composition root'),
);

/// Coordinates the application on top of the Rust engine: startup, session,
/// rooms, the selected conversation and realtime events.
///
/// It is the single owner of the [MessengerGateway] and of its event
/// subscription. The engine stays the source of truth: this layer reacts to
/// its results and events, and ignores results of a previous session or of
/// a room that is no longer selected.
class MessengerController extends Notifier<MessengerState> {
  /// Messages loaded when a room is opened (the engine caps it at 100).
  static const messagesLimit = 50;

  /// The engine; at most one at a time. Replaced only while logged out,
  /// when the user logs in to another homeserver.
  MessengerGateway? _gateway;

  /// The single subscription to the engine events, kept for the gateway's
  /// whole life. It is never cancelled while the app runs: with
  /// flutter_rust_bridge 2.13 a cancellation only completes on a later
  /// event. Disposing the gateway closes the stream instead.
  StreamSubscription<CoreEvent>? _events;

  /// Incremented when a session ends; results of older calls are dropped.
  int _session = 0;

  /// Incremented on each messages load; only the latest may apply.
  int _messagesRequest = 0;

  /// Messages received while the selected room is (re)loading, merged into
  /// the load result.
  final _receivedDuringLoad = <Message>[];

  // Coalescing: one reload running at most, plus one queued.
  bool _roomsReloading = false;
  bool _roomsReloadQueued = false;
  bool _conversationReloading = false;
  bool _conversationReloadQueued = false;

  int _sendsInFlight = 0;

  Future<void> _startup = Future.value();

  /// Completes when the current startup attempt is over.
  Future<void> get startup => _startup;

  @override
  MessengerState build() {
    ref.onDispose(_dispose);
    _startup = Future(_initialize);
    return const MessengerState();
  }

  // -------------------------------------------------------------- lifecycle

  Future<void> _initialize() async {
    final String? homeserver;
    try {
      homeserver = await ref.read(homeserverStoreProvider).read();
    } catch (error) {
      if (ref.mounted) _fail(error);
      return;
    }
    if (!ref.mounted) return;
    // First run: no engine until the login provides a homeserver.
    if (homeserver == null) {
      _endSession();
      return;
    }

    try {
      await _attach(homeserver);
    } on ApiError_InvalidHomeserver {
      // The remembered homeserver is unusable: ask for another one.
      if (ref.mounted) _endSession();
      return;
    } catch (error) {
      if (ref.mounted) _fail(error);
      return;
    }
    if (!ref.mounted) return;

    final gateway = _gateway!;
    final session = _session;
    final RestoreOutcome outcome;
    try {
      outcome = await gateway.restoreSession();
    } on ApiError catch (error) {
      if (!_isCurrent(session)) return;
      if (error is ApiError_InvalidSession) {
        // The engine discarded an unusable session: a new login is needed.
        _endSession(notice: AuthNotice.sessionExpired);
      } else {
        _fail(error);
      }
      return;
    }
    if (!_isCurrent(session)) return;
    switch (outcome) {
      case RestoreOutcome.noSession:
        _endSession();
      case RestoreOutcome.restored:
        await _enterAuthenticated();
    }
  }

  /// Creates the engine for [homeserver] and subscribes to its events,
  /// replacing the previous engine if any. Throws if creation fails (no
  /// engine is left then).
  Future<void> _attach(String homeserver) async {
    _detach();
    final gateway = await ref.read(gatewayFactoryProvider)(homeserver);
    if (!ref.mounted) {
      gateway.dispose();
      return;
    }
    _gateway = gateway;
    // Events of a replaced engine are ignored, should any still arrive.
    _events = gateway.events().listen((event) {
      if (identical(_gateway, gateway)) onEvent(event);
    });
    state = state.copyWith(homeserver: homeserver);
  }

  /// Releases the engine: disposing it first closes its event stream
  /// immediately, so the cancellation never waits for a further event
  /// (flutter_rust_bridge 2.13).
  void _detach() {
    final events = _events;
    final gateway = _gateway;
    _events = null;
    _gateway = null;
    gateway?.dispose();
    if (events != null) unawaited(events.cancel());
  }

  void _fail(Object error) {
    state = MessengerState(
      phase: AppPhase.fatalError,
      homeserver: state.homeserver,
      fatalError: FatalError(error),
    );
  }

  void _dispose() {
    _session++;
    _detach();
  }

  /// Opens the authenticated session: user, local rooms, then sync.
  Future<void> _enterAuthenticated() async {
    final gateway = _gateway!;
    final session = _session;
    state = MessengerState(
      phase: AppPhase.authenticated,
      homeserver: state.homeserver,
      auth: AuthState(userId: gateway.currentUser()),
      rooms: const RoomsState(loading: true),
      syncState: gateway.syncState(),
    );
    // Local rooms first, so the app does not depend on the network. When
    // there are none yet (fresh login), keep loading until the first sync.
    await _loadCachedRooms(session, keepLoadingIfEmpty: true);
    await _startSync(session);
  }

  Future<void> _startSync(int session) async {
    final gateway = _gateway;
    if (gateway == null || !_isCurrent(session)) return;
    try {
      await gateway.startSync();
    } on ApiError_AlreadySyncing {
      // Already running: nothing to do.
    } on ApiError catch (error) {
      if (_isCurrent(session)) _endSessionIfLost(error);
    }
  }

  /// Back to the unauthenticated state, dropping every session-bound state.
  /// The event subscription stays: it serves the next login too.
  void _endSession({AuthNotice? notice}) {
    _session++;
    _messagesRequest++;
    _receivedDuringLoad.clear();
    _sendsInFlight = 0;
    state = MessengerState(
      phase: AppPhase.unauthenticated,
      homeserver: state.homeserver,
      auth: AuthState(notice: notice),
      syncState: _gateway?.syncState() ?? SyncState.stopped,
    );
  }

  /// Ends the session if [error] means the engine no longer has one.
  bool _endSessionIfLost(ApiError error) {
    if (state.phase != AppPhase.authenticated) return false;
    if (error is ApiError_SessionRevoked ||
        error is ApiError_NotAuthenticated) {
      _endSession(notice: AuthNotice.sessionExpired);
      return true;
    }
    return false;
  }

  bool _isCurrent(int session) => ref.mounted && session == _session;

  // ---------------------------------------------------------------- intents

  /// Retries a failed startup.
  Future<void> retryStartup() {
    if (state.phase == AppPhase.fatalError) {
      state = const MessengerState();
      _startup = Future(_initialize);
    }
    return _startup;
  }

  /// Logs in to [homeserver]; on success remembers it for the next startup,
  /// opens the authenticated session and starts the sync. The engine
  /// validates the homeserver and the credentials.
  ///
  /// Only while logged out: a different homeserver replaces the engine
  /// (the previous one is disposed, the new one gets the single event
  /// subscription).
  Future<void> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (state.phase != AppPhase.unauthenticated || state.auth.submitting) {
      return;
    }
    final homeserverUrl = homeserver.trim();
    final session = _session;
    state = state.copyWith(auth: const AuthState(submitting: true));

    if (_gateway == null || homeserverUrl != state.homeserver) {
      try {
        await _attach(homeserverUrl);
      } on ApiError catch (error) {
        if (_isCurrent(session)) {
          state = state.copyWith(auth: AuthState(failure: _authFailure(error)));
        }
        return;
      }
    }
    final gateway = _gateway;
    if (gateway == null || !_isCurrent(session)) return;

    try {
      await gateway.login(username: username, password: password);
    } on ApiError catch (error) {
      if (_isCurrent(session)) {
        state = state.copyWith(auth: AuthState(failure: _authFailure(error)));
      }
      return;
    }
    if (!_isCurrent(session)) return;
    try {
      await ref.read(homeserverStoreProvider).write(homeserverUrl);
    } catch (_) {
      // Not fatal: the session works; only the next startup will ask for
      // the homeserver again.
    }
    await _enterAuthenticated();
  }

  /// Stops the sync and logs out. A logout the homeserver did not receive
  /// still leaves the session ([AuthNotice.loggedOutLocallyOnly]).
  Future<void> logout() async {
    final gateway = _gateway;
    if (gateway == null ||
        state.phase != AppPhase.authenticated ||
        state.auth.submitting) {
      return;
    }
    final session = _session;
    final userId = state.auth.userId;
    state = state.copyWith(auth: AuthState(userId: userId, submitting: true));
    try {
      await gateway.stopSync();
      final outcome = await gateway.logout();
      if (!_isCurrent(session)) return;
      _endSession(
        notice: outcome == LogoutOutcome.localOnly
            ? AuthNotice.loggedOutLocallyOnly
            : null,
      );
    } on ApiError catch (error) {
      if (!_isCurrent(session) || _endSessionIfLost(error)) return;
      // The engine kept the session (e.g. local storage error): stay in.
      state = state.copyWith(
        auth: AuthState(userId: userId, failure: AuthFailure.unexpected),
      );
      await _startSync(session);
    }
  }

  /// Clears the authentication failure or notice once the UI showed it.
  void dismissAuthMessage() {
    final auth = state.auth;
    state = state.copyWith(
      auth: AuthState(userId: auth.userId, submitting: auth.submitting),
    );
  }

  /// Asks the homeserver for the rooms (the engine syncs once unless the
  /// continuous sync already keeps them up to date).
  Future<void> refreshRooms() async {
    final gateway = _gateway;
    if (gateway == null || state.phase != AppPhase.authenticated) return;
    final session = _session;
    try {
      final rooms = await gateway.refreshRooms();
      if (_isCurrent(session)) _applyRooms(rooms);
    } on ApiError catch (error) {
      if (_isCurrent(session)) _roomsFailed(error);
    }
  }

  /// Opens a room and loads its latest messages. Selecting another room
  /// meanwhile discards this load's result.
  Future<void> selectRoom(String roomId) async {
    if (state.phase != AppPhase.authenticated ||
        state.selectedRoomId == roomId) {
      return;
    }
    _sendsInFlight = 0;
    state = state.copyWith(
      conversation: () => ConversationState(roomId: roomId, loading: true),
    );
    await _loadMessages(roomId);
  }

  /// Closes the selected room.
  void clearSelection() {
    if (state.conversation == null) return;
    _messagesRequest++;
    _receivedDuringLoad.clear();
    state = state.copyWith(conversation: () => null);
  }

  /// Reloads the selected room's messages (e.g. after an error).
  Future<void> reloadConversation() => _reloadConversation();

  /// Sends a text message, unchanged, to the selected room. It is not added
  /// locally: it appears once the realtime sync confirms it. Returns whether
  /// the homeserver accepted it.
  Future<bool> sendMessage(String body) async {
    final gateway = _gateway;
    final roomId = state.selectedRoomId;
    if (gateway == null || roomId == null) return false;
    final session = _session;

    _sendsInFlight++;
    _updateConversation(
      roomId,
      (current) => current.copyWith(sending: true, failure: () => null),
    );
    var sent = false;
    try {
      await gateway.sendTextMessage(roomId: roomId, body: body);
      sent = true;
    } on ApiError catch (error) {
      if (_isCurrent(session) && !_endSessionIfLost(error)) {
        _updateConversation(
          roomId,
          (current) =>
              current.copyWith(failure: () => _conversationFailure(error)),
        );
      }
    }
    if (_isCurrent(session) && state.selectedRoomId == roomId) {
      _sendsInFlight--;
      _updateConversation(
        roomId,
        (current) => current.copyWith(sending: _sendsInFlight > 0),
      );
    }
    return sent;
  }

  // ----------------------------------------------------------------- events

  /// Applies an engine event. Called by the event subscription; public only
  /// so tests can inject events the engine cannot produce on demand.
  @visibleForTesting
  void onEvent(CoreEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case CoreEvent_SyncStateChanged(state: final syncState):
        _onSyncState(syncState);
      case CoreEvent_SessionRevoked():
        if (state.phase == AppPhase.authenticated) {
          _endSession(notice: AuthNotice.sessionExpired);
        }
      // The rest only matters for an open session.
      case _ when state.phase != AppPhase.authenticated:
        break;
      case CoreEvent_RoomsChanged():
        unawaited(_reloadRooms());
      case CoreEvent_MessageReceived(:final roomId, :final message):
        _onMessage(roomId, message);
      case CoreEvent_TimelineGap(:final roomId):
        // Other rooms load fresh messages when opened anyway.
        if (roomId == state.selectedRoomId) {
          unawaited(_reloadConversation());
        }
      case CoreEvent_EventsLost():
        // Updates may have been missed: reload what is shown.
        unawaited(_reloadRooms());
        unawaited(_reloadConversation());
    }
  }

  void _onSyncState(SyncState syncState) {
    state = state.copyWith(syncState: syncState);
    // First sync done after a fresh login: rooms are now known.
    if (syncState == SyncState.running &&
        state.phase == AppPhase.authenticated &&
        state.rooms.loading) {
      unawaited(_reloadRooms());
    }
  }

  /// Adds a message received in realtime to the selected room, once.
  void _onMessage(String roomId, Message message) {
    final conversation = state.conversation;
    if (conversation == null || conversation.roomId != roomId) return;
    if (conversation.loading || conversation.reconciling) {
      _receivedDuringLoad.add(message);
    }
    final messages = _insert(conversation.messages, message);
    if (!identical(messages, conversation.messages)) {
      state = state.copyWith(
        conversation: () => conversation.copyWith(messages: messages),
      );
    }
  }

  // ------------------------------------------------------------------ rooms

  /// Reloads the rooms from the engine's local state; concurrent requests
  /// are coalesced into one more run.
  Future<void> _reloadRooms() async {
    if (_roomsReloading) {
      _roomsReloadQueued = true;
      return;
    }
    _roomsReloading = true;
    try {
      do {
        _roomsReloadQueued = false;
        if (state.phase != AppPhase.authenticated) break;
        await _loadCachedRooms(_session);
      } while (_roomsReloadQueued && ref.mounted);
    } finally {
      _roomsReloading = false;
    }
  }

  Future<void> _loadCachedRooms(
    int session, {
    bool keepLoadingIfEmpty = false,
  }) async {
    final gateway = _gateway;
    if (gateway == null) return;
    try {
      final rooms = await gateway.cachedRooms();
      if (!_isCurrent(session)) return;
      _applyRooms(rooms, keepLoading: keepLoadingIfEmpty && rooms.isEmpty);
    } on ApiError catch (error) {
      if (_isCurrent(session)) _roomsFailed(error);
    }
  }

  /// Replaces the rooms; closes the conversation if its room is gone.
  void _applyRooms(List<RoomSummary> rooms, {bool keepLoading = false}) {
    final selected = state.selectedRoomId;
    final selectionGone =
        selected != null && !rooms.any((room) => room.id == selected);
    if (selectionGone) {
      _messagesRequest++;
      _receivedDuringLoad.clear();
    }
    state = state.copyWith(
      rooms: RoomsState(rooms: rooms, loading: keepLoading),
      conversation: selectionGone ? () => null : null,
    );
  }

  void _roomsFailed(ApiError error) {
    if (_endSessionIfLost(error)) return;
    state = state.copyWith(
      rooms: RoomsState(
        rooms: state.rooms.rooms,
        failure: error is ApiError_HomeserverUnreachable
            ? RoomsFailure.network
            : RoomsFailure.unexpected,
      ),
    );
  }

  // --------------------------------------------------------------- messages

  /// Reloads the selected room after missed updates, replacing its
  /// timeline; concurrent requests are coalesced into one more run.
  Future<void> _reloadConversation() async {
    if (_conversationReloading) {
      _conversationReloadQueued = true;
      return;
    }
    _conversationReloading = true;
    try {
      do {
        _conversationReloadQueued = false;
        final conversation = state.conversation;
        if (conversation == null || state.phase != AppPhase.authenticated) {
          break;
        }
        state = state.copyWith(
          conversation: () =>
              conversation.copyWith(reconciling: true, failure: () => null),
        );
        await _loadMessages(conversation.roomId);
      } while (_conversationReloadQueued && ref.mounted);
    } finally {
      _conversationReloading = false;
    }
  }

  /// Loads the latest messages of [roomId] and makes them the conversation's
  /// timeline, unless another load started meanwhile.
  Future<void> _loadMessages(String roomId) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final request = ++_messagesRequest;
    final session = _session;
    _receivedDuringLoad.clear();
    try {
      final loaded = await gateway.loadMessages(
        roomId: roomId,
        limit: messagesLimit,
      );
      if (!_isCurrent(session) || request != _messagesRequest) return;
      var messages = loaded;
      for (final message in _receivedDuringLoad) {
        messages = _insert(messages, message);
      }
      _receivedDuringLoad.clear();
      _updateConversation(
        roomId,
        (current) => current.copyWith(
          messages: messages,
          loading: false,
          reconciling: false,
          failure: () => null,
        ),
      );
    } on ApiError catch (error) {
      if (!_isCurrent(session) || request != _messagesRequest) return;
      if (_endSessionIfLost(error)) return;
      _updateConversation(
        roomId,
        (current) => current.copyWith(
          loading: false,
          reconciling: false,
          failure: () => _conversationFailure(error),
        ),
      );
    }
  }

  void _updateConversation(
    String roomId,
    ConversationState Function(ConversationState current) update,
  ) {
    final conversation = state.conversation;
    if (conversation == null || conversation.roomId != roomId) return;
    state = state.copyWith(conversation: () => update(conversation));
  }

  /// Inserts [message] in timestamp order (oldest first), unless a message
  /// with the same ID is already there. Returns [messages] itself if
  /// unchanged.
  static List<Message> _insert(List<Message> messages, Message message) {
    if (messages.any((existing) => existing.id == message.id)) {
      return messages;
    }
    var index = messages.length;
    while (index > 0 && messages[index - 1].timestampMs > message.timestampMs) {
      index--;
    }
    return [...messages]..insert(index, message);
  }

  // ----------------------------------------------------------------- errors

  static AuthFailure _authFailure(ApiError error) => switch (error) {
    ApiError_InvalidHomeserver() => AuthFailure.invalidHomeserver,
    ApiError_InvalidCredentials() => AuthFailure.invalidCredentials,
    ApiError_HomeserverUnreachable() => AuthFailure.network,
    _ => AuthFailure.unexpected,
  };

  static ConversationFailure _conversationFailure(ApiError error) =>
      switch (error) {
        ApiError_RoomNotFound() ||
        ApiError_NotJoined() => ConversationFailure.roomUnavailable,
        ApiError_InvalidMessage() => ConversationFailure.emptyMessage,
        ApiError_HomeserverUnreachable() => ConversationFailure.network,
        _ => ConversationFailure.unexpected,
      };
}
