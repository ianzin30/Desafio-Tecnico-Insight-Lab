// Application layer: startup, authentication and stream lifecycle.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/messenger_core.dart';

import '../support/app_harness.dart';
import '../support/fake_homeserver.dart';
import '../support/rust_lib.dart';

const roomA = '!a:example.org';

void main() {
  late FakeHomeserver server;
  late Directory dataDir;
  late AppHarness harness;

  setUpAll(initRustForTests);

  setUp(() async {
    server = await FakeHomeserver.start();
    dataDir = await Directory.systemTemp.createTemp('messenger_app_test');
    harness = AppHarness(server, dataDir);
    server.syncScript[null] = FakeResponse(syncBody('s1', {roomA: []}));
  });

  tearDown(() async {
    harness.stop();
    await server.close();
    await dataDir.delete(recursive: true);
  });

  test('startup without a session is unauthenticated', () async {
    await harness.start();

    expect(harness.state.phase, AppPhase.unauthenticated);
    expect(harness.state.auth.notice, isNull);
    expect(harness.state.connection, ConnectionStatus.offline);
  });

  test(
    'startup with a session restores it, shows cached rooms, syncs',
    () async {
      await harness.start();
      await harness.login();
      harness.stop();

      await harness.start();

      expect(harness.state.phase, AppPhase.authenticated);
      expect(harness.state.auth.userId, FakeHomeserver.userId);
      // Rooms come from the local store, before any new sync result.
      expect(harness.state.rooms.rooms.map((room) => room.id), [roomA]);
      await harness.until(
        (state) => state.connection == ConnectionStatus.online,
      );
    },
  );

  test('an unusable stored session leads to login with a notice', () async {
    await harness.start();
    await harness.login();
    harness.stop();
    File('${harness.engineDir}/session.json').writeAsStringSync('{ corrupted');

    await harness.start();

    expect(harness.state.phase, AppPhase.unauthenticated);
    expect(harness.state.auth.notice, AuthNotice.sessionExpired);
  });

  test('an engine that cannot start is a fatal error', () async {
    await harness.store.write(server.url);
    // The engine's data directory cannot be created.
    File(harness.engineDir).writeAsStringSync('not a directory');

    await harness.start();

    expect(harness.state.phase, AppPhase.fatalError);
    expect(harness.state.fatalError?.cause, isA<ApiError_Storage>());
  });

  test('login opens the session and starts the sync', () async {
    await harness.start();

    await harness.login();

    expect(harness.state.phase, AppPhase.authenticated);
    expect(harness.state.auth.userId, FakeHomeserver.userId);
    expect(harness.state.auth.submitting, isFalse);
    expect(harness.state.rooms.rooms.map((room) => room.id), [roomA]);
    expect(harness.state.connection, ConnectionStatus.online);
  });

  test('invalid credentials keep the app unauthenticated', () async {
    await harness.start();

    await harness.app.login(
      homeserver: server.url,
      username: 'alice',
      password: 'wrong',
    );

    expect(harness.state.phase, AppPhase.unauthenticated);
    expect(harness.state.auth.failure, AuthFailure.invalidCredentials);
    expect(harness.state.auth.submitting, isFalse);
    harness.app.dismissAuthMessage();
    expect(harness.state.auth.failure, isNull);
  });

  test('logout stops the sync and clears the session state', () async {
    await harness.start();
    await harness.login();
    await harness.app.selectRoom(roomA);

    await harness.app.logout();

    final state = harness.state;
    expect(state.phase, AppPhase.unauthenticated);
    expect(state.auth.notice, isNull);
    expect(state.rooms.rooms, isEmpty);
    expect(state.conversation, isNull);
    expect(state.connection, ConnectionStatus.offline);
  });

  test('a local-only logout still leaves the session', () async {
    await harness.start();
    await harness.login();
    await server.close();

    await harness.app.logout();

    expect(harness.state.phase, AppPhase.unauthenticated);
    expect(harness.state.auth.notice, AuthNotice.loggedOutLocallyOnly);
  });

  test('a revoked session returns to login automatically', () async {
    server.syncScript['s1'] = const FakeResponse({
      'errcode': 'M_UNKNOWN_TOKEN',
      'error': 'Invalid token',
    }, status: 401);
    await harness.start();
    await harness.app.login(
      homeserver: server.url,
      username: 'alice',
      password: FakeHomeserver.password,
    );

    await harness.until((state) => state.phase == AppPhase.unauthenticated);

    final state = harness.state;
    expect(state.auth.notice, AuthNotice.sessionExpired);
    expect(state.rooms.rooms, isEmpty);
    expect(state.conversation, isNull);
  });

  test('one engine and one event stream across sessions', () async {
    await harness.start();
    expect(harness.gateways, isEmpty, reason: 'no engine before a login');

    await harness.login();
    final gateway = harness.gateways.single;
    expect(gateway.activeEventStreams(), 1);

    await harness.app.logout();
    await harness.login();
    await harness.app.logout();

    // Same homeserver: the engine and its subscription are reused.
    expect(harness.gateways, hasLength(1));
    expect(gateway.activeEventStreams(), 1);

    // Quitting disposes the engine, which closes the stream: no hang.
    harness.stop();
    expect(gateway.isDisposed, isTrue);
  });
}
