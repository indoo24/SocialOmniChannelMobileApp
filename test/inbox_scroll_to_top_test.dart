/// The floating Scroll to top button on the Inbox: hidden at the top, shown
/// once the agent is well down the list (with a gap before it hides again, so
/// it does not flicker), and a tap glides back to the first conversation
/// *without* reloading, clearing or re-requesting anything — it only moves the
/// one existing scroll position.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';

import 'support/grouped_server.dart';

final _button = find.byKey(const ValueKey('inboxScrollToTop'));

/// Moves the list to [pixels] and lets the button's fade settle.
Future<void> _scrollTo(WidgetTester tester, double pixels) async {
  listPosition(tester).jumpTo(pixels);
  await settle(tester);
}

/// Taps the button and lets the glide to the top (and the fade) finish.
Future<void> _tapToTop(WidgetTester tester) async {
  await tester.tap(_button);
  await settle(tester, 60);
}

void main() {
  group('visibility', () {
    testWidgets('is hidden when the Inbox opens', (tester) async {
      await pumpInbox(tester, GroupedServer(singleGroups(90)));

      expect(_button, findsNothing);
    });

    testWidgets('stays hidden until the list is scrolled well down', (
      tester,
    ) async {
      await pumpInbox(tester, GroupedServer(singleGroups(90)));

      await _scrollTo(tester, 300);
      expect(_button, findsNothing);
      await _scrollTo(tester, 900);
      expect(_button, findsNothing, reason: 'still inside the first screens');

      await _scrollTo(tester, 1100);
      expect(_button, findsOneWidget);
    });

    testWidgets('does not flicker near the threshold: it only goes away once '
        'the agent is back close to the top', (tester) async {
      await pumpInbox(tester, GroupedServer(singleGroups(90)));
      await _scrollTo(tester, 1500);
      expect(_button, findsOneWidget);

      // Back below where it appeared, but not near the top: it stays.
      await _scrollTo(tester, 900);
      expect(_button, findsOneWidget);
      await _scrollTo(tester, 500);
      expect(_button, findsOneWidget);

      await _scrollTo(tester, 300);
      expect(_button, findsNothing);

      // And it needs the full distance again to come back.
      await _scrollTo(tester, 900);
      expect(_button, findsNothing);
      await _scrollTo(tester, 1200);
      expect(_button, findsOneWidget);
    });
  });

  group('tapping it', () {
    testWidgets('glides to the first conversation, and the button goes away', (
      tester,
    ) async {
      await pumpInbox(tester, GroupedServer(singleGroups(90)));
      await _scrollTo(tester, 1500);
      expect(_button, findsOneWidget);

      await tester.tap(_button);
      await tester.pump(); // the animation starts on the next frame
      await tester.pump(const Duration(milliseconds: 150));
      // Animated, not a jump: part of the way there.
      final midway = listPosition(tester).pixels;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1500));

      await settle(tester, 60);
      expect(listPosition(tester).pixels, closeTo(0, 5));
      expect(_button, findsNothing);
      expect(find.text('Customer 1'), findsOneWidget);
    });

    testWidgets('works after several batches have been loaded, from far '
        'down, without reloading or clearing anything', (tester) async {
      final server = GroupedServer(singleGroups(300));
      await pumpInbox(tester, server);
      final inbox = inboxController(tester);
      for (var i = 0; i < 4; i++) {
        unawaited(inbox.loadMore());
        await settle(tester, 6);
      }
      expect(inboxState(tester).groups, hasLength(150));

      final position = listPosition(tester);
      position.jumpTo(6000); // ~80 rows down, 70 rows short of the end
      await settle(tester);
      expect(position.pixels, greaterThan(5000), reason: 'hundreds of rows in');
      expect(_button, findsOneWidget);

      final before = inboxState(tester);
      final requestsBefore = server.requests.length;

      await _tapToTop(tester);

      expect(listPosition(tester).pixels, closeTo(0, 5));
      expect(_button, findsNothing);
      final after = inboxState(tester);
      expect(after.groups, same(before.groups), reason: 'nothing reloaded');
      expect(after.groups, hasLength(150));
      expect(after.page, before.page);
      expect(after.hasMore, before.hasMore);
      expect(
        after.navigation,
        before.navigation,
        reason: 'not a reload from the top',
      );
      expect(server.requests.length, requestsBefore, reason: 'no request');
    });
  });

  group('with infinite scrolling', () {
    testWidgets('appending a batch does not send the agent to the top, and '
        'the button stays', (tester) async {
      final server = GroupedServer(singleGroups(90));
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['page'] == '2' ? release.future : null;
      await pumpInbox(tester, server);

      await _scrollTo(tester, 1500); // near the end: asks for page 2
      expect(server.pagesRequested, [1, 2]);
      expect(_button, findsOneWidget);
      final offset = listPosition(tester).pixels;

      release.complete();
      await settle(tester);

      expect(inboxState(tester).groups, hasLength(60));
      expect(listPosition(tester).pixels, closeTo(offset, 0.5));
      expect(_button, findsOneWidget);
    });

    testWidgets('tapping it while a batch is loading adds no request and loses '
        'nothing', (tester) async {
      final server = GroupedServer(singleGroups(90));
      final release = Completer<void>();
      server.gate = (uri) =>
          uri.queryParameters['page'] == '2' ? release.future : null;
      await pumpInbox(tester, server);
      await _scrollTo(tester, 1500);
      expect(inboxState(tester).isLoadingMore, isTrue);

      await _tapToTop(tester);
      expect(server.pagesRequested, [1, 2], reason: 'still the one request');

      release.complete();
      await settle(tester);

      final state = inboxState(tester);
      expect(state.groups, hasLength(60), reason: 'the batch still lands');
      expect(server.pagesRequested, [1, 2]);
      expect(
        listPosition(tester).pixels,
        closeTo(0, 5),
        reason: 'and does not pull the view away from the top',
      );
    });

    testWidgets('scrolling back up does not ask for more', (tester) async {
      final server = GroupedServer(singleGroups(90));
      await pumpInbox(tester, server);
      await _scrollTo(tester, 1500);
      await settle(tester, 6);
      final requests = server.requests.length;

      await _tapToTop(tester);

      expect(server.requests.length, requests);
    });

    testWidgets('the Retry row of a failed batch is not under the button', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(90))..failPages.add(2);
      await pumpInbox(tester, server);
      final position = listPosition(tester);
      position.jumpTo(position.maxScrollExtent - 300);
      await settle(tester);
      position.jumpTo(position.maxScrollExtent);
      await settle(tester);

      final retry = find.byKey(const ValueKey('inboxLoadMoreRetry'));
      expect(retry, findsOneWidget);
      expect(_button, findsOneWidget);
      expect(
        tester.getRect(retry).overlaps(tester.getRect(_button)),
        isFalse,
        reason: 'the floating button must not cover Retry',
      );
    });
  });

  group('after the list is replaced', () {
    // 300 groups; every third is unread.
    List<Json> unreadOnly(List<Json> all, Map<String, String> q) =>
        q['unread'] == 'true'
        ? [
            for (final g in all)
              if ((((g['conversations'] as List).first as Map)['unread_count']
                      as int) >
                  0)
                g,
          ]
        : all;

    testWidgets('a filter change hides it, and it works again on the new '
        'list', (tester) async {
      final server = GroupedServer(singleGroups(300))..filter = unreadOnly;
      await pumpInbox(tester, server);
      await _scrollTo(tester, 1500);
      expect(_button, findsOneWidget);

      screenContainer(tester)
          .read(inboxFiltersProvider.notifier)
          .selectQuickFilter(InboxQuickFilter.unread);
      await settle(tester, 30);

      expect(_button, findsNothing, reason: 'a fresh list starts at the top');
      expect(inboxState(tester).page, 1);

      await _scrollTo(tester, 1500);
      expect(_button, findsOneWidget);
      await _tapToTop(tester);
      expect(listPosition(tester).pixels, closeTo(0, 5));
      expect(_button, findsNothing);
    });

    testWidgets('a pull-to-refresh reload hides it, and it works again', (
      tester,
    ) async {
      final server = GroupedServer(singleGroups(90));
      await pumpInbox(tester, server);
      await _scrollTo(tester, 1500);
      expect(_button, findsOneWidget);

      unawaited(inboxController(tester).refresh());
      await settle(tester, 30);

      expect(_button, findsNothing);
      await _scrollTo(tester, 1500);
      expect(_button, findsOneWidget);
    });
  });

  group('accessibility, localisation and theme', () {
    testWidgets('has an English tooltip and screen-reader label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpInbox(tester, GroupedServer(singleGroups(90)));
      await _scrollTo(tester, 1500);

      expect(find.byTooltip('Scroll to top'), findsOneWidget);
      final node = tester.getSemantics(_button);
      expect('${node.label} ${node.tooltip}', contains('Scroll to top'));
      semantics.dispose();
    });

    testWidgets('has an Arabic tooltip and label, and sits at the start side '
        'of the reading direction', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpInbox(
        tester,
        GroupedServer(singleGroups(90)),
        locale: const Locale('ar'),
      );
      await _scrollTo(tester, 1500);

      expect(find.byTooltip('العودة إلى الأعلى'), findsOneWidget);
      final node = tester.getSemantics(_button);
      expect('${node.label} ${node.tooltip}', contains('العودة إلى الأعلى'));
      // RTL: the "end" corner is the left one.
      expect(tester.getCenter(_button).dx, lessThan(430 / 2));
      semantics.dispose();
    });

    testWidgets('is at the right-hand corner in English, above the bottom '
        'edge', (tester) async {
      await pumpInbox(tester, GroupedServer(singleGroups(90)));
      await _scrollTo(tester, 1500);

      final rect = tester.getRect(_button);
      expect(rect.center.dx, greaterThan(430 / 2));
      expect(rect.bottom, lessThan(800), reason: 'inside the screen');
      expect(rect.right, lessThanOrEqualTo(430 - 16 + 0.5));
      // A small button (`FloatingActionButton.small`), within the 48 px
      // minimum tap target.
      expect(tester.widget<FloatingActionButton>(_button).mini, isTrue);
      expect(tester.getSize(_button).width, lessThanOrEqualTo(48));
    });

    testWidgets('is a theme-coloured, elevated circle in dark mode too', (
      tester,
    ) async {
      await pumpInbox(
        tester,
        GroupedServer(singleGroups(90)),
        theme: AppTheme.dark,
      );
      await _scrollTo(tester, 1500);

      expect(tester.takeException(), isNull);
      final fab = tester.widget<FloatingActionButton>(_button);
      expect(fab.heroTag, isNull, reason: 'no shared hero tag');
      expect(fab.mini, isTrue);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
      // Elevation comes from the theme's floating-button defaults.
      final material = tester.widget<Material>(
        find.descendant(of: _button, matching: find.byType(Material)).first,
      );
      expect(material.elevation, greaterThan(0));
    });
  });
}
