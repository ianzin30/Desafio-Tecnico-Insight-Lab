// Runs the application layer over the real Rust engine and a local fake
// homeserver (no internet).
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messenger_app/app/homeserver_store.dart';
import 'package:messenger_app/app/messenger_controller.dart';
import 'package:messenger_app/app/messenger_gateway.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/app/providers.dart';

import 'fake_homeserver.dart';

class AppHarness {
  AppHarness(this.server, this.dataDir);

  final FakeHomeserver server;
  final Directory dataDir;
  ProviderContainer? _container;

  /// Gateways created by the composition, and their homeservers.
  final gateways = <RustMessengerGateway>[];
  final gatewayHomeservers = <String>[];

  /// The remembered homeserver (stored in [dataDir]).
  late final store = FileHomeserverStore(Future.value(dataDir));

  /// The Rust engine's data directory.
  String get engineDir => '${dataDir.path}/matrix';

  ProviderContainer get container => _container!;
  MessengerController get app => container.read(messengerProvider.notifier);
  MessengerState get state => container.read(messengerProvider);

  /// Starts the application (like `main`) and waits for its startup.
  Future<void> start() async {
    final container = ProviderContainer(
      overrides: [
        homeserverStoreProvider.overrideWithValue(store),
        gatewayFactoryProvider.overrideWithValue((homeserverUrl) async {
          final gateway = await RustMessengerGateway.create(
            homeserverUrl: homeserverUrl,
            dataDir: engineDir,
          );
          gateways.add(gateway);
          gatewayHomeservers.add(homeserverUrl);
          return gateway;
        }),
      ],
    );
    _container = container;
    container.listen(messengerProvider, (_, _) {});
    await container.read(messengerProvider.notifier).startup;
  }

  /// Quits the application (like the app exit hook).
  void stop() {
    _container?.dispose();
    _container = null;
  }

  /// Waits until the state matches [test].
  Future<void> until(
    bool Function(MessengerState state) test, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!test(state)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('state not reached: ${describe(state)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Logs in with the fake homeserver's credentials and waits until the
  /// first sync delivered the rooms.
  Future<void> login({FakeHomeserver? to}) async {
    await app.login(
      homeserver: (to ?? server).url,
      username: 'alice',
      password: FakeHomeserver.password,
    );
    await until(
      (state) =>
          state.phase == AppPhase.authenticated &&
          state.syncState.name == 'running' &&
          !state.rooms.loading,
    );
  }

  static String describe(MessengerState state) =>
      'phase=${state.phase.name} sync=${state.syncState.name} '
      'rooms=${state.rooms.rooms.map((room) => room.id).toList()} '
      'roomsLoading=${state.rooms.loading} '
      'conversation=${state.conversation?.roomId} '
      'messages=${state.conversation?.messages.map((m) => m.id).toList()}';
}
