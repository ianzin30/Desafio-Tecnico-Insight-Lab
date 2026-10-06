import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/messenger_core.dart';
import 'package:messenger_app/ui/format.dart';

Message msg(String id, String sender, DateTime time, {bool own = false}) =>
    Message(
      id: id,
      sender: sender,
      body: id,
      timestampMs: time.millisecondsSinceEpoch,
      isOwn: own,
    );

void main() {
  final now = DateTime(2026, 10, 6, 15);

  test('day labels', () {
    expect(dayLabel(DateTime(2026, 10, 6, 1), now), 'Hoje');
    expect(dayLabel(DateTime(2026, 10, 5, 23, 59), now), 'Ontem');
    expect(dayLabel(DateTime(2026, 9, 12), now), '12 de set.');
    expect(dayLabel(DateTime(2025, 12, 31), now), '31 de dez. 2025');
    expect(timeLabel(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });

  test('messages are grouped by sender within 5 minutes and by day', () {
    const bob = '@bob:example.org';
    final items = buildTimeline([
      msg(r'$1', bob, DateTime(2026, 10, 5, 18, 2)),
      msg(r'$2', bob, DateTime(2026, 10, 6, 9, 14)),
      msg(r'$3', bob, DateTime(2026, 10, 6, 9, 18)),
      msg(r'$4', bob, DateTime(2026, 10, 6, 9, 30)),
      msg(r'$5', '@me:x', DateTime(2026, 10, 6, 9, 31), own: true),
    ], now);

    String describe(TimelineItem item) => switch (item) {
      DaySeparator(:final label) => label,
      MessageGroup(:final messages, :final isOwn) =>
        '${isOwn ? 'own' : 'other'}:${messages.map((m) => m.id).join(',')}',
    };
    expect(items.map(describe), [
      'Ontem',
      r'other:$1',
      'Hoje',
      r'other:$2,$3',
      r'other:$4',
      r'own:$5',
    ]);
  });

  test('homeserver URL from the server field and back', () {
    expect(homeserverUrlFromInput(' matrix.org '), 'https://matrix.org');
    expect(
      homeserverUrlFromInput('http://127.0.0.1:8008'),
      'http://127.0.0.1:8008',
    );
    expect(homeserverInputFromUrl('https://matrix.org/'), 'matrix.org');
    expect(
      homeserverInputFromUrl('http://localhost:8008'),
      'http://localhost:8008',
    );
    expect(homeserverInputFromUrl(null), '');
    expect(isMatrixId('@carla:example.org'), isTrue);
    expect(isMatrixId('Equipe Backend'), isFalse);
  });
}
