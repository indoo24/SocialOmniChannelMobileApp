/// Inbox page navigation against a large inbox: `GET /conversations/grouped/`
/// is page-number pagination over groups (`?page=N`, 30 per page). One page is on screen
/// and in memory at a time; Previous / Next / page numbers / "Go to page"
/// replace it. Driven through the real [InboxScreen], [InboxPaginationBar]
/// and [InboxController] against a small stateful fake server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_pagination_bar.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/grouped_inbox.dart';

// ---------------------------------------------------------------------------
// Fake server
// ---------------------------------------------------------------------------

const _pageSize = 30; // the backend's default; neither client overrides it

/// Conversations newest first, the way the backend lists them. Every third
/// one is unread. A realtime change is simulated by [bump] (a conversation
/// gets a new message and moves to the top) or [addNew].
class _Server implements HttpClientAdapter {
  _Server(int count) {
    for (var i = 0; i < count; i++) {
      _rows.add(_make(count - i, minutesAgo: i + 1));
    }
  }

  final List<Map<String, dynamic>> _rows = [];
  final _base = DateTime.utc(2026, 9, 28, 12);
  int _clock = 0;

  /// Every list request the inbox made (not the `page_size=1` count probes).
  final List<Uri> listRequests = [];

  /// Requests for these pages wait until the completer completes.
  final Map<int, Completer<void>> hold = {};

  /// Requests for these pages fail once with a 500.
  final Set<int> failOnce = {};

  Map<String, dynamic> _make(int id, {required int minutesAgo}) => {
    'id': id,
    'customer': {'id': id, 'display_name': 'Customer $id'},
    'provider': 'FACEBOOK',
    'channel_id': 1,
    'channel_name': 'Page',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': id % 3 == 0 ? 1 : 0,
    'message_count': 1,
    'assigned_to': null,
    'last_message_preview': 'Message from $id',
    'last_message_at': _base
        .subtract(Duration(minutes: minutesAgo))
        .toIso8601String(),
  };

  String get _now => _base.add(Duration(minutes: ++_clock)).toIso8601String();

  /// A new message on [id]: it moves to the top, as the backend orders it.
  void bump(int id, {String preview = 'New message'}) {
    final row = _rows.firstWhere((r) => r['id'] == id);
    _rows
      ..remove(row)
      ..insert(0, {
        ...row,
        'last_message_at': _now,
        'last_message_preview': preview,
      });
  }

  /// A brand-new conversation arrives at the top.
  void addNew(int id) =>
      _rows.insert(0, {..._make(id, minutesAgo: 0), 'last_message_at': _now});

  /// Drops the oldest [n] conversations (resolved elsewhere, say).
  void removeOldest(int n) => _rows.removeRange(_rows.length - n, _rows.length);

  Iterable<int> pagesRequested() =>
      listRequests.map((u) => int.parse(u.queryParameters['page'] ?? '1'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final uri = options.uri;
    if (!uri.path.endsWith('/conversations/grouped/')) {
      return _json({'count': 0, 'next': null, 'previous': null, 'results': []});
    }
    final q = uri.queryParameters;
    final probe = q['page_size'] == '1';
    if (!probe) listRequests.add(uri);

    var rows = _rows.where((r) {
      final search = q['search'];
      if (search != null &&
          !(r['customer']['display_name'] as String).toLowerCase().contains(
            search.toLowerCase(),
          )) {
        return false;
      }
      if (q['unread'] == 'true' && (r['unread_count'] as int) == 0) {
        return false;
      }
      return true;
    }).toList();

    final size = int.tryParse(q['page_size'] ?? '') ?? _pageSize;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    final count = rows.length;
    final totalPages = rows.isEmpty ? 1 : (count + size - 1) ~/ size;

    if (!probe) {
      final gate = hold[page];
      if (gate != null) await gate.future;
      if (failOnce.remove(page)) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Boom.'},
        }, 500);
      }
    }
    if (page > totalPages) {
      return _json({
        'error': {'code': 'not_found', 'message': 'Invalid page.'},
      }, 404);
    }
    final start = (page - 1) * size;
    rows = rows.sublist(start, (start + size).clamp(0, rows.length));
    return _json({
      'count': count,
      'page': page,
      'page_size': size,
      'total_pages': totalPages,
      'next': page < totalPages
          ? 'https://example.test/api/conversations/grouped/?page=${page + 1}'
          : null,
      'previous': page > 1
          ? 'https://example.test/api/conversations/grouped/?page=${page - 1}'
          : null,
      'results': groupedRows(rows),
    });
  }

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

final _admin = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

const _channel = ChannelConnection(
  id: 1,
  provider: 'FACEBOOK',
  displayName: 'Page',
  status: 'CONNECTED',
  isActive: true,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const _phone = Size(390, 800);
const _tablet = Size(820, 1000);

List<Override> _overrides(_Server server) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  return [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWith((ref) => _admin),
    channelsProvider.overrideWith((ref) async => const [_channel]),
  ];
}

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  Size size = _phone,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(server),
      child: _app(const InboxScreen(), locale: locale, theme: theme),
    ),
  );
  await _settle(tester);
}

/// Lets the fake server's responses land. Not `pumpAndSettle`: a progress
/// indicator animates for as long as a page is loading.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(InboxScreen)));

InboxState _state(WidgetTester tester) =>
    _container(tester).read(inboxControllerProvider).requireValue;

InboxController _inbox(WidgetTester tester) =>
    _container(tester).read(inboxControllerProvider.notifier);

List<int> _ids(WidgetTester tester) =>
    _state(tester).conversations.map((c) => c.id).toList();

/// Server ids on [page] of a fresh [_Server] of [count].
List<int> _pageIds(int count, int page) => [
  for (var i = (page - 1) * _pageSize; i < page * _pageSize && i < count; i++)
    count - i,
];

Future<void> _goTo(WidgetTester tester, int page) async {
  unawaited(_inbox(tester).goToPage(page));
  await _settle(tester);
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('inboxList')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

final _bar = find.byKey(const ValueKey('inboxPagination'));
final _previous = find.byKey(const ValueKey('inboxPreviousPage'));
final _next = find.byKey(const ValueKey('inboxNextPage'));
final _indicator = find.byKey(const ValueKey('inboxPageIndicator'));
final _loading = find.byKey(const ValueKey('inboxPageLoading'));
final _pageError = find.byKey(const ValueKey('inboxPageError'));
final _dialog = find.byKey(const ValueKey('inboxGoToPageDialog'));
final _field = find.byKey(const ValueKey('inboxGoToPageField'));
final _go = find.byKey(const ValueKey('inboxGoToPageGo'));
Finder _pageButton(int page) => find.byKey(ValueKey('inboxPage_$page'));

bool _enabled(WidgetTester tester, Finder arrow) {
  final button = tester.widget(
    find
        .descendant(
          of: arrow,
          matching: find.byWidgetPredicate(
            (w) => w is IconButton || w is ButtonStyleButton,
          ),
        )
        .first,
  );
  return button is IconButton
      ? button.onPressed != null
      : (button as ButtonStyleButton).onPressed != null;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(_next);
  await _settle(tester);
}

void main() {
  group('page window', () {
    test('6. nearby pages around the current one, first and last kept', () {
      expect(inboxPageWindow(20, 400), [1, null, 19, 20, 21, null, 400]);
      expect(inboxPageWindow(20, 400, siblings: 2), [
        1,
        null,
        18,
        19,
        20,
        21,
        22,
        null,
        400,
      ]);
    });

    test('7. ellipses only where they hide two or more pages, and the width '
        'never changes while paging', () {
      expect(inboxPageWindow(1, 400), [1, 2, 3, 4, 5, null, 400]);
      expect(inboxPageWindow(4, 400), [1, 2, 3, 4, 5, null, 400]);
      expect(inboxPageWindow(5, 400), [1, null, 4, 5, 6, null, 400]);
      expect(inboxPageWindow(400, 400), [1, null, 396, 397, 398, 399, 400]);
      expect(inboxPageWindow(3, 7), [1, 2, 3, 4, 5, 6, 7]);
      expect(inboxPageWindow(1, 1), [1]);
      expect(inboxPageWindow(1, 0), isEmpty);
      for (var page = 1; page <= 400; page++) {
        final window = inboxPageWindow(page, 400);
        expect(window, hasLength(7), reason: 'page $page');
        expect(window, contains(page));
        final numbers = window.whereType<int>().toList();
        expect(numbers.toSet(), hasLength(numbers.length));
        expect(numbers, orderedEquals([...numbers]..sort()));
      }
    });
  });

  group('the bar is really on screen', () {
    testWidgets('page 1 of 400 → bar visible at the bottom without '
        'scrolling, outside the list; Next replaces the 30 rows; scrolling '
        'never loads anything', (tester) async {
      final server = _Server(12000); // page_size 30, total_pages 400
      await _open(tester, server);

      // The response the screen got: page 1, 30 rows, 400 pages.
      expect(server.pagesRequested(), [1]);
      expect(_state(tester).page, 1);
      expect(_state(tester).totalPages, 400);
      expect(_state(tester).conversations, hasLength(30));

      // Rendered, inside the visible screen, and not part of the list's
      // scrolling content.
      expect(_bar, findsOneWidget);
      final screen = tester.getRect(find.byType(InboxScreen));
      final bar = tester.getRect(_bar);
      expect(screen.contains(bar.topLeft), isTrue);
      expect(screen.contains(bar.bottomRight - const Offset(1, 1)), isTrue);
      expect(bar.bottom, closeTo(screen.bottom, 1));
      expect(
        find.ancestor(of: _bar, matching: find.byType(Scrollable)),
        findsNothing,
      );
      final list = tester.getRect(find.byKey(const ValueKey('inboxList')));
      expect(list.bottom, lessThanOrEqualTo(bar.top));

      expect(find.text('Page 1 of 400'), findsOneWidget);
      expect(_enabled(tester, _previous), isFalse);
      expect(_enabled(tester, _next), isTrue);

      // Scrolling to the very end of the page requests nothing.
      await tester.fling(
        find.byKey(const ValueKey('inboxList')),
        const Offset(0, -4000),
        3000,
      );
      await tester.pumpAndSettle();
      final position = _position(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(server.pagesRequested(), [1]);
      expect(_ids(tester), _pageIds(12000, 1));

      // Next: page 2 requested, and page 2 replaces page 1's rows.
      await _tapNext(tester);
      expect(server.pagesRequested(), [1, 2]);
      expect(find.text('Page 2 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 2));
      expect(_state(tester).conversations, hasLength(30));
      expect(
        find.byKey(ValueKey('inbox-conversation-${_pageIds(12000, 1).first}')),
        findsNothing,
      );

      // Previous: back to page 1.
      await tester.tap(_previous);
      await _settle(tester);
      expect(server.pagesRequested(), [1, 2, 1]);
      expect(find.text('Page 1 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 1));
    });
  });

  group('states', () {
    testWidgets('1 + 4. page 1: "Page 1 of 400", Previous disabled, Next '
        'enabled, only page 1 requested', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);

      expect(server.pagesRequested(), [1]);
      expect(
        server.listRequests.single.queryParameters.containsKey('page_size'),
        isFalse,
      );
      expect(find.text('Page 1 of 400'), findsOneWidget);
      expect(_enabled(tester, _previous), isFalse);
      expect(_enabled(tester, _next), isTrue);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('2. a middle page: both directions enabled, its own rows', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 20);

      expect(find.text('Page 20 of 400'), findsOneWidget);
      expect(_enabled(tester, _previous), isTrue);
      expect(_enabled(tester, _next), isTrue);
      expect(_ids(tester), _pageIds(12000, 20));
    });

    testWidgets('3 + 5. the last page: Next disabled, Previous enabled', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 400);

      expect(find.text('Page 400 of 400'), findsOneWidget);
      expect(_enabled(tester, _next), isFalse);
      expect(_enabled(tester, _previous), isTrue);
      await tester.tap(_next);
      await _settle(tester);
      expect(server.pagesRequested(), [1, 400]);
    });

    testWidgets('Next and Previous move one page, replacing the rows', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _tapNext(tester);
      await _tapNext(tester);
      expect(find.text('Page 3 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 3));

      await tester.tap(_previous);
      await _settle(tester);
      expect(find.text('Page 2 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 2));
      expect(server.pagesRequested(), [1, 2, 3, 2]);
    });

    testWidgets('19. only the current page is ever held', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      for (var i = 0; i < 5; i++) {
        await _tapNext(tester);
      }
      expect(_state(tester).page, 6);
      expect(_state(tester).conversations, hasLength(_pageSize));
      expect(_ids(tester), _pageIds(12000, 6));
      expect(_state(tester).total, 12000);
    });

    testWidgets('23. a single page: no pagination bar at all', (tester) async {
      final server = _Server(12);
      await _open(tester, server);
      expect(_ids(tester), _pageIds(12, 1));
      expect(_bar, findsNothing);
      expect(_previous, findsNothing);
    });

    testWidgets('24. an empty inbox: the empty state and no bar', (
      tester,
    ) async {
      final server = _Server(0);
      await _open(tester, server);
      expect(find.text('No conversations yet'), findsOneWidget);
      expect(_bar, findsNothing);
    });
  });

  group('page numbers (wider screens)', () {
    testWidgets('6 + 7. nearby numbers with ellipses; the current page is '
        'filled, bold and announced as current', (tester) async {
      final server = _Server(12000);
      await _open(tester, server, size: _tablet);
      await _goTo(tester, 20);

      for (final page in [1, 18, 19, 20, 21, 22, 400]) {
        expect(_pageButton(page), findsOneWidget, reason: 'page $page');
      }
      expect(_pageButton(2), findsNothing);
      expect(_pageButton(399), findsNothing);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNWidgets(2));

      final scheme = Theme.of(tester.element(_bar)).colorScheme;
      expect(tester.widget<Material>(_pageButton(20)).color, scheme.primary);
      expect(
        tester.widget<Material>(_pageButton(21)).color,
        Colors.transparent,
      );
      final current = tester.widget<Text>(
        find.descendant(of: _pageButton(20), matching: find.text('20')),
      );
      expect(current.style?.fontWeight, FontWeight.w700);
      expect(
        tester.getSemantics(_pageButton(20)),
        matchesSemantics(
          label: 'Page 20, current page',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('a page number opens that page; an ellipsis opens "Go to '
        'page"', (tester) async {
      final server = _Server(12000);
      await _open(tester, server, size: _tablet);

      await tester.tap(_pageButton(400));
      await _settle(tester);
      expect(_state(tester).page, 400);
      expect(server.pagesRequested(), [1, 400]);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      expect(_dialog, findsOneWidget);
    });

    testWidgets('22. dark mode: the current page uses the dark primary', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server, size: _tablet, theme: AppTheme.dark);
      final scheme = AppTheme.dark.colorScheme;
      expect(tester.widget<Material>(_pageButton(1)).color, scheme.primary);
      final label = tester.widget<Text>(
        find.descendant(of: _pageButton(1), matching: find.text('1')),
      );
      expect(label.style?.color, scheme.onPrimary);
      expect(tester.takeException(), isNull);
    });
  });

  group('go to page', () {
    testWidgets('8. typing a page and pressing Go opens it', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);

      await tester.tap(_indicator);
      await tester.pumpAndSettle();
      expect(_dialog, findsOneWidget);
      expect(find.text('Go to page'), findsOneWidget);
      final field = tester.widget<TextField>(_field);
      expect(field.keyboardType, TextInputType.number);

      await tester.enterText(_field, '250');
      await tester.pump();
      await tester.tap(_go);
      await _settle(tester);

      expect(_dialog, findsNothing);
      expect(find.text('Page 250 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 250));
      expect(server.pagesRequested(), [1, 250]);
    });

    testWidgets('8. Enter submits', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await tester.tap(_indicator);
      await tester.pumpAndSettle();
      await tester.enterText(_field, '7');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await _settle(tester);
      expect(_state(tester).page, 7);
    });

    testWidgets('9 + 10 + 11. invalid pages are refused: 0, above the last, '
        'letters', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await tester.tap(_indicator);
      await tester.pumpAndSettle();

      for (final value in ['0', '401', '999']) {
        await tester.enterText(_field, value);
        await tester.pump();
        expect(
          find.text('Enter a page from 1 to 400'),
          findsOneWidget,
          reason: value,
        );
        expect(tester.widget<FilledButton>(_go).onPressed, isNull);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pump();
        expect(_dialog, findsOneWidget, reason: value);
      }

      // Digits only, and no more digits than the last page has.
      await tester.enterText(_field, 'abc');
      await tester.pump();
      expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
      await tester.enterText(_field, '12345');
      await tester.pump();
      expect(tester.widget<TextField>(_field).controller!.text, '123');

      expect(server.pagesRequested(), [1]);
      expect(_state(tester).page, 1);
    });

    testWidgets('Cancel and Escape close it without changing the page', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 3);

      await tester.tap(_indicator);
      await tester.pumpAndSettle();
      await tester.enterText(_field, '99');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);

      await tester.tap(_indicator);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);

      expect(_state(tester).page, 3);
      expect(server.pagesRequested(), [1, 3]);
    });
  });

  group('loading, failures, races', () {
    testWidgets('12. while a page loads: controls disabled, the old page '
        'dimmed and inert, a thin progress bar — and the indicator still '
        'says where the agent is', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      server.hold[2] = Completer<void>();

      await tester.tap(_next);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_loading, findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(_enabled(tester, _next), isFalse);
      expect(_enabled(tester, _previous), isFalse);
      expect(find.text('Page 1 of 400'), findsOneWidget);
      final dim = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('inboxList')),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(dim.opacity, lessThan(1));
      // No full-screen spinner: the only one is the indicator's own.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.descendant(
          of: _indicator,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      server.hold.remove(2)!.complete();
      await _settle(tester);
      expect(_loading, findsNothing);
      expect(find.text('Page 2 of 400'), findsOneWidget);
      expect(_enabled(tester, _next), isTrue);
    });

    testWidgets('13 + 14. a failed page keeps the agent where they were; '
        'retry opens it', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 20);
      server.failOnce.add(21);

      await _tapNext(tester);
      expect(_pageError, findsOneWidget);
      expect(find.text("Couldn't load page 21"), findsOneWidget);
      expect(find.text('Page 20 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 20));
      expect(find.byKey(const ValueKey('inboxList')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inboxPageRetry')));
      await _settle(tester);
      expect(_pageError, findsNothing);
      expect(find.text('Page 21 of 400'), findsOneWidget);
      expect(_ids(tester), _pageIds(12000, 21));
      expect(server.pagesRequested(), [1, 20, 21, 21]);
    });

    testWidgets('18. rapid Next taps make one request, for one page', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      server.hold[2] = Completer<void>();
      for (var i = 0; i < 4; i++) {
        await tester.tap(_next, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 10));
      }
      // Calls that get past the disabled button are ignored as well.
      unawaited(_inbox(tester).nextPage());
      unawaited(_inbox(tester).goToPage(9));
      await tester.pump();
      expect(server.pagesRequested(), [1, 2]);

      server.hold.remove(2)!.complete();
      await _settle(tester);
      expect(_state(tester).page, 2);
      expect(server.pagesRequested(), [1, 2]);
    });

    testWidgets('a filter change while a page loads: that page is dropped, '
        'the new filter opens at page 1', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      server.hold[5] = Completer<void>();
      unawaited(_inbox(tester).goToPage(5));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await _settle(tester);
      server.hold.remove(5)!.complete();
      await _settle(tester);

      expect(_state(tester).page, 1);
      expect(
        _state(tester).conversations.every((c) => c.unreadCount > 0),
        isTrue,
      );
      expect(_state(tester).isNavigating, isFalse);
    });

    testWidgets('25. leaving the inbox while a page loads is harmless', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      server.hold[2] = Completer<void>();
      await tester.tap(_next);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox());
      server.hold.remove(2)!.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('filters and search', () {
    testWidgets('15. a filter change goes back to page 1 of the new filter, '
        'and paging keeps the filter', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 5);

      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await _settle(tester);
      final filtered = server.listRequests.last.queryParameters;
      expect(filtered['page'], '1');
      expect(filtered['unread'], 'true');
      expect(find.text('Page 1 of 134'), findsOneWidget); // 4000 unread

      await _tapNext(tester);
      final next = server.listRequests.last.queryParameters;
      expect(next['page'], '2');
      expect(next['unread'], 'true');
      expect(find.text('Page 2 of 134'), findsOneWidget);
    });

    testWidgets('16. a search goes back to page 1, and paging keeps the '
        'query', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 9);

      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Customer 11');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _settle(tester);
      final searched = server.listRequests.last.queryParameters;
      expect(searched['page'], '1');
      expect(searched['search'], 'Customer 11');
      expect(_state(tester).page, 1);

      // Close the keyboard so the bar is back, then page on.
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.viewInsets = FakeViewPadding.zero;
      await _settle(tester);
      await _tapNext(tester);
      final next = server.listRequests.last.queryParameters;
      expect(next['page'], '2');
      expect(next['search'], 'Customer 11');
    });
  });

  group('realtime', () {
    testWidgets('17. an event on page 20 refreshes page 20 — never page 1', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 20);
      // Two new conversations push page 20's rows down by two.
      server
        ..addNew(90001)
        ..addNew(90002);

      unawaited(_inbox(tester).refreshQuietly());
      await _settle(tester);

      expect(server.pagesRequested(), [1, 20, 20]);
      expect(find.text('Page 20 of 401'), findsOneWidget); // 12,002 now
      expect(_ids(tester).first, 12000 - 19 * _pageSize + 2);
    });

    testWidgets('17. scrolled down, the page is not refreshed under the '
        'agent; the pill reloads the same page', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 20);
      final position = _position(tester);
      position.jumpTo(600);
      await _settle(tester);
      final requests = server.listRequests.length;

      server.addNew(90001);
      final inbox = _inbox(tester);
      for (var i = 0; i < 4; i++) {
        unawaited(inbox.refreshQuietly());
      }
      await _settle(tester);
      expect(server.listRequests, hasLength(requests));
      expect(position.pixels, 600);
      expect(_ids(tester), _pageIds(12000, 20));
      final pill = find.byKey(const ValueKey('inboxNewActivity'));
      expect(pill, findsOneWidget);

      await tester.tap(pill);
      await _settle(tester);
      expect(server.pagesRequested().last, 20);
      expect(find.text('Page 20 of 401'), findsOneWidget); // 12,001 now
      expect(_ids(tester).first, 12000 - 19 * _pageSize + 1);
      expect(pill, findsNothing);
      expect(position.pixels, 0);
    });

    testWidgets('a burst of events is one refetch plus one, not one per '
        'event', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 4);
      server.hold[4] = Completer<void>();
      for (var i = 0; i < 6; i++) {
        unawaited(_inbox(tester).refreshQuietly());
      }
      await tester.pump();
      server.hold.remove(4)!.complete();
      await _settle(tester);
      expect(server.pagesRequested(), [1, 4, 4, 4]);
      expect(_state(tester).page, 4);
    });

    testWidgets('a page that no longer exists falls back to the new last '
        'page', (tester) async {
      final server = _Server(120); // 4 pages
      await _open(tester, server);
      await _goTo(tester, 4);
      server.removeOldest(40); // now 80: 3 pages

      unawaited(_inbox(tester).refreshQuietly());
      await _settle(tester);
      expect(_state(tester).page, 3);
      expect(_state(tester).totalPages, 3);
      // Three pages fit as numbers, the current one filled.
      expect(
        tester.widget<Material>(_pageButton(3)).color,
        Theme.of(tester.element(_bar)).colorScheme.primary,
      );
      expect(_ids(tester), _pageIds(80, 3).map((id) => id + 40).toList());
    });

    testWidgets('pull-to-refresh reloads the page the agent is on', (
      tester,
    ) async {
      final server = _Server(12000);
      await _open(tester, server);
      await _goTo(tester, 12);
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();
      expect(server.pagesRequested(), [1, 12, 12]);
      expect(find.text('Page 12 of 400'), findsOneWidget);
    });
  });

  group('scroll and rebuild', () {
    testWidgets('27. a new page starts at its top — moved there only after '
        'it has been laid out', (tester) async {
      final server = _Server(12000);
      await _open(tester, server);
      final position = _position(tester);
      position.jumpTo(900);
      await _settle(tester);
      server.hold[2] = Completer<void>();

      await tester.tap(_next);
      await tester.pump(const Duration(milliseconds: 50));
      // Still loading: the old page has not been moved.
      expect(position.pixels, 900);

      server.hold.remove(2)!.complete();
      await _settle(tester);
      expect(_state(tester).page, 2);
      expect(_position(tester).pixels, 0);
      expect(
        find.byKey(ValueKey('inbox-conversation-${_pageIds(12000, 2).first}')),
        findsOneWidget,
      );
    });

    testWidgets('26. the page survives a rebuild and the screen being '
        'rebuilt from scratch', (tester) async {
      final server = _Server(12000);
      final container = ProviderContainer(overrides: _overrides(server));
      addTearDown(container.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = _phone;
      addTearDown(tester.view.reset);
      final show = ValueNotifier(true);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
            ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) =>
                  visible ? const InboxScreen() : const SizedBox(),
            ),
          ),
        ),
      );
      await _settle(tester);
      unawaited(container.read(inboxControllerProvider.notifier).goToPage(7));
      await _settle(tester);

      tester.view.physicalSize = const Size(400, 820);
      await _settle(tester);
      expect(find.text('Page 7 of 400'), findsOneWidget);

      show.value = false;
      await tester.pump();
      show.value = true;
      await _settle(tester);
      expect(find.text('Page 7 of 400'), findsOneWidget);
      expect(server.pagesRequested(), [1, 7]);
    });
  });

  group('directions', () {
    testWidgets('21. LTR: Previous on the left, Next on the right', (
      tester,
    ) async {
      await _open(tester, _Server(12000));
      expect(
        tester.getCenter(_previous).dx,
        lessThan(tester.getCenter(_next).dx),
      );
    });

    testWidgets('20. RTL: Arabic labels, Previous on the right, and the '
        'jump dialog in Arabic', (tester) async {
      await _open(tester, _Server(12000), locale: const Locale('ar'));
      expect(Directionality.of(tester.element(_bar)), TextDirection.rtl);
      expect(find.text('صفحة 1 من 400'), findsOneWidget);
      expect(find.text('السابق'), findsOneWidget);
      expect(find.text('التالي'), findsOneWidget);
      expect(
        tester.getCenter(_previous).dx,
        greaterThan(tester.getCenter(_next).dx),
      );

      await tester.tap(_indicator);
      await tester.pumpAndSettle();
      expect(find.text('الانتقال إلى صفحة'), findsOneWidget);
      await tester.enterText(_field, '500');
      await tester.pump();
      expect(find.text('أدخل رقم صفحة من 1 إلى 400'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets('the longest labels fit a 360 px phone '
          '(${locale.languageCode})', (tester) async {
        await _open(
          tester,
          _Server(12000),
          size: const Size(360, 720),
          locale: locale,
        );
        await _goTo(tester, 400);
        expect(tester.takeException(), isNull);
        expect(_state(tester).page, 400);
        expect(
          find.text(
            locale.languageCode == 'ar' ? 'صفحة 400 من 400' : 'Page 400 of 400',
          ),
          findsOneWidget,
        );
        expect(
          find.text(locale.languageCode == 'ar' ? 'السابق' : 'Previous'),
          findsOneWidget,
        );
      });
    }

    testWidgets('a very narrow phone keeps icon-only arrows and does not '
        'overflow', (tester) async {
      await _open(tester, _Server(12000), size: const Size(320, 640));
      expect(find.text('Previous'), findsNothing);
      expect(find.byTooltip('Previous'), findsOneWidget);
      expect(find.text('Page 1 of 400'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
