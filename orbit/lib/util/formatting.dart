import 'package:intl/intl.dart';

import '../models/models.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Label for the separator above the first message of a day.
String daySeparatorLabel(DateTime date, DateTime now) {
  final diff = _day(now).difference(_day(date)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(date);
  if (date.year == now.year) return DateFormat.MMMMd().format(date);
  return DateFormat.yMMMMd().format(date);
}

/// Short time for the inbox: time today, weekday this week, else a date.
String inboxTimeLabel(DateTime date, DateTime now) {
  final diff = _day(now).difference(_day(date)).inDays;
  if (diff == 0) return DateFormat.jm().format(date);
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.E().format(date);
  if (date.year == now.year) return DateFormat.MMMd().format(date);
  return DateFormat.yMd().format(date);
}

String presenceLabel(UserProfile profile, DateTime now) {
  if (profile.isOnlineAt(now)) return 'Online';
  final seen = profile.lastSeen;
  if (seen == null) return 'Offline';
  final ago = now.difference(seen);
  if (ago.inMinutes < 1) return 'Last seen just now';
  if (ago.inMinutes < 60) return 'Last seen ${ago.inMinutes} min ago';
  final diff = _day(now).difference(_day(seen)).inDays;
  if (diff == 0) return 'Last seen today at ${DateFormat.jm().format(seen)}';
  if (diff == 1) return 'Last seen yesterday at ${DateFormat.jm().format(seen)}';
  return 'Last seen ${DateFormat.MMMd().format(seen)}';
}

String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// One row of the chat list: either a day separator or a message.
sealed class TimelineEntry {
  const TimelineEntry();
}

class DaySeparatorEntry extends TimelineEntry {
  const DaySeparatorEntry(this.day);
  final DateTime day;
}

class MessageEntry extends TimelineEntry {
  const MessageEntry(this.message, {required this.showSender});
  final Message message;

  /// True when this message starts a run from a new sender (for group names).
  final bool showSender;
}

/// Builds rows in chronological order from messages in any order.
List<TimelineEntry> buildTimeline(List<Message> messages) {
  final sorted = [...messages]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  final entries = <TimelineEntry>[];
  DateTime? currentDay;
  String? previousSender;
  for (final m in sorted) {
    final day = _day(m.sentAt);
    if (currentDay == null || day != currentDay) {
      entries.add(DaySeparatorEntry(day));
      currentDay = day;
      previousSender = null;
    }
    final senderKey = m.senderId ?? m.senderAddress ?? m.senderName;
    final isSystem = m.kind == MessageKind.system;
    entries.add(MessageEntry(
      m,
      showSender: !isSystem && senderKey != previousSender,
    ));
    previousSender = isSystem ? null : senderKey;
  }
  return entries;
}
