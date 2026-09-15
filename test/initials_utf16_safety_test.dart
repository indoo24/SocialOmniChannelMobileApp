/// Regression: a display name that starts with an emoji (or any other
/// multi-code-unit character) must never produce a lone/unpaired UTF-16
/// surrogate when reduced to "initials" — half of a surrogate pair is a
/// malformed string that crashes `TextPainter` with "Invalid argument(s):
/// string is not well-formed UTF-16" the moment it is rendered.
///
/// The bug: `name[0]` (raw UTF-16 code-unit indexing) instead of
/// `name.characters.first` (grapheme-cluster-safe) in three places that
/// derive initials from a customer/conversation display name, plus a
/// well-formedness guard in `InitialsAvatar` itself, which every avatar in
/// the app renders through — but that guard must never *truncate* an
/// already-well-formed string, since some callers legitimately pass a
/// multi-character label (`Employee.initials`, e.g. `"JD"`), not a single
/// glyph.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/widgets/avatar.dart';

/// U+1F44B (👋) as a Dart string literal — a genuine UTF-16 surrogate pair,
/// not a single code unit. `'👋'[0]` takes only its high surrogate
/// (`\uD83D`), which is exactly the malformed, unpaired half that crashes
/// the painting library.
const _wavingHand = '👋';

void main() {
  group('CustomerBrief.initials', () {
    test('an emoji-led display name keeps the whole emoji, not half of it', () {
      final customer = CustomerBrief(id: 1, displayName: '$_wavingHand Indoo');

      // The whole emoji survives (a correctly-paired surrogate, two code
      // units), followed by "Indoo"'s own initial — not half of the emoji
      // the way `name[0]` used to produce.
      expect(customer.initials, '${_wavingHand.toUpperCase()}I');
    });

    test('a plain ASCII name is unaffected', () {
      final customer = CustomerBrief(id: 1, displayName: 'Yousef Kandeel');
      expect(customer.initials, 'YK');
    });
  });

  group('InitialsAvatar', () {
    testWidgets('renders an emoji-led name without a UTF-16 painting error', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InitialsAvatar(initials: '$_wavingHand Indoo')),
        ),
      );
      await tester.pumpAndSettle();

      // `TestWidgetsFlutterBinding` records a paint-time exception here
      // rather than letting it escape — `takeException()` is the
      // idiomatic way to assert none was thrown.
      expect(tester.takeException(), isNull);
      expect(find.textContaining(_wavingHand), findsOneWidget);
    });

    testWidgets('a lone surrogate passed in directly is never painted raw', (
      tester,
    ) async {
      // The exact malformed half `name[0]` used to produce: only the high
      // surrogate of 👋, with no low surrogate to pair it with.
      const loneSurrogate = '\uD83D';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InitialsAvatar(initials: loneSurrogate)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a well-formed multi-character label like "JD" renders in full, not truncated',
      (tester) async {
        // Regression: the fix for the malformed-UTF-16 crash must not
        // itself start truncating `InitialsAvatar`'s input — callers like
        // the employee directory pass a server-computed two-letter label
        // (`Employee.initials`), not a single glyph, and an over-eager
        // "just render the first grapheme" guard would silently cut "JD"
        // down to "J".
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: InitialsAvatar(initials: 'JD')),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('JD'), findsOneWidget);
      },
    );
  });
}
