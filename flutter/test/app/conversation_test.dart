// Application layer: rooms, the selected conversation and realtime events.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/messenger_core.dart';

import '../support/app_harness.dart';
import '../support/fake_homeserver.dart';
import '../support/rust_lib.dart';

const roomA = '!a:example.org';
const roomB = '!b:example.org';
const roomC = '!c:example.org';
const bob = '@bob:example.org';

/// The sync after the baseline arrives after this delay (like a long poll),
/// so a room can be selected before it.
const nextSyncDelay = Duration(seconds: 1);

Message message(String id, int ts, String body) =>
    Message(id: id, sender: bob, body: body, timestampMs: ts, isOwn: false);

List<String> ids(MessengerState state) =>
    state.conversation!.messages.map((message) => message.id).toList();

void main() {
  late FakeHomeserver server;
  late Directory dataDir;
  late AppHarness harness;

  setUpAll(initRustForTests);

  setUp(() async {
    server = await FakeHomeserver.start();
    dataDir = await Directory.systemTemp.createTemp('messenger_app_test');
    harness = AppHarness(server, dataDir);
    server.syncScript[null] = FakeResponse(
      syncBody('s1', {roomA: [], roomB: []}),
    );
    server.roomMessages[roomA] = [textEvent(r'$a1', bob, 1000, 'Olá A')];
    server.roomMessages[roomB] = [textEvent(r'$b1', bob, 1000, 'Olá B')];
  });

  tearDown(() async {
    harness.stop();
    await server.close();
    await dataDir.delete(recursive: true);
  });

  /// Starts, logs in and opens room A.
  Future<void> openRoomA() async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);
    expect(ids(harness.state), [r'$a1']);
  }

  test('rooms changes are reconciled from the engine', () async {
    server.syncScript['s1'] = FakeResponse(
      syncBody('s2', {roomC: []}),
      delay: nextSyncDelay,
    );
    await harness.start();
    await harness.login();
    expect(harness.state.rooms.rooms.map((room) => room.id), [roomA, roomB]);

    await harness.until((state) => state.rooms.contains(roomC));

    expect(harness.state.rooms.rooms.map((room) => room.id), [
      roomA,
      roomB,
      roomC,
    ]);
  });

  test('a room that disappears closes its conversation', () async {
    server.syncScript['s1'] = const FakeResponse({
      'next_batch': 's2',
      'rooms': {
        'leave': {
          roomA: {
            'state': {'events': []},
            'timeline': {'events': []},
          },
        },
      },
    }, delay: nextSyncDelay);
    await openRoomA();

    await harness.until((state) => !state.rooms.contains(roomA));

    expect(harness.state.conversation, isNull);
    expect(harness.state.rooms.rooms.map((room) => room.id), [roomB]);
  });

  test('new messages of the selected room are added once, in order', () async {
    server.syncScript['s1'] = FakeResponse(
      syncBody('s2', {
        roomA: [textEvent(r'$a2', bob, 2000, 'Nova A')],
        roomB: [textEvent(r'$b2', bob, 2000, 'Nova B')],
      }),
      delay: nextSyncDelay,
    );
    await openRoomA();

    await harness.until((state) => ids(state).contains(r'$a2'));

    // The same event again, and an older one arriving late.
    harness.app.onEvent(
      CoreEvent.messageReceived(
        roomId: roomA,
        message: message(r'$a2', 2000, 'Nova A'),
      ),
    );
    harness.app.onEvent(
      CoreEvent.messageReceived(
        roomId: roomA,
        message: message(r'$late', 1500, 'Atrasada'),
      ),
    );
    // Room B's message does not reach room A's timeline.
    expect(ids(harness.state), [r'$a1', r'$late', r'$a2']);
  });

  test('a gap in the selected room reloads its timeline', () async {
    server.syncScript['s1'] = FakeResponse(
      syncBody('s2', {roomA: []}, limited: true),
      delay: nextSyncDelay,
    );
    await openRoomA();
    server.roomMessages[roomA] = [
      textEvent(r'$a3', bob, 3000, 'Fresca 2'),
      textEvent(r'$a2', bob, 2000, 'Fresca 1'),
    ];

    await harness.until((state) => ids(state).contains(r'$a3'));

    expect(ids(harness.state), [r'$a2', r'$a3']);
    expect(harness.state.conversation!.reconciling, isFalse);
    expect(server.messagesRequests(roomA), 2);
  });

  test('a gap in another room causes no request', () async {
    server.syncScript['s1'] = FakeResponse(
      syncBody('s2', {roomB: []}, limited: true),
      delay: nextSyncDelay,
    );
    await openRoomA();

    await harness.until(
      (_) =>
          server.requestPaths.where((path) => path.endsWith('/sync')).length >=
          3,
    );

    expect(server.messagesRequests(roomB), 0);
    expect(server.messagesRequests(roomA), 1);
  });

  test('lost events reload the rooms and the conversation', () async {
    await openRoomA();
    server.roomMessages[roomA] = [textEvent(r'$a9', bob, 9000, 'Recuperada')];

    harness.app.onEvent(const CoreEvent.eventsLost(count: 3));

    await harness.until((state) => ids(state).contains(r'$a9'));
    expect(ids(harness.state), [r'$a9']);
    expect(harness.state.rooms.rooms.map((room) => room.id), [roomA, roomB]);
  });

  test(
    'a late result of a previous room does not overwrite the new one',
    () async {
      server.messagesDelay[roomA] = const Duration(milliseconds: 800);
      await harness.start();
      await harness.login();

      final selectA = harness.app.selectRoom(roomA);
      await harness.app.selectRoom(roomB);
      expect(ids(harness.state), [r'$b1']);
      await selectA;

      expect(harness.state.selectedRoomId, roomB);
      expect(ids(harness.state), [r'$b1']);
      expect(harness.state.conversation!.loading, isFalse);
    },
  );

  test('reconnecting keeps rooms and messages', () async {
    server.syncScript['s1'] = const FakeResponse({
      'errcode': 'M_UNKNOWN',
      'error': 'Unavailable',
    }, status: 503);
    await openRoomA();

    await harness.until(
      (state) => state.connection == ConnectionStatus.reconnecting,
    );

    final state = harness.state;
    expect(state.phase, AppPhase.authenticated);
    expect(state.rooms.rooms.map((room) => room.id), [roomA, roomB]);
    expect(ids(state), [r'$a1']);
  });

  test(
    'sending goes through the engine, unchanged, without local echo',
    () async {
      await openRoomA();

      final sending = harness.app.sendMessage('  Olá!\n');
      expect(harness.state.conversation!.sending, isTrue);
      expect(await sending, isTrue);

      expect(server.sentMessages, [
        {'msgtype': 'm.text', 'body': '  Olá!\n'},
      ]);
      expect(harness.state.conversation!.sending, isFalse);
      expect(ids(harness.state), [r'$a1']);

      expect(await harness.app.sendMessage('   '), isFalse);
      expect(
        harness.state.conversation!.failure,
        ConversationFailure.emptyMessage,
      );
    },
  );

  test('bursts of gaps and lost events are coalesced', () async {
    await openRoomA();
    server.messagesDelay[roomA] = const Duration(milliseconds: 300);
    final before = server.messagesRequests(roomA);

    for (var i = 0; i < 5; i++) {
      harness.app.onEvent(const CoreEvent.timelineGap(roomId: roomA));
      harness.app.onEvent(const CoreEvent.eventsLost(count: 1));
    }
    await harness.until((state) => !state.conversation!.reconciling);
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // One reload running plus at most one queued, instead of ten.
    final reloads = server.messagesRequests(roomA) - before;
    expect(reloads, inInclusiveRange(1, 2));
    expect(harness.state.conversation!.reconciling, isFalse);
    expect(ids(harness.state), [r'$a1']);
  });

  test('a message received while loading is kept', () async {
    server.messagesDelay[roomA] = const Duration(milliseconds: 500);
    await harness.start();
    await harness.login();

    final opening = harness.app.selectRoom(roomA);
    expect(harness.state.conversation!.loading, isTrue);
    harness.app.onEvent(
      CoreEvent.messageReceived(
        roomId: roomA,
        message: message(r'$live', 5000, 'Chegou agora'),
      ),
    );
    await opening;

    // The load result (without it) did not drop the live message.
    expect(ids(harness.state), [r'$a1', r'$live']);
    expect(harness.state.conversation!.loading, isFalse);
  });
}
