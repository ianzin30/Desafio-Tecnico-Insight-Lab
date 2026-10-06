// Red-team of the application layer over the real Rust engine: offline
// startup, revocation on every path, homeserver switches, unusual event
// sequences, storms and repeated sessions.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/messenger_core.dart';

import '../support/app_harness.dart';
import '../support/fake_homeserver.dart';
import '../support/rust_lib.dart';

const roomA = '!a:example.org';
const roomB = '!b:example.org';
const bob = '@bob:example.org';

Message message(String id, int ts, [String body = 'texto']) =>
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
    dataDir = await Directory.systemTemp.createTemp('messenger_hardening');
    harness = AppHarness(server, dataDir);
    server.syncScript[null] = FakeResponse(
      syncBody('s1', {roomA: [], roomB: []}),
    );
    server.roomMessages[roomA] = [textEvent(r'$a1', bob, 1000, 'Olá A')];
  });

  tearDown(() async {
    harness.stop();
    await server.close();
    await dataDir.delete(recursive: true);
  });

  void expectLoggedOut({
    AuthNotice? notice = AuthNotice.sessionExpired,
    bool syncStopped = true,
  }) {
    final state = harness.state;
    expect(state.phase, AppPhase.unauthenticated);
    expect(state.auth.notice, notice);
    expect(state.rooms.rooms, isEmpty);
    expect(state.conversation, isNull);
    if (syncStopped) expect(state.connection, ConnectionStatus.offline);
  }

  test('an offline startup keeps the valid session and local data', () async {
    await harness.start();
    await harness.login();
    harness.stop();
    await server.close();

    await harness.start();

    expect(harness.state.phase, AppPhase.authenticated);
    expect(harness.state.auth.notice, isNull);
    expect(harness.state.rooms.rooms.map((room) => room.id), [roomA, roomB]);
    await harness.until(
      (state) => state.connection == ConnectionStatus.reconnecting,
    );
    // Still logged in: only a real revocation ends the session.
    expect(harness.state.phase, AppPhase.authenticated);
    expect(harness.state.auth.userId, FakeHomeserver.userId);
  });

  test(
    'revoked while loading messages: back to login, state cleared',
    () async {
      await harness.start();
      await harness.login();
      server.messagesOverride = revokedToken;

      await harness.app.selectRoom(roomA);

      expectLoggedOut();
    },
  );

  test('revoked while sending: back to login, state cleared', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);
    server.sendOverride = revokedToken;

    expect(await harness.app.sendMessage('Oi'), isFalse);

    expectLoggedOut();
  });

  test('a revocation event during a send leaves nothing behind', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);
    server.sendDelay = const Duration(milliseconds: 500);

    // Injected event: the engine itself keeps syncing here (a real
    // revocation stops it before emitting the event).
    final sending = harness.app.sendMessage('Oi');
    final handling = Stopwatch()..start();
    harness.app.onEvent(const CoreEvent.sessionRevoked());
    // Never blocks the UI thread on the running send (it used to, through a
    // synchronous engine getter).
    expect(handling.elapsed, lessThan(const Duration(seconds: 1)));
    expectLoggedOut(syncStopped: false);
    await sending;

    // The late send result changes nothing.
    expectLoggedOut(syncStopped: false);
  });

  test('homeservers A → B → A stay isolated, one engine at a time', () async {
    final serverB = await FakeHomeserver.start();
    serverB.syncScript[null] = FakeResponse(syncBody('s1', {'!b-only:b': []}));
    addTearDown(serverB.close);
    await harness.start();

    await harness.login(to: server);
    expect(harness.state.rooms.contains(roomA), isTrue);
    await harness.app.logout();
    await harness.login(to: serverB);
    expect(harness.state.rooms.rooms.map((room) => room.id), ['!b-only:b']);
    await harness.app.logout();
    await harness.login(to: server);

    expect(harness.state.rooms.rooms.map((room) => room.id), [roomA, roomB]);
    expect(harness.gatewayHomeservers, [server.url, serverB.url, server.url]);
    expect(
      harness.gateways.take(2).every((gateway) => gateway.isDisposed),
      isTrue,
    );
    expect(harness.gateways.last.activeEventStreams(), 1);
    expect(await harness.store.read(), server.url);
    expect(Directory('${harness.engineDir}/stores').listSync(), hasLength(1));
  });

  test('logout during a reconciliation is final', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);
    server.messagesDelay[roomA] = const Duration(milliseconds: 500);

    harness.app.onEvent(const CoreEvent.timelineGap(roomId: roomA));
    expect(harness.state.conversation!.reconciling, isTrue);
    await harness.app.logout();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expectLoggedOut(notice: null);
  });

  test('a room removed while its messages load is closed', () async {
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
    }, delay: Duration(milliseconds: 300));
    server.messagesDelay[roomA] = const Duration(seconds: 2);
    await harness.start();
    await harness.app.login(
      homeserver: server.url,
      username: 'alice',
      password: FakeHomeserver.password,
    );
    await harness.until((state) => state.rooms.contains(roomA));

    final opening = harness.app.selectRoom(roomA);
    await harness.until((state) => !state.rooms.contains(roomA));
    expect(harness.state.conversation, isNull);
    await opening;

    expect(harness.state.conversation, isNull);
    expect(harness.state.phase, AppPhase.authenticated);
  });

  test('a storm of reload events is coalesced', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);
    server.messagesDelay[roomA] = const Duration(milliseconds: 200);
    final before = server.messagesRequests(roomA);

    for (var i = 0; i < 500; i++) {
      harness.app.onEvent(const CoreEvent.roomsChanged());
      harness.app.onEvent(const CoreEvent.eventsLost(count: 1));
      harness.app.onEvent(const CoreEvent.timelineGap(roomId: roomA));
    }
    await harness.until((state) => !state.conversation!.reconciling);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // One reload running plus at most one queued, instead of 1000.
    expect(server.messagesRequests(roomA) - before, inInclusiveRange(1, 2));
    expect(harness.state.conversation!.reconciling, isFalse);
    expect(ids(harness.state), [r'$a1']);
    expect(harness.state.rooms.rooms.map((room) => room.id), [roomA, roomB]);
  });

  test('a storm of messages: deduplicated, ordered, per room', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);

    // 1000 messages, each delivered twice, newest first, with messages of
    // another room mixed in.
    for (var i = 999; i >= 0; i--) {
      final received = message('\$s$i', 10000 + i);
      harness.app.onEvent(
        CoreEvent.messageReceived(roomId: roomA, message: received),
      );
      harness.app.onEvent(
        CoreEvent.messageReceived(roomId: roomA, message: received),
      );
      harness.app.onEvent(
        CoreEvent.messageReceived(roomId: roomB, message: message('\$b$i', i)),
      );
    }

    final timeline = harness.state.conversation!.messages;
    expect(timeline, hasLength(1001));
    expect(timeline.first.id, r'$a1');
    expect(timeline.where((m) => m.id.startsWith(r'$b')), isEmpty);
    for (var i = 1; i < timeline.length; i++) {
      expect(timeline[i].timestampMs, greaterThan(timeline[i - 1].timestampMs));
    }
  });

  test('equal timestamps keep their arrival order', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);

    for (final id in [r'$x', r'$y', r'$z']) {
      harness.app.onEvent(
        CoreEvent.messageReceived(roomId: roomA, message: message(id, 5000)),
      );
    }

    expect(ids(harness.state), [r'$a1', r'$x', r'$y', r'$z']);
  });

  test(
    'Unicode, emoji, multi-line and long texts are sent unchanged',
    () async {
      await harness.start();
      await harness.login();
      await harness.app.selectRoom(roomA);
      final texts = [
        'Olá 👋🏽 — ção, ñ, 中文, עברית',
        '  linha 1\nlinha 2\n\n  linha 4  ',
        'x' * 20000,
      ];

      for (final text in texts) {
        expect(await harness.app.sendMessage(text), isTrue);
      }

      expect(server.sentMessages.map((content) => content['body']), texts);
    },
  );

  test('repeated sessions do not leak engines, streams or stores', () async {
    await harness.start();
    for (var i = 0; i < 8; i++) {
      await harness.login();
      await harness.app.selectRoom(roomA);
      await harness.app.logout();
    }

    expect(harness.gateways, hasLength(1));
    expect(harness.gateways.single.activeEventStreams(), 1);
    expect(Directory('${harness.engineDir}/stores').listSync(), hasLength(1));
    expect(File('${harness.engineDir}/session.json').existsSync(), isFalse);
  });
}
