/// Opening the phone's own dialer with a customer's number filled in.
///
/// The app never places a call itself: it hands a `tel:` link to the platform,
/// whose dialer shows the number and waits for the agent to press Call. That is
/// why no calling permission is needed on either platform.
///
/// The number is customer data, and the customer can influence it, so it is
/// not passed on as it came. [dialableNumber] accepts only what is a phone
/// number — digits with an optional leading `+` — after removing the
/// separators people and exports put in them. It refuses everything else
/// (letters, `*` and `#`, which a dialer treats as USSD and supplementary
/// service codes, `;` and `,`, which add dial extensions), so what reaches the
/// platform can only dial a number.
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_log.dart';

/// What came of asking for the dialer.
enum DialOutcome {
  /// The dialer was opened with the number.
  opened,

  /// There was no number to dial.
  noNumber,

  /// There was text, but it is not a phone number.
  invalidNumber,

  /// This device has no phone app to open, or it could not be opened.
  unavailable,
}

/// Shortest and longest a dialable number can be: ITU E.164 allows at most 15
/// digits including the country code, and nothing real is shorter than a
/// handful.
const _minDigits = 6;
const _maxDigits = 15;

/// Spaces (including the no-break kind), dashes, dots, brackets, and the
/// invisible direction marks a number picks up when it is copied out of
/// right-to-left text.
final _separators = RegExp(
  r'[\s\-.()\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  unicode: true,
);

final _dialable = RegExp('^\\+?[0-9]{$_minDigits,$_maxDigits}\$');

/// [raw] as a dialer takes it — digits, with a leading `+` kept — or null when
/// it is not a phone number.
///
/// A leading `+` is the country code's marker and is never dropped: `+20 101
/// 234 5678` becomes `+201012345678`, not `201012345678`. A `+` anywhere
/// else, or any other character, makes it invalid. Arabic-Indic digits (٠-٩,
/// ۰-۹) are read as the digits they are. Nothing is added: a number stored
/// without its country code is dialed as stored.
String? dialableNumber(String? raw) {
  if (raw == null) return null;
  final cleaned = _asciiDigits(raw.replaceAll(_separators, ''));
  return _dialable.hasMatch(cleaned) ? cleaned : null;
}

/// The `tel:` link for [raw], or null when it is not a dialable number.
Uri? telUri(String? raw) {
  final number = dialableNumber(raw);
  return number == null ? null : Uri(scheme: 'tel', path: number);
}

String _asciiDigits(String s) {
  final out = StringBuffer();
  for (final unit in s.runes) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      out.writeCharCode(0x30 + unit - 0x0660);
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      out.writeCharCode(0x30 + unit - 0x06F0);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Hands a `tel:` link to the platform. Replaceable in tests.
@visibleForTesting
Future<bool> Function(Uri uri) launchDialer = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens the dialer on [raw]. Never throws, and never logs the number: a
/// refusal, a device with no phone app, or a platform error is reported as
/// an outcome, for the caller to say in words.
Future<DialOutcome> dialNumber(String? raw) async {
  if (raw == null || raw.trim().isEmpty) return DialOutcome.noNumber;
  final uri = telUri(raw);
  if (uri == null) return DialOutcome.invalidNumber;
  try {
    final opened = await launchDialer(uri);
    if (!opened) AppLog.debug('PhoneDialer', 'no phone app to open the dialer');
    return opened ? DialOutcome.opened : DialOutcome.unavailable;
  } catch (error) {
    AppLog.debug(
      'PhoneDialer',
      'opening the dialer failed: ${error.runtimeType}',
    );
    return DialOutcome.unavailable;
  }
}
