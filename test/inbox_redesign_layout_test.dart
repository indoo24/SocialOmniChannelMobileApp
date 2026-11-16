/// The redesigned inbox: what sits where, in both directions.
///
///  - Header order: Channels & accounts → quick filters → search bar → sort
///    row → list, and no search icon in the app bar.
///  - A row: unread count in red right beside the name (hidden at 0, "99+"
///    past 99); the time at the row's end with the assigned employee's avatar
///    under it — the left edge in Arabic, the right in English.
///  - The All channels dropdown drives the existing `provider` filter.
///  - Nothing overflows on a narrow phone, with long names and big counts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/theme/app_palette.dart';
import 'package:scenario_mobile/core/widgets/avatar.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';

import 'support/grouped_server.dart';

Json _assignee(int id, String name, String initials) => {
  'id': id,
  'full_name': name,
  'initials': initials,
  'availability': 'ONLINE',
};

/// A one-thread group for conversation [id].
Json _row(
  int id, {
  String name = 'Customer',
  int unread = 0,
  Json? assignedTo,
  String provider = 'WHATSAPP',
}) => groupJson('${provider}_$id', [
  {
    ...convoJson(id, name: name, unread: unread, provider: provider),
    'assigned_to': assignedTo,
  },
]);

final _sara = _assignee(9, 'Sara Noor', 'SN');
final _omar = _assignee(10, 'Omar Adel', 'OA');

Finder _inRow(int id, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('inbox-conversation-$id')),
  matching: matching,
);

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  group('header', () {
    testWidgets('filters, tabs, search and sort stack in that order, and '
        'search has left the app bar', (tester) async {
      await pumpInbox(tester, GroupedServer([_row(1)]));

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.search),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Inbox')),
        findsOneWidget,
      );
      // The filter (tune), bell and account actions are all still there.
      expect(find.byIcon(Icons.tune), findsOneWidget);

      final section = _rect(
        tester,
        find.byKey(const Key('inbox_channel_account_filters')),
      );
      final tabs = _rect(tester, find.byKey(const Key('quick_filter_all')));
      final search = _rect(tester, find.byKey(const Key('inbox_search_field')));
      final sort = _rect(tester, find.byKey(const Key('needs_reply_sort_bar')));
      final firstRow = _rect(
        tester,
        find.byKey(const ValueKey('inbox-conversation-1')),
      );
      expect(section.bottom, lessThanOrEqualTo(tabs.top));
      expect(tabs.bottom, lessThanOrEqualTo(search.top));
      expect(search.bottom, lessThanOrEqualTo(sort.top));
      expect(sort.bottom, lessThanOrEqualTo(firstRow.top));
      // Full width, less the page margins.
      expect(search.width, closeTo(430 - 2 * 16, 1));
    });

    testWidgets('the search field follows a search changed elsewhere', (
      tester,
    ) async {
      final server = GroupedServer([_row(1)]);
      await pumpInbox(tester, server);
      final c = screenContainer(tester);
      c
          .read(inboxFiltersProvider.notifier)
          .update(c.read(inboxFiltersProvider).copyWith(search: 'order'));
      await settle(tester);
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().controller!.text, 'order');
      expect(find.byKey(const Key('inbox_search_clear')), findsOneWidget);

      // Opening an employee's inbox starts it unsearched; so does the field.
      c
          .read(inboxFiltersProvider.notifier)
          .showEmployee(const InboxEmployeeFilter(id: 9, name: 'Sara Noor'));
      await settle(tester);
      expect(field().controller!.text, isEmpty);
      expect(find.byKey(const Key('inbox_search_clear')), findsNothing);
    });

    testWidgets('All channels sets the existing provider filter', (
      tester,
    ) async {
      final server = GroupedServer([_row(1)]);
      await pumpInbox(tester, server);

      await tester.tap(find.byKey(const Key('inbox_channel_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Instagram').last);
      await settle(tester);

      expect(server.listRequests.last.queryParameters['provider'], 'INSTAGRAM');
      expect(
        screenContainer(tester).read(inboxFiltersProvider).provider,
        'INSTAGRAM',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('inbox_channel_filter')),
          matching: find.text('Instagram'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('inbox_channel_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All channels').last);
      await settle(tester);
      expect(
        server.listRequests.last.queryParameters.containsKey('provider'),
        isFalse,
      );
    });
  });

  group('row', () {
    testWidgets('a red unread count sits right beside the name', (
      tester,
    ) async {
      await pumpInbox(
        tester,
        GroupedServer([_row(1, unread: 3), _row(2, unread: 0)]),
      );

      final badge = _inRow(1, find.byKey(const ValueKey('inboxRowUnread')));
      expect(badge, findsOneWidget);
      expect(_inRow(1, find.text('3')), findsOneWidget);
      final box = tester.widget<Container>(badge);
      final colors = AppColors.of(tester.element(badge));
      expect((box.decoration! as BoxDecoration).color, colors.danger);

      // Immediately after the name, on the same line.
      final name = _rect(tester, _inRow(1, find.text('Customer 1')));
      final count = _rect(tester, badge);
      expect(count.left - name.right, inInclusiveRange(0, 12));
      expect(count.center.dy, closeTo(name.center.dy, 4));

      // Read: no badge.
      expect(
        _inRow(2, find.byKey(const ValueKey('inboxRowUnread'))),
        findsNothing,
      );
    });

    testWidgets('a large count shows 99+ without breaking the row', (
      tester,
    ) async {
      await pumpInbox(
        tester,
        GroupedServer([_row(1, unread: 1250, assignedTo: _sara)]),
        size: const Size(320, 700),
      );
      expect(tester.takeException(), isNull);
      expect(_inRow(1, find.text('99+')), findsOneWidget);
    });

    for (final (locale, rtl) in [
      (const Locale('en'), false),
      (const Locale('ar'), true),
    ]) {
      testWidgets('the date and, under it, the assignee sit at the row\'s far '
          'end — ${rtl ? 'left in Arabic' : 'right in English'}', (
        tester,
      ) async {
        const width = 430.0;
        await pumpInbox(
          tester,
          GroupedServer([_row(1, assignedTo: _sara)]),
          locale: locale,
        );

        final assignee = _inRow(
          1,
          find.byKey(const ValueKey('inboxRowAssignee')),
        );
        expect(assignee, findsOneWidget);
        expect(_inRow(1, find.text('SN')), findsOneWidget);
        final avatar = _rect(tester, assignee);
        final time = _rect(
          tester,
          _inRow(1, find.byKey(const ValueKey('inboxRowTime'))),
        );
        final customer = _rect(
          tester,
          _inRow(1, find.byType(InitialsAvatar)).first,
        );

        // Under the date…
        expect(avatar.top, greaterThan(time.bottom - 1));
        // …against the row's end edge (16 px page margin), opposite the
        // customer's avatar.
        if (rtl) {
          expect(avatar.left, closeTo(16, 1));
          expect(time.left, closeTo(16, 1));
          expect(customer.right, closeTo(width - 16, 1));
        } else {
          expect(avatar.right, closeTo(width - 16, 1));
          expect(time.right, closeTo(width - 16, 1));
          expect(customer.left, closeTo(16, 1));
        }
      });
    }

    testWidgets('no avatar for an unassigned conversation, nor for a '
        'customer whose threads are held by different people', (tester) async {
      await pumpInbox(
        tester,
        GroupedServer([
          _row(1),
          groupJson('WHATSAPP_20', [
            {...convoJson(21, customerId: 20), 'assigned_to': _sara},
            {...convoJson(22, customerId: 20), 'assigned_to': _omar},
          ]),
          groupJson('WHATSAPP_30', [
            {...convoJson(31, customerId: 30), 'assigned_to': _omar},
            {...convoJson(32, customerId: 30), 'assigned_to': _omar},
          ]),
        ]),
      );

      expect(
        _inRow(1, find.byKey(const ValueKey('inboxRowAssignee'))),
        findsNothing,
      );
      Finder group(String key) => find.descendant(
        of: find.byKey(ValueKey('inbox-group-$key')),
        matching: find.byKey(const ValueKey('inboxRowAssignee')),
      );
      expect(group('WHATSAPP_20'), findsNothing);
      // One holder for every thread: shown.
      expect(group('WHATSAPP_30'), findsOneWidget);
    });

    for (final locale in [const Locale('en'), const Locale('ar')]) {
      testWidgets('a narrow phone with long names, mixed scripts and big '
          'counts does not overflow — ${locale.languageCode}', (tester) async {
        final longAssignee = _assignee(
          11,
          'Abdulrahman Mohamed Abdelaziz Elsayed Hassan',
          '',
        );
        await pumpInbox(
          tester,
          GroupedServer([
            _row(
              1,
              name: 'محمد عبد الرحمن Mohamed Abdelrahman Elsayed',
              unread: 999,
              assignedTo: longAssignee,
            ),
            _row(2, name: 'kareem', unread: 7, assignedTo: _sara),
            _row(3, name: 'backspace', provider: 'INSTAGRAM'),
          ]),
          size: const Size(320, 640),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        // Initials worked out from the name when the server sent none.
        expect(_inRow(1, find.text('AM')), findsOneWidget);
      });
    }
  });

  test('initialsOf takes up to two initials, any script', () {
    expect(initialsOf('Sara Noor'), 'SN');
    expect(initialsOf('kareem'), 'K');
    expect(initialsOf('  ahmed   ali  hassan '), 'AA');
    expect(initialsOf('محمد جادالحق'), 'مج');
    expect(initialsOf(''), '');
  });
}
