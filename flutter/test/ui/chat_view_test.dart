import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/messenger_core.dart';
import 'package:messenger_app/ui/chat_page.dart';
import 'package:messenger_app/ui/sidebar.dart';
import 'package:messenger_app/ui/theme.dart';

import 'ui_host.dart';

const me = '@ana:matrix.org';
const bob = '@bruno:example.org';
final now = DateTime(2026, 10, 6, 15);

const rooms = [
  RoomSummary(id: '!b:x', displayName: 'Equipe Backend', isDirect: false),
  RoomSummary(id: '!a:x', displayName: 'Alice Souza', isDirect: true),
  RoomSummary(id: '!d:x', displayName: 'Design & Produto', isDirect: false),
  RoomSummary(id: '!c:x', displayName: '@carla:example.org', isDirect: true),
];

Message message(String id, int minute, {bool own = false, String? body}) =>
    Message(
      id: id,
      sender: own ? me : bob,
      body: body ?? 'mensagem $id',
      timestampMs: DateTime(2026, 10, 6, 9, minute).millisecondsSinceEpoch,
      isOwn: own,
    );

final composer = find.byKey(const Key('composer.input'));
final send = find.byKey(const Key('composer.send'));

bool enabled(WidgetTester tester, Finder button) =>
    tester
        .widget<TextButton>(
          find.descendant(of: button, matching: find.byType(TextButton)),
        )
        .onPressed !=
    null;

/// Holds the inputs of a [ChatView] and records its callbacks.
class ChatHarness {
  RoomsState roomsState = const RoomsState(rooms: rooms);
  ConversationState? conversation;
  ConnectionStatus connection = ConnectionStatus.online;
  String? removedRoomName;
  final selected = <String>[];
  final sent = <String>[];
  int retriedRooms = 0, retriedConversation = 0, logouts = 0;
  Completer<bool>? sendResult;

  Widget build() => ChatView(
    userId: me,
    rooms: roomsState,
    conversation: conversation,
    connection: connection,
    removedRoomName: removedRoomName,
    onDismissRemoved: () => removedRoomName = null,
    onSelectRoom: selected.add,
    onRetryRooms: () => retriedRooms++,
    onRetryConversation: () => retriedConversation++,
    onSend: (body) {
      sent.add(body);
      return (sendResult ??= Completer<bool>()..complete(true)).future;
    },
    onLogout: () => logouts++,
    bannerDelay: const Duration(milliseconds: 100),
    now: () => now,
  );

  Future<void> show(WidgetTester tester, {Size? size}) =>
      pumpView(tester, build(), size: size ?? const Size(1280, 800));

  Future<void> update(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(Brightness.light), home: build()),
    );
    await tester.pump();
  }
}

void main() {
  late ChatHarness chat;

  setUp(() => chat = ChatHarness());

  testWidgets('rooms are split into directs and groups, alphabetically', (
    tester,
  ) async {
    await chat.show(tester);

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where(
          (label) => const [
            'DIRETAS',
            'GRUPOS',
            'Alice Souza',
            '@carla:example.org',
            'Design & Produto',
            'Equipe Backend',
          ].contains(label),
        )
        .toList();
    expect(labels, [
      'DIRETAS',
      'Alice Souza',
      '@carla:example.org',
      'GRUPOS',
      'Design & Produto',
      'Equipe Backend',
    ]);
    expect(find.text('Nenhuma conversa aberta'), findsOneWidget);
    expect(find.text(me), findsOneWidget);

    await tester.tap(find.byKey(const Key('room.!b:x')));
    expect(chat.selected, ['!b:x']);
  });

  testWidgets('first sync: skeleton rooms and "Sincronizando…"', (
    tester,
  ) async {
    chat
      ..roomsState = const RoomsState(loading: true)
      ..connection = ConnectionStatus.connecting;
    await chat.show(tester);

    expect(find.text('Sincronizando…'), findsOneWidget);
    expect(find.text('Nenhuma conversa.'), findsNothing);
  });

  testWidgets('no rooms at all', (tester) async {
    chat.roomsState = const RoomsState();
    await chat.show(tester);

    expect(find.text('Nenhuma conversa.'), findsOneWidget);
    expect(
      find.text('Você ainda não participa de nenhuma conversa'),
      findsOneWidget,
    );
  });

  testWidgets('rooms that failed to load can be retried', (tester) async {
    chat.roomsState = const RoomsState(failure: RoomsFailure.network);
    await chat.show(tester);

    await tester.tap(find.text('Tentar de novo'));
    expect(chat.retriedRooms, 1);
  });

  testWidgets('loading, error and empty conversations', (tester) async {
    chat.conversation = const ConversationState(roomId: '!b:x', loading: true);
    await chat.show(tester);
    expect(find.text('Carregando mensagens…'), findsOneWidget);
    expect(find.text('Equipe Backend'), findsWidgets);
    expect(find.text('Grupo'), findsOneWidget);

    chat.conversation = const ConversationState(
      roomId: '!b:x',
      failure: ConversationFailure.network,
    );
    await chat.update(tester);
    expect(find.text('Não foi possível carregar as mensagens'), findsOneWidget);
    expect(
      find.text('Disponível depois que a conversa carregar.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(composer).enabled, isFalse);
    await tester.tap(find.text('Tentar de novo'));
    expect(chat.retriedConversation, 1);

    chat.conversation = const ConversationState(roomId: '!a:x');
    await chat.update(tester);
    expect(find.text('Nenhuma mensagem ainda'), findsOneWidget);
    expect(
      find.text('Envie a primeira mensagem para Alice Souza.'),
      findsOneWidget,
    );
    expect(find.text('Conversa direta'), findsOneWidget);
  });

  testWidgets('messages are grouped, own ones labelled "Você"', (tester) async {
    chat.conversation = ConversationState(
      roomId: '!b:x',
      messages: [
        message(r'$1', 14),
        message(r'$2', 15),
        message(r'$3', 20, own: true),
      ],
    );
    await chat.show(tester);

    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text(bob), findsOneWidget, reason: 'one group for two');
    expect(find.text('Você'), findsOneWidget);
    expect(find.text(r'mensagem $1'), findsOneWidget);
  });

  testWidgets('sending: Enter sends the text unchanged, then clears it', (
    tester,
  ) async {
    chat
      ..conversation = const ConversationState(roomId: '!b:x')
      ..sendResult = Completer<bool>();
    await chat.show(tester);
    expect(enabled(tester, send), isFalse);

    await tester.enterText(composer, '  Olá!  ');
    await tester.pump();
    expect(enabled(tester, send), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(chat.sent, ['  Olá!  ']);
    expect(find.text('Enviando'), findsOneWidget);
    expect(tester.widget<TextField>(composer).readOnly, isTrue);

    chat.sendResult!.complete(true);
    await tester.pump();
    expect(find.text('Enviando'), findsNothing);
    expect(tester.widget<TextField>(composer).controller!.text, '');
  });

  testWidgets('a failed send keeps the text and offers a retry', (
    tester,
  ) async {
    chat
      ..conversation = const ConversationState(roomId: '!b:x')
      ..sendResult = (Completer<bool>()..complete(false));
    await chat.show(tester);

    await tester.enterText(composer, 'Oi');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();

    expect(find.text('Não foi possível enviar.'), findsOneWidget);
    expect(tester.widget<TextField>(composer).controller!.text, 'Oi');
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();
    expect(chat.sent, ['Oi', 'Oi']);
  });

  testWidgets('blank text and Shift+Enter do not send', (tester) async {
    chat.conversation = const ConversationState(roomId: '!b:x');
    await chat.show(tester);

    await tester.enterText(composer, '   ');
    await tester.pump();
    expect(enabled(tester, send), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    await tester.enterText(composer, 'linha');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(chat.sent, isEmpty);
  });

  testWidgets('drafts are kept per room', (tester) async {
    chat.conversation = const ConversationState(roomId: '!b:x');
    await chat.show(tester);
    await tester.enterText(composer, 'rascunho B');

    chat.conversation = const ConversationState(roomId: '!a:x');
    await chat.update(tester);
    expect(tester.widget<TextField>(composer).controller!.text, '');

    chat.conversation = const ConversationState(roomId: '!b:x');
    await chat.update(tester);
    expect(tester.widget<TextField>(composer).controller!.text, 'rascunho B');
  });

  testWidgets('reconnecting: banner after a delay, sending disabled', (
    tester,
  ) async {
    chat.conversation = ConversationState(
      roomId: '!b:x',
      messages: [message(r'$1', 1)],
    );
    await chat.show(tester);
    await tester.enterText(composer, 'Oi');

    chat.connection = ConnectionStatus.reconnecting;
    await chat.update(tester);
    expect(find.byKey(const Key('banner.offline')), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('banner.offline')), findsOneWidget);
    expect(find.text(r'mensagem $1'), findsOneWidget, reason: 'data kept');
    expect(enabled(tester, send), isFalse);
    expect(
      find.text('Você poderá enviar quando a conexão voltar.'),
      findsOneWidget,
    );

    chat.connection = ConnectionStatus.online;
    await chat.update(tester);
    expect(find.byKey(const Key('banner.back')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('banner.back')), findsNothing);
  });

  testWidgets('a short reconnection shows no banner', (tester) async {
    await chat.show(tester);
    chat.connection = ConnectionStatus.reconnecting;
    await chat.update(tester);
    chat.connection = ConnectionStatus.online;
    await chat.update(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('banner.offline')), findsNothing);
    expect(find.byKey(const Key('banner.back')), findsNothing);
  });

  testWidgets('reconciling shows "Atualizando conversa…" after 300 ms', (
    tester,
  ) async {
    chat.conversation = ConversationState(
      roomId: '!b:x',
      messages: [message(r'$1', 1)],
      reconciling: true,
    );
    await chat.show(tester);
    expect(find.text('Atualizando conversa…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Atualizando conversa…'), findsOneWidget);
  });

  testWidgets('removed room notice', (tester) async {
    chat.removedRoomName = 'Equipe Backend';
    await chat.show(tester);

    expect(
      find.textContaining(
        'Você não está mais em “Equipe Backend”.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await chat.update(tester);
    expect(
      find.textContaining(
        'Você não está mais em “Equipe Backend”.',
        findRichText: true,
      ),
      findsNothing,
    );
  });

  testWidgets('logout asks for confirmation; Cancel and Esc close it', (
    tester,
  ) async {
    await chat.show(tester);
    Future<void> openDialog() async {
      await tester.tap(find.byKey(const Key('account.menu')));
      await tester.pumpAndSettle();
      expect(find.text('Conectado como'), findsOneWidget);
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(find.text('Sair da conta?'), findsOneWidget);
    }

    await openDialog();
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(find.text('Sair da conta?'), findsNothing);

    await openDialog();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Sair da conta?'), findsNothing);
    expect(chat.logouts, 0);

    await openDialog();
    await tester.tap(find.byKey(const Key('logout.confirm')));
    await tester.pump();
    expect(chat.logouts, 1);
  });

  testWidgets('new messages while reading above show a pill', (tester) async {
    final many = [for (var i = 0; i < 40; i++) message('\$m$i', i)];
    chat.conversation = ConversationState(roomId: '!b:x', messages: many);
    await chat.show(tester);

    // Read above, then a message from someone else arrives.
    await tester.drag(find.text(r'mensagem $m39'), const Offset(0, 1500));
    await tester.pumpAndSettle();
    chat.conversation = ConversationState(
      roomId: '!b:x',
      messages: [...many, message(r'$new', 50)],
    );
    await chat.update(tester);
    expect(find.text('1 nova mensagem'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timeline.newMessages')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline.newMessages')), findsNothing);
    expect(find.text(r'mensagem $new'), findsOneWidget);
  });

  testWidgets('own messages never show the pill', (tester) async {
    final many = [for (var i = 0; i < 40; i++) message('\$m$i', i)];
    chat.conversation = ConversationState(roomId: '!b:x', messages: many);
    await chat.show(tester);

    await tester.drag(find.text(r'mensagem $m39'), const Offset(0, 1500));
    await tester.pumpAndSettle();
    chat.conversation = ConversationState(
      roomId: '!b:x',
      messages: [...many, message(r'$mine', 50, own: true)],
    );
    await chat.update(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline.newMessages')), findsNothing);
  });

  testWidgets('minimum window, long names, dark theme: no overflow', (
    tester,
  ) async {
    chat
      ..roomsState = const RoomsState(
        rooms: [
          RoomSummary(
            id: '!long:x',
            displayName: 'Projeto Lote 10 — arquitetura do sync engine v2',
            isDirect: false,
          ),
        ],
      )
      ..conversation = ConversationState(
        roomId: '!long:x',
        messages: [
          message(
            r'$url',
            1,
            body:
                'https://docs.example.org/projetos/lote-10/arquitetura-sync-'
                'engine-v2#reconciliacao-de-timeline-com-um-endereco-longo',
          ),
        ],
      );
    await pumpView(
      tester,
      chat.build(),
      size: const Size(720, 480),
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Sidebar)).width, 224);
  });
}
