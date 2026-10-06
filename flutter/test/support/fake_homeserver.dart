// A minimal local Matrix homeserver for bridge tests (no internet).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Scripted answer of the fake server.
class FakeResponse {
  const FakeResponse(
    this.body, {
    this.status = 200,
    this.delay = Duration.zero,
  });

  final Object body;
  final int status;
  final Duration delay;
}

/// Answers the Matrix endpoints used by messenger_core. `/sync` answers are
/// scripted by `since` token (`null` for the first sync); unscripted syncs
/// behave like an idle server.
class FakeHomeserver {
  FakeHomeserver._(this._server) {
    _server.listen(_handle);
  }

  static const userId = '@alice:example.org';
  static const password = 'secret';

  final HttpServer _server;
  final Map<String?, FakeResponse> syncScript = {};
  final List<Map<String, dynamic>> sentMessages = [];
  List<Map<String, dynamic>> messagesChunk = [];
  int requestCount = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<FakeHomeserver> start() async =>
      FakeHomeserver._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requestCount++;
    final path = request.uri.path;
    final body = await utf8.decoder.bind(request).join();
    FakeResponse response;

    if (path == '/_matrix/client/versions') {
      response = const FakeResponse({
        'versions': ['v1.11'],
      });
    } else if (path == '/_matrix/client/v3/login') {
      final json = jsonDecode(body) as Map<String, dynamic>;
      response = json['password'] == password
          ? const FakeResponse({
              'user_id': userId,
              'access_token': 'fake-token',
              'device_id': 'FAKEDEVICE',
            })
          : const FakeResponse({
              'errcode': 'M_FORBIDDEN',
              'error': 'Invalid password',
            }, status: 403);
    } else if (path == '/_matrix/client/v3/logout') {
      response = const FakeResponse({});
    } else if (path == '/_matrix/client/v3/sync') {
      final since = request.uri.queryParameters['since'];
      response =
          syncScript[since] ??
          FakeResponse({
            'next_batch': since ?? 's0',
          }, delay: const Duration(milliseconds: 100));
    } else if (path.endsWith('/messages')) {
      response = FakeResponse({'start': 't1', 'chunk': messagesChunk});
    } else if (path.contains('/send/m.room.message/')) {
      sentMessages.add(jsonDecode(body) as Map<String, dynamic>);
      response = const FakeResponse({r'event_id': r'$sent'});
    } else {
      // Includes the encryption state lookup before sending: not encrypted.
      response = const FakeResponse({
        'errcode': 'M_NOT_FOUND',
        'error': 'Not found',
      }, status: 404);
    }

    await Future<void>.delayed(response.delay);
    request.response
      ..statusCode = response.status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(response.body));
    await request.response.close();
  }
}

/// A text `m.room.message` event.
Map<String, dynamic> textEvent(String id, String sender, int ts, String body) =>
    {
      'type': 'm.room.message',
      'event_id': id,
      'sender': sender,
      'origin_server_ts': ts,
      'content': {'msgtype': 'm.text', 'body': body},
    };

/// A `/sync` response body; `joined` maps room IDs to timeline events.
Map<String, dynamic> syncBody(
  String nextBatch,
  Map<String, List<Map<String, dynamic>>> joined, {
  Map<String, List<Map<String, dynamic>>> state = const {},
  bool limited = false,
}) => {
  'next_batch': nextBatch,
  'rooms': {
    'join': {
      for (final entry in joined.entries)
        entry.key: {
          'state': {'events': state[entry.key] ?? []},
          'timeline': {'events': entry.value, 'limited': limited},
        },
    },
  },
};
