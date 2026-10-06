// Composition root: builds the application layer once and shows the UI.
// screen only shows the application phase.
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/homeserver_store.dart';
import 'app/messenger_gateway.dart';
import 'app/providers.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Per-platform application data directory: the last homeserver (a URL,
  // no secret) and, in `matrix/`, the Rust engine's data.
  final supportDir = getApplicationSupportDirectory();

  final container = ProviderContainer(
    overrides: [
      homeserverStoreProvider.overrideWithValue(
        FileHomeserverStore(supportDir),
      ),
      // One engine at a time, for the homeserver chosen at login (or the
      // remembered one at startup).
      gatewayFactoryProvider.overrideWithValue(
        (homeserverUrl) async => RustMessengerGateway.create(
          homeserverUrl: homeserverUrl,
          dataDir: Directory('${(await supportDir).path}/matrix').path,
        ),
      ),
    ],
  );
  // Starts the application layer (engine, events, session restore).
  container.read(messengerProvider);

  // Release the engine cleanly when the app quits.
  AppLifecycleListener(
    onExitRequested: () async {
      container.dispose();
      return AppExitResponse.exit;
    },
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MessengerApp(),
    ),
  );
}
