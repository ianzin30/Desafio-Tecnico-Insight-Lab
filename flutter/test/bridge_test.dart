// End-to-end tests of the Dart <-> Rust boundary: real Rust library, local
// fake homeserver, no internet.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/messenger_core.dart';

import 'support/fake_homeserver.dart';
import 'support/rust_lib.dart';

const roomA = '!a:example.org';
const roomB = '!b:example.org';
const timeout = Duration(seconds: 15);

/// Records the events of a stream and waits for specific ones.
class EventRecorder {
  EventRecorder(Stream<CoreEvent> stream) {
    subscription = stream.listen(
      (event) {
        events.add(event);
        _changed.add(null);
      },
      onDone: () {
        done = true;
        _changed.add(null);
      },
    );
  }

  final events = <CoreEvent>[];
  final _changed = StreamController<void>.broadcast();
  late final StreamSubscription<CoreEvent> subscription;
  bool done = false;

  /// Waits until an event (from index `from`) matches; returns its index.
  Future<int> waitFor(bool Function(CoreEvent) test, {int from = 0}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final index = events.indexWhere(test, from);
      if (index >= 0) return index;
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw TimeoutException('event not received; got $events');
      }
      await _changed.stream.first.timeout(remaining, onTimeout: () {});
    }
  }

  Future<int> waitForState(SyncState state, {int from = 0}) => waitFor(
    (event) => event is CoreEvent_SyncStateChanged && event.state == state,
    from: from,
  );

  Future<void> waitDone() async {
    final deadline = DateTime.now().add(timeout);
    while (!done) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) throw TimeoutException('stream not closed');
      await _changed.stream.first.timeout(remaining, onTimeout: () {});
    }
  }

  /// Cancels the subscription without waiting: with flutter_rust_bridge the
  /// cancellation completes on the next event or when the API is disposed.
  void cancel() => unawaited(subscription.cancel());

  List<Message> get messages => [
    for (final event in events)
      if (event is CoreEvent_MessageReceived) event.message,
  ];
}

/// Polls `condition` until true.
Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeHomeserver server;
  late Directory dataDir;

  setUpAll(initRustForTests);

  setUp(() async {
    server = await FakeHomeserver.start();
    dataDir = await Directory.systemTemp.createTemp('messenger_bridge_test');
  });

  tearDown(() async {
    await server.close();
    await dataDir.delete(recursive: true);
  });

  Future<MessengerApi> create() => MessengerApi.create(
    homeserverUrl: server.url,
    dataDir: dataDir.path,
    secretStorage: SecretStorage.inMemory,
  );

  Future<MessengerApi> loggedIn() async {
    final api = await create();
    await api.login(username: 'alice', password: FakeHomeserver.password);
    return api;
  }

  group('initialization and session', () {
    test('creates the core without network', () async {
      final api = await create();

      expect(api.homeserver(), '${server.url}/');
      expect(api.currentUser(), isNull);
      expect(api.syncState(), SyncState.stopped);
      expect(await api.restoreSession(), RestoreOutcome.noSession);
      expect(server.requestCount, 0);
      api.dispose();
    });

    test('invalid configuration is a typed error', () async {
      await expectLater(
        MessengerApi.create(
          homeserverUrl: 'matrix.org',
          dataDir: dataDir.path,
          secretStorage: SecretStorage.inMemory,
        ),
        throwsA(isA<ApiError_InvalidHomeserver>()),
      );
    });

    test('login, errors, logout and restore after restart', () async {
      var api = await create();
      await expectLater(
        api.login(username: 'alice', password: 'wrong'),
        throwsA(isA<ApiError_InvalidCredentials>()),
      );
      await api.login(username: 'alice', password: FakeHomeserver.password);
      expect(api.currentUser(), FakeHomeserver.userId);
      await expectLater(
        api.login(username: 'alice', password: FakeHomeserver.password),
        throwsA(isA<ApiError_AlreadyAuthenticated>()),
      );

      // Same data dir, new instance: the session is restored.
      api.dispose();
      api = await create();
      expect(await api.restoreSession(), RestoreOutcome.restored);
      expect(api.currentUser(), FakeHomeserver.userId);

      expect(await api.logout(), LogoutOutcome.complete);
      expect(api.currentUser(), isNull);
      api.dispose();
    });

    test('logout without the homeserver is local only', () async {
      final api = await loggedIn();
      await server.close();

      expect(await api.logout(), LogoutOutcome.localOnly);
      api.dispose();
    });
  });

  group('rooms and messages', () {
    test('translate rooms, messages and sent messages', () async {
      server.syncScript[null] = FakeResponse(
        syncBody(
          's1',
          {roomA: [], roomB: []},
          state: {
            roomA: [
              {
                'type': 'm.room.name',
                'state_key': '',
                'event_id': r'$name',
                'sender': FakeHomeserver.userId,
                'origin_server_ts': 1,
                'content': {'name': 'Equipe'},
              },
            ],
          },
        ),
      );
      server.messagesChunk = [
        textEvent(r'$2', FakeHomeserver.userId, 2000, 'Bom dia'),
        textEvent(r'$1', '@bob:example.org', 1000, 'Olá'),
      ];
      final api = await loggedIn();

      final rooms = await api.refreshRooms();
      expect(rooms, const [
        RoomSummary(id: roomA, displayName: 'Equipe', isDirect: false),
        RoomSummary(id: roomB, displayName: 'Empty Room', isDirect: false),
      ]);
      expect(await api.cachedRooms(), rooms);

      final messages = await api.loadMessages(roomId: roomA, limit: 50);
      expect(messages, const [
        Message(
          id: r'$1',
          sender: '@bob:example.org',
          body: 'Olá',
          timestampMs: 1000,
          isOwn: false,
        ),
        Message(
          id: r'$2',
          sender: FakeHomeserver.userId,
          body: 'Bom dia',
          timestampMs: 2000,
          isOwn: true,
        ),
      ]);

      final sent = await api.sendTextMessage(roomId: roomA, body: 'Olá!');
      expect(sent, const SentMessage(eventId: r'$sent'));
      expect(server.sentMessages, [
        {'msgtype': 'm.text', 'body': 'Olá!'},
      ]);

      await expectLater(
        api.sendTextMessage(roomId: roomA, body: '  '),
        throwsA(isA<ApiError_InvalidMessage>()),
      );
      await expectLater(
        api.loadMessages(roomId: '!unknown:example.org', limit: 10),
        throwsA(isA<ApiError_RoomNotFound>()),
      );
      api.dispose();
    });

    test('unauthenticated calls fail with NotAuthenticated', () async {
      final api = await create();
      await expectLater(
        api.cachedRooms(),
        throwsA(isA<ApiError_NotAuthenticated>()),
      );
      await expectLater(
        api.startSync(),
        throwsA(isA<ApiError_NotAuthenticated>()),
      );
      api.dispose();
    });
  });

  group('realtime stream', () {
    test('Rust events reach the Dart stream', () async {
      server.syncScript[null] = FakeResponse(
        syncBody('s1', {
          roomA: [textEvent(r'$old', '@bob:example.org', 500, 'antiga')],
        }),
      );
      server.syncScript['s1'] = FakeResponse(
        syncBody('s2', {
          roomA: [textEvent(r'$new', '@bob:example.org', 5000, 'Olá')],
        }),
      );
      server.syncScript['s2'] = FakeResponse(
        syncBody('s3', {roomB: []}, limited: true),
      );
      final api = await loggedIn();
      final recorder = EventRecorder(api.events());

      await api.startSync();
      await expectLater(
        api.startSync(),
        throwsA(isA<ApiError_AlreadySyncing>()),
      );
      await recorder.waitFor((event) => event is CoreEvent_TimelineGap);

      final running = await recorder.waitForState(SyncState.running);
      expect(
        recorder.events.first,
        const CoreEvent.syncStateChanged(state: SyncState.starting),
      );
      expect(
        recorder.events.take(running),
        contains(const CoreEvent.roomsChanged()),
      );
      // History of the baseline is not reported; the new message is, once.
      expect(recorder.messages, const [
        Message(
          id: r'$new',
          sender: '@bob:example.org',
          body: 'Olá',
          timestampMs: 5000,
          isOwn: false,
        ),
      ]);
      expect(
        recorder.events,
        contains(const CoreEvent.timelineGap(roomId: roomB)),
      );
      expect(api.syncState(), SyncState.running);

      await api.stopSync();
      await recorder.waitForState(SyncState.stopped);
      expect(api.syncState(), SyncState.stopped);
      await api.stopSync(); // idempotent
      recorder.cancel();
      api.dispose();
    });

    test('cancelling the Dart subscription ends the Rust forwarder', () async {
      final api = await loggedIn();
      final recorder = EventRecorder(api.events());
      await eventually(() => api.activeEventStreams() == 1);
      await api.startSync();
      await recorder.waitForState(SyncState.running);

      // The cancellation completes once the next event reaches Dart (here:
      // sync stopped); the Dart port is closed then.
      final cancelled = recorder.subscription.cancel();
      await api.stopSync();
      await cancelled.timeout(timeout);

      // The Rust forwarder notices on the following event and ends.
      expect(api.activeEventStreams(), lessThanOrEqualTo(1));
      await api.startSync();
      await eventually(() => api.activeEventStreams() == 0);
      await api.stopSync();
      api.dispose();
    });

    test('disposing the API closes idle streams', () async {
      final api = await loggedIn();
      final recorder = EventRecorder(api.events());
      await eventually(() => api.activeEventStreams() == 1);

      api.dispose();

      await recorder.waitDone();
    });

    test(
      'lifecycle: subscribe, start, stop, dispose closes the stream',
      () async {
        final api = await loggedIn();
        final recorder = EventRecorder(api.events());

        await api.startSync();
        await recorder.waitForState(SyncState.running);
        await api.stopSync();
        await recorder.waitForState(SyncState.stopped);
        api.dispose();

        await recorder.waitDone();
      },
    );

    test('calls while syncing, then logout with an active stream', () async {
      server.syncScript[null] = FakeResponse(syncBody('s1', {roomA: []}));
      server.messagesChunk = [
        textEvent(r'$1', '@bob:example.org', 1000, 'Olá'),
      ];
      final api = await loggedIn();
      final recorder = EventRecorder(api.events());
      await api.startSync();
      await recorder.waitForState(SyncState.running);

      final results = await Future.wait([
        api.cachedRooms(),
        api.loadMessages(roomId: roomA, limit: 10),
        api.refreshRooms(),
      ]);
      expect((results[0] as List<RoomSummary>).single.id, roomA);
      expect((results[1] as List<Message>).single.body, 'Olá');

      expect(await api.logout(), LogoutOutcome.complete);
      final stopped = await recorder.waitForState(SyncState.stopped);
      expect(api.currentUser(), isNull);
      expect(api.syncState(), SyncState.stopped);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        recorder.events.length,
        stopped + 1,
        reason: 'no event after logout',
      );

      recorder.cancel();
      api.dispose();
    });

    test('revoked session reaches Dart', () async {
      server.syncScript[null] = FakeResponse(syncBody('s1', {roomA: []}));
      server.syncScript['s1'] = const FakeResponse({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'Invalid token',
      }, status: 401);
      final api = await loggedIn();
      final recorder = EventRecorder(api.events());

      await api.startSync();
      await recorder.waitFor((event) => event is CoreEvent_SessionRevoked);
      await recorder.waitForState(SyncState.stopped);
      expect(api.currentUser(), isNull);

      recorder.cancel();
      api.dispose();
    });
  });
}
