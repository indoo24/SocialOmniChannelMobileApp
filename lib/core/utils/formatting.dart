/// Date and text formatting, matching the web client's `lib/utils.ts`.
library;

import 'package:intl/intl.dart';

/// "just now", "12m", "3h", "Mon", "12 Mar" — the inbox's compact form.
String formatRelativeTime(DateTime? value) {
  if (value == null) return '';

  final now = DateTime.now();
  final difference = now.difference(value);

  if (difference.inSeconds < 45) return 'now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return DateFormat('EEE').format(value);
  if (value.year == now.year) return DateFormat('d MMM').format(value);
  return DateFormat('d MMM yy').format(value);
}

/// Full timestamp for message bubbles and detail rows.
String formatDateTime(DateTime? value) =>
    value == null ? '—' : DateFormat('d MMM y, HH:mm').format(value);

String formatTime(DateTime? value) =>
    value == null ? '' : DateFormat('HH:mm').format(value);

/// Day separator inside a message thread.
String formatDayHeading(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (difference < 7) return DateFormat('EEEE').format(value);
  return DateFormat('d MMMM y').format(value);
}

/// Sentence-cases a backend enum for display: `WAITING_CUSTOMER` → `Waiting customer`.
String humanizeEnum(String value) {
  if (value.isEmpty) return value;
  final words = value.toLowerCase().split('_');
  return words
      .asMap()
      .entries
      .map((e) => e.key == 0
          ? '${e.value[0].toUpperCase()}${e.value.substring(1)}'
          : e.value)
      .join(' ');
}
