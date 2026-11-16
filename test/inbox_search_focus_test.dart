/// The inbox search field's focus and keyboard.
///
/// The keyboard opens only when the agent taps the field. It goes away on
/// the Search key, on a tap elsewhere, on scrolling the results and before a
/// conversation opens — and coming back to the inbox (from a conversation, a
/// sheet, or another section) never brings it back, while the query and its
/// results stay as they were.
///
/// The bug these pin: a route popped off the inbox refocuses whatever its
/// focus scope last remembered, and the field was left remembered (its
/// scope was unfocused, not the field), so every return reopened the
/// keyboard.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_server.dart';

const _debounce = Duration(milliseconds: 450);

/// A server that narrows by `search` on the customer's name, as the real one
/// applies the query before it paginates.
GroupedServer _server([int n = 12]) => GroupedServer(singleGroups(n))
  ..filter = (all, query) {
    final term = (query['search'] ?? '').toLowerCase();
    if (term.isEmpty) return all;
    return [
      for (final g in all)
        if (((g['customer'] as Json)['display_name'] as String).toLowerCase() ==
            term)
          g,
    ];
  };

/// The real inbox under a `GoRouter` laid out like the app's: `/inbox`, a
/// stand-in conversation page at `/inbox/:id`, and another section.
Future<GoRouter> _pumpApp(WidgetTester tester, GroupedServer server) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(tester.view.reset);

  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  final router = GoRouter(
    initialLocation: '/inbox',
    routes: [
      GoRoute(
        path: '/inbox',
        builder: (_, _) => const InboxScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => Scaffold(
              appBar: AppBar(
                title: Text('Conversation ${state.pathParameters['id']}'),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/other',
        builder: (_, _) => const Scaffold(body: Text('Another section')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWith((ref) => testEmployee),
        channelsProvider.overrideWith((ref) async => const [testChannel5]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await settle(tester, 30);
  return router;
}

/// Found offstage too: its focus matters while a route covers the inbox.
Finder get _field =>
    find.byKey(const Key('inbox_search_field'), skipOffstage: false);

TextField _textField(WidgetTester tester) => tester.widget<TextField>(_field);

bool _focused(WidgetTester tester) => _textField(tester).focusNode!.hasFocus;

bool _keyboard(WidgetTester tester) => tester.testTextInput.isVisible;

/// Neither focused nor showing the keyboard.
void _expectAtRest(WidgetTester tester) {
  expect(_focused(tester), isFalse, reason: 'search field focused');
  expect(_keyboard(tester), isFalse, reason: 'keyboard showing');
}

Future<void> _tapField(WidgetTester tester) async {
  await tester.tap(_field);
  await tester.pump();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(_field, query);
  await tester.pump(_debounce);
  await settle(tester);
}

Finder _row(int id) => find.byKey(ValueKey('inbox-conversation-$id'));

List<String?> _searches(GroupedServer server) => [
  for (final u in server.listRequests) u.queryParameters['search'],
];

void main() {
  testWidgets('1–4. at rest on arrival; a tap opens the keyboard; typing '
      'searches as before; the Search key sends and puts it away', (
    tester,
  ) async {
    final server = _server();
    await _pumpApp(tester, server);
    expect(_textField(tester).autofocus, isFalse);
    _expectAtRest(tester);

    await _tapField(tester);
    expect(_focused(tester), isTrue);
    expect(_keyboard(tester), isTrue);

    // Typing: debounced, one request, results in — keyboard still up while
    // the agent is typing.
    await _search(tester, 'customer 3');
    expect(_searches(server).last, 'customer 3');
    expect(_row(3), findsOneWidget);
    expect(_row(1), findsNothing);
    expect(_focused(tester), isTrue);

    // The Search key: sent at once, keyboard away, query and results kept.
    await tester.enterText(_field, 'customer 4');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    _expectAtRest(tester);
    expect(_searches(server).last, 'customer 4');
    expect(_textField(tester).controller!.text, 'customer 4');
    expect(_row(4), findsOneWidget);
    // The pause after the Search key sends nothing twice.
    final sent = server.listRequests.length;
    await tester.pump(_debounce * 2);
    await settle(tester);
    expect(server.listRequests.length, sent);
  });

  testWidgets('5–6. tapping a conversation puts the keyboard away before it '
      'opens, and coming back does not bring it back', (tester) async {
    final server = _server();
    await _pumpApp(tester, server);
    await _tapField(tester);
    await _search(tester, 'customer 2');
    expect(_focused(tester), isTrue);

    await tester.tap(_row(2));
    await tester.pump();
    // Gone as the tap lands — before the conversation slides in.
    _expectAtRest(tester);
    await settle(tester, 30);
    expect(find.text('Conversation 2'), findsOneWidget);

    await tester.pageBack();
    await settle(tester, 30);
    _expectAtRest(tester);
    // The search and its results are where the agent left them.
    expect(_textField(tester).controller!.text, 'customer 2');
    expect(_row(2), findsOneWidget);
    expect(_row(1), findsNothing);
  });

  testWidgets('a conversation opened without a tap on the inbox (a '
      'notification, a link) does not leave the field to be refocused on the '
      'way back', (tester) async {
    final server = _server();
    final router = await _pumpApp(tester, server);
    await _tapField(tester);
    expect(_focused(tester), isTrue);

    router.push('/inbox/5');
    await settle(tester, 30);
    expect(find.text('Conversation 5'), findsOneWidget);
    expect(_keyboard(tester), isFalse);

    router.pop();
    await settle(tester, 30);
    _expectAtRest(tester);
  });

  testWidgets('a sheet opened from the inbox closes without reopening the '
      'keyboard', (tester) async {
    final server = _server();
    await _pumpApp(tester, server);
    await _tapField(tester);

    await tester.longPress(_row(1));
    await settle(tester, 30);
    _expectAtRest(tester);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // the barrier
    await settle(tester, 30);
    expect(find.byType(BottomSheet), findsNothing);
    _expectAtRest(tester);
  });

  testWidgets('7–8. another section and back: still at rest, the query kept; '
      'a tap still opens the keyboard', (tester) async {
    final server = _server();
    final router = await _pumpApp(tester, server);
    await _tapField(tester);
    await _search(tester, 'customer 6');

    router.go('/other');
    await settle(tester, 30);
    expect(find.text('Another section'), findsOneWidget);
    expect(_keyboard(tester), isFalse);

    router.go('/inbox');
    await settle(tester, 30);
    _expectAtRest(tester);
    // A new inbox screen, showing the search the inbox is still on.
    expect(_textField(tester).controller!.text, 'customer 6');
    expect(_row(6), findsOneWidget);
    expect(_row(1), findsNothing);

    await _tapField(tester);
    expect(_focused(tester), isTrue);
    expect(_keyboard(tester), isTrue);
  });

  testWidgets('9. clearing still restores the unsearched inbox', (
    tester,
  ) async {
    final server = _server();
    await _pumpApp(tester, server);
    await _tapField(tester);
    await _search(tester, 'customer 2');
    expect(_row(1), findsNothing);

    await tester.tap(find.byKey(const Key('inbox_search_clear')));
    await settle(tester);
    expect(_textField(tester).controller!.text, isEmpty);
    expect(_searches(server).last, isNull);
    expect(_row(1), findsOneWidget);
  });

  testWidgets('10. switching filters puts the keyboard away and the reload '
      'does not bring it back', (tester) async {
    final server = _server();
    await _pumpApp(tester, server);
    await _tapField(tester);
    await _search(tester, 'customer 2');

    await tester.tap(find.byKey(const Key('quick_filter_all')));
    await tester.pump();
    _expectAtRest(tester);
    await settle(tester, 30);
    _expectAtRest(tester);
    final last = server.listRequests.last.queryParameters;
    expect(last['search'], 'customer 2');
    expect(last.containsKey('view'), isFalse);

    // A filter's own menu opening and closing does not either.
    await tester.tap(find.byKey(const Key('inbox_channel_filter')));
    await settle(tester, 30);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester, 30);
    _expectAtRest(tester);
  });

  testWidgets('scrolling the results puts the keyboard away', (tester) async {
    final server = _server(30);
    await _pumpApp(tester, server);
    await _tapField(tester);
    expect(_keyboard(tester), isTrue);

    await tester.drag(
      find.byKey(const ValueKey('inboxList')),
      const Offset(0, -300),
    );
    await settle(tester);
    _expectAtRest(tester);
  });

  testWidgets('the field does not take focus by itself when filters or the '
      'search change from elsewhere', (tester) async {
    final server = _server();
    await _pumpApp(tester, server);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(InboxScreen)),
    );

    c
        .read(inboxFiltersProvider.notifier)
        .update(c.read(inboxFiltersProvider).copyWith(search: 'customer 1'));
    await settle(tester, 30);
    expect(_textField(tester).controller!.text, 'customer 1');
    _expectAtRest(tester);

    c
        .read(inboxFiltersProvider.notifier)
        .selectQuickFilter(InboxQuickFilter.unread);
    await settle(tester, 30);
    _expectAtRest(tester);
  });
}
