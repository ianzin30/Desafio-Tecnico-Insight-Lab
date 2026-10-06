// Presentation helpers for the timeline: day labels, times and grouping.
import '../messenger_core.dart';

const _months = [
  'jan.',
  'fev.',
  'mar.',
  'abr.',
  'mai.',
  'jun.',
  'jul.',
  'ago.',
  'set.',
  'out.',
  'nov.',
  'dez.',
];

/// "Hoje", "Ontem" or "12 de set." (with the year when not the current one).
String dayLabel(DateTime day, DateTime now) {
  final date = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Ontem';
  final label = '${date.day} de ${_months[date.month - 1]}';
  return date.year == now.year ? label : '$label ${date.year}';
}

String timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

DateTime messageTime(Message message) =>
    DateTime.fromMillisecondsSinceEpoch(message.timestampMs);

/// A row of the timeline: a day separator or a group of messages.
sealed class TimelineItem {
  const TimelineItem();
}

class DaySeparator extends TimelineItem {
  const DaySeparator(this.label);
  final String label;
}

/// Consecutive messages of one sender, at most [groupWindow] apart.
class MessageGroup extends TimelineItem {
  MessageGroup({required this.sender, required this.isOwn});
  final String sender;
  final bool isOwn;
  final messages = <Message>[];
}

const groupWindow = Duration(minutes: 5);

/// Builds the timeline rows of [messages] (oldest first).
List<TimelineItem> buildTimeline(List<Message> messages, DateTime now) {
  final items = <TimelineItem>[];
  String? lastDay;
  MessageGroup? group;
  DateTime? groupLast;
  for (final message in messages) {
    final time = messageTime(message);
    final day = dayLabel(time, now);
    if (day != lastDay) {
      items.add(DaySeparator(day));
      lastDay = day;
      group = null;
    }
    final sameGroup =
        group != null &&
        group.sender == message.sender &&
        time.difference(groupLast!) <= groupWindow;
    if (!sameGroup) {
      group = MessageGroup(sender: message.sender, isOwn: message.isOwn);
      items.add(group);
    }
    group.messages.add(message);
    groupLast = time;
  }
  return items;
}

/// Whether a room name is a Matrix identifier (shown in mono).
bool isMatrixId(String name) => name.startsWith('@') || name.startsWith('!');

/// The homeserver URL from what the user typed after the fixed `https://`.
/// An explicit `http://` or `https://` is kept (e.g. a local server).
String homeserverUrlFromInput(String input) {
  final value = input.trim();
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  return 'https://$value';
}

/// What the server field shows for a stored homeserver URL.
String homeserverInputFromUrl(String? url) {
  if (url == null) return '';
  var value = url.trim();
  if (value.startsWith('https://')) value = value.substring(8);
  if (value.endsWith('/')) value = value.substring(0, value.length - 1);
  return value;
}
