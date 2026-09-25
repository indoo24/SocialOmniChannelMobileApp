/// `JsonSafe.asString`/`asStringOrNull` must hand back a well-formed UTF-16
/// string, or Flutter's text layout throws `ArgumentError: string is not
/// well-formed UTF-16` the moment something tries to render it — a red-screen
/// crash triggered by data Scenario does not control (a customer's display
/// name or message text, arriving from a WhatsApp/Instagram/Facebook payload
/// with a truncated emoji or other corrupted surrogate pair). This is what
/// silently cut an inbox list short: the badge counted every conversation
/// correctly, the server returned every row correctly, and one row's
/// malformed text crashed the list mid-render, leaving only the rows drawn
/// before it on screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/utils/json_safe.dart';

void main() {
  group('JsonSafe.asString — well-formed UTF-16', () {
    test('passes ordinary strings through unchanged', () {
      expect(JsonSafe.asString('Mohamed Gad'), 'Mohamed Gad');
      expect(JsonSafe.asString(''), '');
    });

    test('passes valid surrogate pairs (real emoji) through unchanged', () {
      const withEmoji = 'Hello 😀 there';
      expect(JsonSafe.asString(withEmoji), withEmoji);
      // Confirms the fixture itself really does contain a surrogate pair,
      // so this test is exercising the pair-preservation path.
      expect(
        withEmoji.codeUnits.any((u) => u >= 0xD800 && u <= 0xDBFF),
        isTrue,
      );
    });

    test('replaces a lone leading (high) surrogate with U+FFFD', () {
      // A truncated emoji: only the first half of the pair survived.
      final malformed = '${String.fromCharCode(0xD83D)}x';
      final result = JsonSafe.asString(malformed);
      expect(result, '�x');
      expect(() => result.codeUnits, returnsNormally);
    });

    test('replaces a lone trailing (low) surrogate with U+FFFD', () {
      final malformed = 'x${String.fromCharCode(0xDE00)}';
      final result = JsonSafe.asString(malformed);
      expect(result, 'x�');
    });

    test('replaces a high surrogate at the very end of the string', () {
      final malformed = 'name${String.fromCharCode(0xD800)}';
      final result = JsonSafe.asString(malformed);
      expect(result, 'name�');
    });

    test('replaces multiple lone surrogates independently', () {
      final malformed =
          '${String.fromCharCode(0xD800)}ok${String.fromCharCode(0xDFFF)}end';
      final result = JsonSafe.asString(malformed);
      expect(result, '�ok�end');
    });

    test(
      'a real message with an embedded truncated surrogate stays renderable',
      () {
        final malformed =
            'Order #4521 confirmed ${String.fromCharCode(0xD83C)}';
        final result = JsonSafe.asString(malformed);
        expect(result.startsWith('Order #4521 confirmed'), isTrue);
        expect(result, isNot(contains('\uD83C')));
      },
    );

    test('honors fallback for a non-string value, not the sanitizer', () {
      expect(JsonSafe.asString(null, fallback: 'default'), 'default');
      expect(JsonSafe.asString(42), '42');
    });
  });

  group('JsonSafe.asStringOrNull — well-formed UTF-16', () {
    test('sanitizes a lone surrogate the same way as asString', () {
      final malformed = '${String.fromCharCode(0xDC00)}y';
      expect(JsonSafe.asStringOrNull(malformed), '�y');
    });

    test('stays null for a non-string, not the empty fallback', () {
      expect(JsonSafe.asStringOrNull(null), isNull);
    });

    test('passes a clean string through unchanged', () {
      expect(JsonSafe.asStringOrNull('clean'), 'clean');
    });
  });
}
