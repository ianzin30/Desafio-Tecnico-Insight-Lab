// Bridge smoke tests, run inside the real desktop app by app_test.dart:
// the Rust library is the one bundled by the build hook, loaded by the
// default loader.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:messenger_app/messenger_core.dart';

import '../test/support/fake_homeserver.dart';

/// Creates a client in a temporary directory and queries it without network.
Future<String> bridgeSmokeCheck() async {
  final dataDir = await Directory.systemTemp.createTemp('messenger_smoke');
  try {
    final api = await MessengerApi.create(
      homeserverUrl: 'https://matrix.org',
      dataDir: dataDir.path,
      secretStorage: SecretStorage.system,
    );
    final restore = await api.restoreSession();
    final status =
        'messenger_core loaded: homeserver=${api.homeserver()} '
        'user=${api.currentUser()} restore=${restore.name} '
        'sync=${api.syncState().name}';
    api.dispose();
    return status;
  } finally {
    await dataDir.delete(recursive: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!RustLib.instance.initialized) await RustLib.init();
  });

  test('the bundled Rust library answers', () async {
    expect(
      await bridgeSmokeCheck(),
      'messenger_core loaded: homeserver=https://matrix.org/ user=null '
      'restore=noSession sync=stopped',
    );
  });

  test('typed errors and realtime events cross the boundary', () async {
    final server = await FakeHomeserver.start();
    final dataDir = await Directory.systemTemp.createTemp('messenger_it');
    server.syncScript[null] = FakeResponse(
      syncBody('s1', {'!a:example.org': []}),
    );
    server.syncScript['s1'] = FakeResponse(
      syncBody('s2', {
        '!a:example.org': [textEvent(r'$new', '@bob:example.org', 5000, 'Olá')],
      }),
    );

    await expectLater(
      MessengerApi.create(
        homeserverUrl: 'not a url',
        dataDir: dataDir.path,
        secretStorage: SecretStorage.system,
      ),
      throwsA(isA<ApiError_InvalidHomeserver>()),
    );

    final api = await MessengerApi.create(
      homeserverUrl: server.url,
      dataDir: dataDir.path,
      secretStorage: SecretStorage.system,
    );
    await api.login(username: 'alice', password: FakeHomeserver.password);
    final received = api.events().firstWhere(
      (event) => event is CoreEvent_MessageReceived,
    );
    await api.startSync();

    final event = await received.timeout(
      const Duration(seconds: 15),
    ) as CoreEvent_MessageReceived;
    expect(event.roomId, '!a:example.org');
    expect(event.message.body, 'Olá');
    expect(api.syncState(), SyncState.running);

    await api.stopSync();
    // Logging out also removes the secret from the real Keychain.
    expect(await api.logout(), LogoutOutcome.complete);
    api.dispose();
    await server.close();
    await dataDir.delete(recursive: true);
  });
}
