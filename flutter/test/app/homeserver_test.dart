// Application layer: the homeserver chosen at login and the engine lifecycle.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';

import '../support/app_harness.dart';
import '../support/fake_homeserver.dart';
import '../support/rust_lib.dart';

const roomA = '!a:example.org';

void main() {
  late FakeHomeserver serverA;
  late FakeHomeserver serverB;
  late Directory dataDir;
  late AppHarness harness;

  setUpAll(initRustForTests);

  setUp(() async {
    serverA = await FakeHomeserver.start();
    serverB = await FakeHomeserver.start();
    for (final server in [serverA, serverB]) {
      server.syncScript[null] = FakeResponse(syncBody('s1', {roomA: []}));
    }
    dataDir = await Directory.systemTemp.createTemp('messenger_app_test');
    harness = AppHarness(serverA, dataDir);
  });

  tearDown(() async {
    harness.stop();
    await serverA.close();
    await serverB.close();
    await dataDir.delete(recursive: true);
  });

  test('first startup waits for a homeserver from the login', () async {
    await harness.start();

    expect(harness.state.phase, AppPhase.unauthenticated);
    expect(harness.state.homeserver, isNull);
    expect(harness.gateways, isEmpty);
  });

  test('a successful login remembers its homeserver', () async {
    await harness.start();

    await harness.login(to: serverA);

    expect(await harness.store.read(), serverA.url);
    expect(harness.state.homeserver, serverA.url);
  });

  test('the next startup restores with the remembered homeserver', () async {
    await harness.start();
    await harness.login(to: serverA);
    harness.stop();

    await harness.start();

    expect(harness.gatewayHomeservers, [serverA.url, serverA.url]);
    expect(harness.state.phase, AppPhase.authenticated);
    expect(harness.state.homeserver, serverA.url);
  });

  test('logging in to another homeserver replaces the engine', () async {
    await harness.start();
    await harness.login(to: serverA);
    await harness.app.logout();

    await harness.login(to: serverB);

    expect(harness.gatewayHomeservers, [serverA.url, serverB.url]);
    expect(harness.gateways.first.isDisposed, isTrue);
    expect(harness.gateways.last.activeEventStreams(), 1);
    expect(harness.state.phase, AppPhase.authenticated);
    expect(harness.state.homeserver, serverB.url);
    expect(await harness.store.read(), serverB.url);
  });

  test('no engine leaks: invalid homeserver, switch while logged in', () async {
    await harness.start();
    await harness.login(to: serverA);

    // Logged in: another homeserver is not accepted silently.
    await harness.app.login(
      homeserver: serverB.url,
      username: 'alice',
      password: FakeHomeserver.password,
    );
    expect(harness.gateways, hasLength(1));
    expect(harness.state.homeserver, serverA.url);

    await harness.app.logout();
    await harness.app.login(
      homeserver: 'not a url',
      username: 'alice',
      password: FakeHomeserver.password,
    );
    expect(harness.state.phase, AppPhase.unauthenticated);
    expect(harness.state.auth.failure, AuthFailure.invalidHomeserver);
    // The previous engine was released; no new one exists.
    expect(harness.gateways, hasLength(1));
    expect(harness.gateways.single.isDisposed, isTrue);
    expect(await harness.store.read(), serverA.url);

    await harness.login(to: serverA);
    expect(harness.gateways, hasLength(2));
    expect(harness.gateways.last.activeEventStreams(), 1);
    expect(harness.state.phase, AppPhase.authenticated);
  });
}
