// Technical entrypoint only (no product UI yet): loads the Rust library,
// calls it once without network and shows the result.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:messenger_app/messenger_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final status = await bridgeSmokeCheck();
  debugPrint(status);
  runApp(Center(child: Text(status, textDirection: TextDirection.ltr)));
}

/// Creates a client in a temporary directory and queries it.
Future<String> bridgeSmokeCheck() async {
  final dataDir = await Directory.systemTemp.createTemp('messenger_smoke');
  try {
    final api = await MessengerApi.create(
      homeserverUrl: 'https://matrix.org',
      dataDir: dataDir.path,
    );
    final restore = await api.restoreSession();
    final status =
        'messenger_core loaded: homeserver=${api.homeserver()} '
        'user=${api.currentUser()} restore=${restore.name} '
        'sync=${api.syncState().name}';
    api.dispose();
    return status;
  } on ApiError catch (error) {
    return 'messenger_core error: $error';
  } finally {
    await dataDir.delete(recursive: true);
  }
}
