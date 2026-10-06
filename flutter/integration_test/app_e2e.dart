// End-to-end test of the whole app through its UI, on the desktop target:
// real widgets, application layer, Rust engine and a local fake homeserver.
// Run by app_test.dart.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:messenger_app/app/homeserver_store.dart';
import 'package:messenger_app/app/messenger_gateway.dart';
import 'package:messenger_app/app/providers.dart';
import 'package:messenger_app/ui/app.dart';

import '../test/support/fake_homeserver.dart';

const room = '!backend:example.org';
const bob = '@bob:example.org';

Map<String, dynamic> nameEvent(String name) => {
  'type': 'm.room.name',
  'state_key': '',
  'event_id': '\$name-$name',
  'sender': bob,
  'origin_server_ts': 1,
  'content': {'name': name},
};

/// Saves the current rendering of [boundary] as `<name>.png` in the temp
/// directory (inside the app container on macOS).
Future<void> screenshot(GlobalKey boundary, String name) async {
  final image =
      await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${Directory.systemTemp.path}/$name.png')
    ..writeAsBytesSync(png!.buffer.asUint8List());
  debugPrint('E2E screenshot: ${file.path}');
}

/// Pumps frames until [finder] matches (spinners never settle).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('not found in time: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, chat, realtime, logout and expired session', (
    tester,
  ) async {
    final server = await FakeHomeserver.start();
    final dataDir = await Directory.systemTemp.createTemp('messenger_e2e');
    final now = DateTime.now().millisecondsSinceEpoch;
    server.syncScript[null] = FakeResponse(
      syncBody(
        's1',
        {room: [], '!random:example.org': []},
        state: {
          room: [nameEvent('Equipe Backend')],
          '!random:example.org': [nameEvent('Random')],
        },
      ),
    );
    server.roomMessages[room] = [
      textEvent(r'$1', bob, now - 60000, 'Bom dia!'),
    ];

    final boundary = GlobalKey();
    final container = ProviderContainer(
      overrides: [
        homeserverStoreProvider.overrideWithValue(
          FileHomeserverStore(Future.value(dataDir)),
        ),
        gatewayFactoryProvider.overrideWithValue(
          (url) => RustMessengerGateway.create(
            homeserverUrl: url,
            dataDir: '${dataDir.path}/matrix',
          ),
        ),
      ],
    );
    container.read(messengerProvider);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: UncontrolledProviderScope(
          container: container,
          child: const MessengerApp(),
        ),
      ),
    );

    // First run: login screen. Wrong password first.
    await pumpUntil(tester, find.text('Entrar na sua conta'));
    await tester.enterText(field('login.server'), server.url);
    await tester.enterText(field('login.username'), 'alice');
    await tester.enterText(field('login.password'), 'errada');
    await tester.pump();
    await tester.tap(find.byKey(const Key('login.submit')));
    await pumpUntil(tester, find.text('Usuário ou senha incorretos.'));
    await tester.pump(const Duration(milliseconds: 300));
    await screenshot(boundary, 'e2e_login_error');

    // Right password: rooms from the first sync.
    await tester.enterText(field('login.password'), FakeHomeserver.password);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntil(tester, find.text('Equipe Backend'));
    expect(find.text('Random'), findsOneWidget);
    expect(find.text(FakeHomeserver.userId), findsOneWidget);
    expect(find.text('Nenhuma conversa aberta'), findsOneWidget);

    // Open the room: its history.
    await tester.tap(find.byKey(const Key('room.$room')));
    await pumpUntil(tester, find.text('Bom dia!'));
    expect(find.byKey(const Key('room.header')), findsOneWidget);

    // Send with Enter: the homeserver receives the text unchanged.
    await tester.enterText(
      find.byKey(const Key('composer.input')),
      'Olá do E2E',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 100 && server.sentMessages.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(server.sentMessages, [
      {'msgtype': 'm.text', 'body': 'Olá do E2E'},
    ]);

    // Realtime: the sync confirms it and brings a reply.
    server.syncScript['s1'] = FakeResponse(
      syncBody('s2', {
        room: [
          textEvent(r'$sent', FakeHomeserver.userId, now, 'Olá do E2E'),
          textEvent(r'$2', bob, now + 1000, 'Recebido em tempo real'),
        ],
      }),
    );
    await pumpUntil(tester, find.text('Recebido em tempo real'));
    expect(find.text('Olá do E2E'), findsOneWidget);
    expect(find.text('Você'), findsOneWidget);

    // Real rendering (shadows, fonts) for visual review.
    await tester.pump(const Duration(milliseconds: 300));
    await screenshot(boundary, 'e2e_chat');

    // Logout through the account menu and its confirmation.
    await tester.tap(find.byKey(const Key('account.menu')));
    await pumpUntil(tester, find.byKey(const Key('account.logout')));
    await tester.pump(const Duration(milliseconds: 500)); // menu animation
    await tester.tap(find.byKey(const Key('account.logout')));
    await pumpUntil(tester, find.text('Sair da conta?'));
    await tester.tap(find.byKey(const Key('logout.confirm')));
    await pumpUntil(tester, find.text('Entrar na sua conta'));
    // Prefilled with the last homeserver and username.
    expect(find.text(server.url), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);

    // Log in again; then the homeserver revokes the session.
    server.syncScript['s2'] = const FakeResponse({
      'errcode': 'M_UNKNOWN_TOKEN',
      'error': 'Token revoked',
    }, status: 401);
    await tester.enterText(field('login.password'), FakeHomeserver.password);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntil(tester, find.text('Sua sessão expirou'));
    await tester.tap(find.byKey(const Key('expired.continue')));
    await pumpUntil(tester, find.text('Sua sessão expirou.'));
    expect(find.text('Entrar na sua conta'), findsOneWidget);

    container.dispose();
    await server.close();
    await dataDir.delete(recursive: true);
  });
}
