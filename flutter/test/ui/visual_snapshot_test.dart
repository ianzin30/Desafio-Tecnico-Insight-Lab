// Renders the main screens to PNG files for visual review against the
// high-fidelity prototype. Runs only with SNAPSHOT_DIR set:
//   SNAPSHOT_DIR=/tmp/shots flutter test test/ui/visual_snapshot_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/messenger_core.dart';
import 'package:messenger_app/ui/app.dart';
import 'package:messenger_app/ui/chat_page.dart';
import 'package:messenger_app/ui/login_page.dart';
import 'package:messenger_app/ui/theme.dart';

final outputDir = Platform.environment['SNAPSHOT_DIR'];

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
    );
  }
  await loader.load();
}

Message msg(
  String id,
  String sender,
  int h,
  int m,
  String body, {
  bool own = false,
}) => Message(
  id: id,
  sender: sender,
  body: body,
  timestampMs: DateTime(2026, 10, 6, h, m).millisecondsSinceEpoch,
  isOwn: own,
);

void main() {
  setUpAll(() async {
    if (outputDir == null) return;
    await loadFont(sansFont, [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/IBMPlexSans-$w.ttf',
    ]);
    await loadFont(monoFont, [
      for (final w in ['Regular', 'Medium', 'SemiBold'])
        'assets/fonts/IBMPlexMono-$w.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    await loadFont('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget view, {
    Size size = const Size(1280, 800),
    Brightness brightness = Brightness.light,
    Future<void> Function()? interact,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(brightness),
          home: view,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    if (interact != null) await interact();
    await tester.pump(const Duration(milliseconds: 500));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$outputDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  const alice = '@alice:example.org', bruno = '@bruno:example.org';
  const rooms = RoomsState(
    rooms: [
      RoomSummary(id: '!alice', displayName: 'Alice Souza', isDirect: true),
      RoomSummary(id: '!bruno', displayName: 'bruno', isDirect: true),
      RoomSummary(
        id: '!carla',
        displayName: '@carla:example.org',
        isDirect: true,
      ),
      RoomSummary(
        id: '!design',
        displayName: 'Design & Produto',
        isDirect: false,
      ),
      RoomSummary(
        id: '!backend',
        displayName: 'Equipe Backend',
        isDirect: false,
      ),
      RoomSummary(
        id: '!lote',
        displayName: 'Projeto Lote 10 — arquitetura do sync',
        isDirect: false,
      ),
      RoomSummary(id: '!random', displayName: 'Random', isDirect: false),
    ],
  );
  final backend = ConversationState(
    roomId: '!backend',
    messages: [
      Message(
        id: r'$y1',
        sender: alice,
        body: 'Subi o PR da engine de sync.',
        timestampMs: DateTime(2026, 10, 5, 18, 2).millisecondsSinceEpoch,
        isOwn: false,
      ),
      Message(
        id: r'$y2',
        sender: alice,
        body: 'Quem puder revisar amanhã, agradeço.',
        timestampMs: DateTime(2026, 10, 5, 18, 3).millisecondsSinceEpoch,
        isOwn: false,
      ),
      msg(
        r'$1',
        bruno,
        9,
        14,
        'Revisei. Só um comentário sobre o tratamento de gap: acho que a '
            'reconciliação deveria trocar a timeline inteira de uma vez.',
      ),
      msg(r'$2', bruno, 9, 15, 'Assim a gente evita flash na interface.'),
      msg(
        r'$3',
        '@ana:matrix.org',
        9,
        20,
        'Boa, faz sentido. Vou ajustar.',
        own: true,
      ),
      msg(
        r'$4',
        '@ana:matrix.org',
        9,
        21,
        'Faço o merge depois do almoço.',
        own: true,
      ),
      msg(r'$5', alice, 9, 31, 'Perfeito, obrigada!'),
    ],
  );

  ChatView chat({
    ConversationState? conversation,
    ConnectionStatus connection = ConnectionStatus.online,
  }) => ChatView(
    userId: '@ana:matrix.org',
    rooms: rooms,
    conversation: conversation,
    connection: connection,
    onSelectRoom: (_) {},
    onRetryRooms: () {},
    onRetryConversation: () {},
    onSend: (_) async => true,
    onLogout: () {},
    bannerDelay: Duration.zero,
    now: () => DateTime(2026, 10, 6, 15),
  );

  LoginView login(AuthState auth) => LoginView(
    auth: auth,
    initialServer: 'matrix.org',
    initialUsername: 'ana',
    onSubmit: (_, _, _) {},
    onDismissMessage: () {},
  );

  final skip = outputDir == null ? 'set SNAPSHOT_DIR to render' : null;

  testWidgets('login', skip: skip != null, (tester) async {
    await shoot(tester, 'login', login(const AuthState()));
    await shoot(
      tester,
      'login_error_dark',
      login(const AuthState(failure: AuthFailure.network)),
      brightness: Brightness.dark,
    );
    await shoot(
      tester,
      'login_credentials',
      login(const AuthState(failure: AuthFailure.invalidCredentials)),
    );
  });

  testWidgets('chat', skip: skip != null, (tester) async {
    await shoot(tester, 'chat', chat(conversation: backend));
    await shoot(
      tester,
      'chat_dark_reconnecting',
      chat(conversation: backend, connection: ConnectionStatus.reconnecting),
      brightness: Brightness.dark,
    );
    await shoot(
      tester,
      'chat_compact',
      chat(conversation: backend),
      size: const Size(720, 480),
    );
    await shoot(tester, 'chat_none', chat());
    await shoot(
      tester,
      'chat_error',
      chat(
        conversation: const ConversationState(
          roomId: '!random',
          failure: ConversationFailure.network,
        ),
      ),
    );
    await shoot(
      tester,
      'logout_dialog',
      chat(conversation: backend),
      interact: () async {
        await tester.tap(find.byKey(const Key('account.menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sair'));
        await tester.pumpAndSettle();
      },
    );
    await shoot(tester, 'expired', ExpiredView(onContinue: () {}));
  });
}
