// Window sizes, themes, extreme content and keyboard navigation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/messenger_core.dart';
import 'package:messenger_app/ui/chat_page.dart';
import 'package:messenger_app/ui/login_page.dart';

import 'ui_host.dart';

const sizes = [
  Size(720, 480), // minimum
  Size(959, 600), // just under the compact breakpoint
  Size(960, 600),
  Size(1280, 800), // default
  Size(1920, 1080), // maximized
];

ChatView chat({ConnectionStatus connection = ConnectionStatus.online}) {
  final rooms = [
    for (var i = 0; i < 60; i++)
      RoomSummary(
        id: '!room$i:a-very-long-homeserver-name.example.org',
        displayName: i.isEven
            ? 'Sala $i com um nome muito longo que não cabe na barra lateral'
            : '@usuario.com.um.id.bem.comprido.$i:servidor.example.org',
        isDirect: i.isOdd,
      ),
  ];
  return ChatView(
    userId: '@uma.conta.com.nome.realmente.longo:matrix.example.org',
    rooms: RoomsState(rooms: rooms),
    conversation: ConversationState(
      roomId: rooms.first.id,
      messages: [
        for (var i = 0; i < 30; i++)
          Message(
            id: '\$m$i',
            sender: i.isEven
                ? '@alguem.com.um.id.muito.longo.mesmo:servidor.example.org'
                : '@ana:matrix.org',
            body: i % 3 == 0
                ? 'Olá 👋🏽 ção 中文 ${'palavra ' * 80}'
                : 'https://example.org/${'segmento-sem-espacos-' * 20}',
            timestampMs: DateTime(2026, 10, 6, 9, i).millisecondsSinceEpoch,
            isOwn: i.isOdd,
          ),
      ],
    ),
    connection: connection,
    onSelectRoom: (_) {},
    onRetryRooms: () {},
    onRetryConversation: () {},
    onSend: (_) async => true,
    onLogout: () {},
    bannerDelay: Duration.zero,
    now: () => DateTime(2026, 10, 6, 15),
  );
}

LoginView login({AuthState auth = const AuthState(), String user = ''}) =>
    LoginView(
      auth: auth,
      initialServer: 'matrix.org',
      initialUsername: user,
      onSubmit: (_, _, _) {},
      onDismissMessage: () {},
    );

bool focused(WidgetTester tester, String key) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
      ),
    )
    .focusNode!
    .hasFocus;

void main() {
  for (final brightness in Brightness.values) {
    for (final size in sizes) {
      final label =
          '${size.width.toInt()}×${size.height.toInt()} ${brightness.name}';

      testWidgets('chat fits $label', (tester) async {
        await pumpView(
          tester,
          chat(connection: ConnectionStatus.reconnecting),
          size: size,
          brightness: brightness,
        );
        await tester.pump(const Duration(milliseconds: 10));

        expect(tester.takeException(), isNull);
        final composer = tester.getRect(
          find.byKey(const Key('composer.input')),
        );
        expect(composer.bottom, lessThanOrEqualTo(size.height));
        expect(composer.right, lessThanOrEqualTo(size.width));
      });

      testWidgets('login fits $label', (tester) async {
        await pumpView(
          tester,
          login(auth: const AuthState(failure: AuthFailure.network)),
          size: size,
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('logout dialog stays on screen at the minimum size', (
    tester,
  ) async {
    await pumpView(tester, chat(), size: const Size(720, 480));
    await tester.tap(find.byKey(const Key('account.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.text('Sair da conta?'));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(
      tester.getRect(find.byKey(const Key('logout.confirm'))).bottom,
      lessThanOrEqualTo(480),
    );
  });

  testWidgets('login: Tab and Shift+Tab move between the fields', (
    tester,
  ) async {
    await pumpView(tester, login());
    await tester.pump();
    expect(focused(tester, 'login.username'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(tester, 'login.password'), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(focused(tester, 'login.username'), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(focused(tester, 'login.server'), isTrue);
  });

  testWidgets('composer: Esc leaves the field and keeps the text', (
    tester,
  ) async {
    await pumpView(tester, chat());
    final input = find.byKey(const Key('composer.input'));
    await tester.tap(input);
    await tester.enterText(input, 'rascunho');
    await tester.pump();
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, 'rascunho');
  });
}
