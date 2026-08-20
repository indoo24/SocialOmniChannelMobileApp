/// `ForegroundPushBanner` — the presentational widget behind Group 8's
/// foreground push banner.
///
/// `PushBridge`'s own wiring (`_handleForegroundPush`) runs off the real
/// `FirebaseMessaging.onMessage` stream, which nothing in this codebase
/// fakes or injects, so it isn't reachable from a test. This widget is the
/// part of the feature that can actually be pumped and exercised directly —
/// it was made public (unlike the rest of `push_bridge.dart`'s private
/// helpers) specifically so this test could do that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/notifications/push_bridge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Align(child: child)),
  );

  testWidgets('renders the title and body', (tester) async {
    await tester.pumpWidget(
      wrap(
        ForegroundPushBanner(
          title: 'New message',
          body: 'A customer just replied.',
          onTap: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.text('New message'), findsOneWidget);
    expect(find.text('A customer just replied.'), findsOneWidget);
  });

  testWidgets('omits the body line when body is empty', (tester) async {
    await tester.pumpWidget(
      wrap(
        ForegroundPushBanner(
          title: 'New message',
          body: '',
          onTap: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.text('New message'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets('tapping the banner calls onTap, not onDismiss', (tester) async {
    var tapped = false;
    var dismissed = false;

    await tester.pumpWidget(
      wrap(
        ForegroundPushBanner(
          title: 'New message',
          body: 'A customer just replied.',
          onTap: () => tapped = true,
          onDismiss: () => dismissed = true,
        ),
      ),
    );

    await tester.tap(find.text('New message'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(dismissed, isFalse);
  });

  testWidgets('tapping the close button calls onDismiss, not onTap', (
    tester,
  ) async {
    var tapped = false;
    var dismissed = false;

    await tester.pumpWidget(
      wrap(
        ForegroundPushBanner(
          title: 'New message',
          body: 'A customer just replied.',
          onTap: () => tapped = true,
          onDismiss: () => dismissed = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissed, isTrue);
    expect(tapped, isFalse);
  });

  testWidgets('long title and body are truncated, not overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 300,
          child: ForegroundPushBanner(
            title: 'A' * 200,
            body: 'B' * 200,
            onTap: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    // No overflow exception is the assertion here — pump() would surface a
    // FlutterError from RenderFlex overflow if maxLines/ellipsis weren't
    // wired correctly.
    expect(tester.takeException(), isNull);
  });
}
