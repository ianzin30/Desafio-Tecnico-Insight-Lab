import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'messenger_controller.dart';
import 'messenger_state.dart';

export 'messenger_controller.dart'
    show gatewayFactoryProvider, homeserverStoreProvider;

/// The application controller. Intents (login, logout, selectRoom,
/// sendMessage, ...) go through `ref.read(messengerProvider.notifier)`.
final messengerProvider = NotifierProvider<MessengerController, MessengerState>(
  MessengerController.new,
);

// Slices the UI observes; each rebuilds only when its part changes.

final appPhaseProvider = Provider<AppPhase>(
  (ref) => ref.watch(messengerProvider.select((state) => state.phase)),
);

final authStateProvider = Provider<AuthState>(
  (ref) => ref.watch(messengerProvider.select((state) => state.auth)),
);

final roomsStateProvider = Provider<RoomsState>(
  (ref) => ref.watch(messengerProvider.select((state) => state.rooms)),
);

final conversationStateProvider = Provider<ConversationState?>(
  (ref) => ref.watch(messengerProvider.select((state) => state.conversation)),
);

final connectionStatusProvider = Provider<ConnectionStatus>(
  (ref) => ref.watch(messengerProvider.select((state) => state.connection)),
);
