import 'package:flutter/foundation.dart';

import '../messenger_core.dart';

/// Where the application is. Exactly one at a time, so the UI cannot show
/// rooms without a user or a login form while authenticated.
enum AppPhase {
  /// Creating the engine and restoring a previous session.
  initializing,

  /// No user: log in.
  unauthenticated,

  /// A user is logged in; rooms and conversation are available.
  authenticated,

  /// The engine could not be created (see [MessengerState.fatalError]).
  fatalError,
}

/// Connectivity, as the UI shows it.
enum ConnectionStatus {
  /// Sync not running.
  offline,

  /// Sync starting (first sync in progress).
  connecting,

  /// Up to date with the homeserver.
  online,

  /// Sync failing temporarily; retrying. Data stays available.
  reconnecting;

  static ConnectionStatus of(SyncState state) => switch (state) {
    SyncState.stopped => offline,
    SyncState.starting => connecting,
    SyncState.running => online,
    SyncState.recovering => reconnecting,
  };
}

/// Why a login or logout failed.
enum AuthFailure { invalidHomeserver, invalidCredentials, network, unexpected }

/// Non-fatal information to show after leaving the authenticated state.
enum AuthNotice {
  /// The homeserver ended the session (e.g. revoked elsewhere).
  sessionExpired,

  /// Logged out locally, but the homeserver could not be told.
  loggedOutLocallyOnly,
}

/// Why rooms could not be loaded.
enum RoomsFailure { network, unexpected }

/// Why a conversation operation failed.
enum ConversationFailure {
  /// The room no longer exists or was left.
  roomUnavailable,

  /// The message is empty.
  emptyMessage,
  network,
  unexpected,
}

/// Why the engine could not start (fatal).
@immutable
class FatalError {
  const FatalError(this.cause);

  /// Underlying error, for logs only.
  final Object cause;
}

@immutable
class AuthState {
  const AuthState({
    this.userId,
    this.submitting = false,
    this.failure,
    this.notice,
  });

  /// Matrix ID of the logged in user.
  final String? userId;

  /// A login or logout is in progress.
  final bool submitting;
  final AuthFailure? failure;
  final AuthNotice? notice;
}

@immutable
class RoomsState {
  const RoomsState({this.rooms = const [], this.loading = false, this.failure});

  /// Joined rooms, as given by the engine.
  final List<RoomSummary> rooms;

  /// Loading and nothing to show yet (first load).
  final bool loading;

  /// Last load failed; [rooms] keeps the previous data.
  final RoomsFailure? failure;

  bool get isEmpty => !loading && rooms.isEmpty;

  bool contains(String roomId) => rooms.any((room) => room.id == roomId);
}

@immutable
class ConversationState {
  const ConversationState({
    required this.roomId,
    this.messages = const [],
    this.loading = false,
    this.reconciling = false,
    this.sending = false,
    this.failure,
  });

  /// The selected room.
  final String roomId;

  /// Text messages, oldest first, without duplicates.
  final List<Message> messages;

  /// First load of the room in progress.
  final bool loading;

  /// Reloading after missed updates; [messages] stays visible.
  final bool reconciling;

  /// A message is being sent (it appears once confirmed by the sync).
  final bool sending;
  final ConversationFailure? failure;

  ConversationState copyWith({
    List<Message>? messages,
    bool? loading,
    bool? reconciling,
    bool? sending,
    ConversationFailure? Function()? failure,
  }) => ConversationState(
    roomId: roomId,
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    reconciling: reconciling ?? this.reconciling,
    sending: sending ?? this.sending,
    failure: failure != null ? failure() : this.failure,
  );
}

/// The whole application state.
@immutable
class MessengerState {
  const MessengerState({
    this.phase = AppPhase.initializing,
    this.homeserver,
    this.auth = const AuthState(),
    this.rooms = const RoomsState(),
    this.conversation,
    this.syncState = SyncState.stopped,
    this.fatalError,
  });

  final AppPhase phase;

  /// Homeserver of the engine (last one used); `null` before the first
  /// login. The login form can start from it.
  final String? homeserver;
  final AuthState auth;
  final RoomsState rooms;

  /// The selected room's conversation; `null` when no room is selected.
  final ConversationState? conversation;
  final SyncState syncState;
  final FatalError? fatalError;

  String? get selectedRoomId => conversation?.roomId;

  ConnectionStatus get connection => ConnectionStatus.of(syncState);

  MessengerState copyWith({
    AppPhase? phase,
    String? homeserver,
    AuthState? auth,
    RoomsState? rooms,
    ConversationState? Function()? conversation,
    SyncState? syncState,
    FatalError? fatalError,
  }) => MessengerState(
    phase: phase ?? this.phase,
    homeserver: homeserver ?? this.homeserver,
    auth: auth ?? this.auth,
    rooms: rooms ?? this.rooms,
    conversation: conversation != null ? conversation() : this.conversation,
    syncState: syncState ?? this.syncState,
    fatalError: fatalError ?? this.fatalError,
  );
}
