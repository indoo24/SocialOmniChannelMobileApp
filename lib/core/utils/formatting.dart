/// Date and text formatting, matching the web client's `lib/utils.ts`.
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n_extensions.dart';

/// "just now", "12m", "3h", "Mon", "12 Mar" — the inbox's compact form.
///
/// Takes [context] so weekday/month names follow the active locale — a
/// hardcoded `DateFormat()` always renders in English regardless of what the
/// rest of the screen is showing.
String formatRelativeTime(BuildContext context, DateTime? value) {
  if (value == null) return '';

  final now = DateTime.now();
  final difference = now.difference(value);
  final locale = context.l10n.localeName;

  if (difference.inSeconds < 45) return context.l10n.timeNow;
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return DateFormat('EEE', locale).format(value);
  if (value.year == now.year) return DateFormat('d MMM', locale).format(value);
  return DateFormat('d MMM yy', locale).format(value);
}

/// Full timestamp for message bubbles and detail rows.
String formatDateTime(BuildContext context, DateTime? value) => value == null
    ? '—'
    : DateFormat('d MMM y, HH:mm', context.l10n.localeName).format(value);

String formatTime(BuildContext context, DateTime? value) => value == null
    ? ''
    : DateFormat('HH:mm', context.l10n.localeName).format(value);

/// Day separator inside a message thread.
String formatDayHeading(BuildContext context, DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final difference = today.difference(day).inDays;
  final locale = context.l10n.localeName;

  if (difference == 0) return context.l10n.dayToday;
  if (difference == 1) return context.l10n.dayYesterday;
  if (difference < 7) return DateFormat('EEEE', locale).format(value);
  return DateFormat('d MMMM y', locale).format(value);
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
