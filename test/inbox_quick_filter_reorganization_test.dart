import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_quick_filter_bar.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/conversations/platform_account_filter_bar.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final _testEmployee = Employee(
  id: 42,
  email: 'employee@test.com',
  fullName: 'Mohamed Gad',
  initials: 'MG',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

const _fbAccount1 = ChannelConnection(
  id: 1,
  provider: 'FACEBOOK',
  providerDisplay: 'Facebook Messenger',
  displayName: 'IndoTech',
  status: 'CONNECTED',
  isActive: true,
);

const _fbAccount2 = ChannelConnection(
  id: 2,
  provider: 'FACEBOOK',
  providerDisplay: 'Facebook Messenger',
  displayName: 'عروض طنطا كول',
  status: 'CONNECTED',
  isActive: true,
);

const _igAccount1 = ChannelConnection(
  id: 3,
  provider: 'INSTAGRAM',
  providerDisplay: 'Instagram Direct',
  displayName: 'Mohamed',
  status: 'CONNECTED',
  isActive: true,
);

const _igAccount2 = ChannelConnection(
  id: 4,
  provider: 'INSTAGRAM',
  providerDisplay: 'Instagram Direct',
  displayName: 'Yousef Qandeel',
  status: 'CONNECTED',
  isActive: true,
);

const _waAccount1 = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Support',
  status: 'CONNECTED',
  isActive: true,
);

const _waAccount2 = ChannelConnection(
  id: 6,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Sales',
  status: 'CONNECTED',
  isActive: true,
);

String _convoJson({
  required int id,
  required String customerName,
  required String provider,
  required int channelId,
  String status = 'OPEN',
  String priority = 'NORMAL',
  int unreadCount = 0,
  int? assignedToId,
}) {
  final assignedJson = assignedToId == null
      ? 'null'
      : '{"id": $assignedToId, "full_name": "Employee $assignedToId"}';
  return '''
{
  "id": $id,
  "customer": {"id": $id, "display_name": "$customerName"},
  "provider": "$provider",
  "channel_id": $channelId,
  "channel_name": "Channel $channelId",
  "status": "$status",
  "priority": "$priority",
  "unread_count": $unreadCount,
  "message_count": 1,
  "assigned_to": $assignedJson
}
''';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Inbox Quick Filter Reorganization Tests', () {
    late ApiClient apiClient;
    late _StubAdapter adapter;

    final allChannels = [
      _fbAccount1,
      _fbAccount2,
      _igAccount1,
      _igAccount2,
      _waAccount1,
      _waAccount2,
    ];

    setUp(() {
      adapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/conversations/counts/')) {
          return _json(
            '{"all": 17, "mine": 2, "unassigned": 0, "unread": 0, "open": 14}',
            200,
          );
        }
        if (path.contains('/conversations/')) {
          final convos = [
            _convoJson(
              id: 101,
              customerName: 'Customer A',
              provider: 'FACEBOOK',
              channelId: 1,
              unreadCount: 2,
              assignedToId: null,
            ),
            _convoJson(
              id: 102,
              customerName: 'Customer B',
              provider: 'INSTAGRAM',
              channelId: 4,
              unreadCount: 1,
              assignedToId: 42,
            ),
            _convoJson(
              id: 103,
              customerName: 'Customer C',
              provider: 'WHATSAPP',
              channelId: 6,
              unreadCount: 0,
              assignedToId: 42,
            ),
          ];
          return _json(
            '{"count": ${convos.length}, "next": null, "previous": null, "results": [${convos.join(',')}]}',
            200,
          );
        }
        if (path.contains('/channels/')) {
          return _json(
            '{"count": 6, "next": null, "previous": null, "results": ['
            '{"id": 1, "provider": "FACEBOOK", "provider_display": "Facebook Messenger", "display_name": "IndoTech", "status": "CONNECTED", "is_active": true},'
            '{"id": 2, "provider": "FACEBOOK", "provider_display": "Facebook Messenger", "display_name": "عروض طنطا كول", "status": "CONNECTED", "is_active": true},'
            '{"id": 3, "provider": "INSTAGRAM", "provider_display": "Instagram Direct", "display_name": "Mohamed", "status": "CONNECTED", "is_active": true},'
            '{"id": 4, "provider": "INSTAGRAM", "provider_display": "Instagram Direct", "display_name": "Yousef Qandeel", "status": "CONNECTED", "is_active": true},'
            '{"id": 5, "provider": "WHATSAPP", "provider_display": "WhatsApp Business", "display_name": "WhatsApp Support", "status": "CONNECTED", "is_active": true},'
            '{"id": 6, "provider": "WHATSAPP", "provider_display": "WhatsApp Business", "display_name": "WhatsApp Sales", "status": "CONNECTED", "is_active": true}'
            ']}',
            200,
          );
        }
        return _json('{}', 200);
      });

      apiClient = ApiClient.create(cookieJar: CookieJar());
      apiClient.raw.httpClientAdapter = adapter;
    });

    Widget createInboxApp({
      Locale locale = const Locale('en'),
      ThemeData? theme,
    }) {
      return ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          currentEmployeeProvider.overrideWith((ref) => _testEmployee),
          channelsProvider.overrideWith((ref) async => allChannels),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InboxScreen(),
        ),
      );
    }

    testWidgets('1-5. All 5 primary quick filters are permanently visible', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quick_filter_all')), findsOneWidget);
      expect(find.byKey(const Key('quick_filter_mine')), findsOneWidget);
      expect(find.byKey(const Key('quick_filter_unassigned')), findsOneWidget);
      expect(find.byKey(const Key('quick_filter_unread')), findsOneWidget);
      expect(find.byKey(const Key('quick_filter_open')), findsOneWidget);
    });

    testWidgets('6-7. Active state and exact count display behavior', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      // Counts: all=17, mine=2, open=14 are > 0 so rendered inside pills.
      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_all')),
          matching: find.text('17'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_mine')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_open')),
          matching: find.text('14'),
        ),
        findsOneWidget,
      );
      // unassigned=0, unread=0 are 0 so no count widget inside their pills.
      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_unassigned')),
          matching: find.text('0'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_unread')),
          matching: find.text('0'),
        ),
        findsNothing,
      );

      // Default active is "All"
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      expect(
        container.read(inboxFiltersProvider).activeQuickFilter,
        equals(InboxQuickFilter.all),
      );
    });

    testWidgets('8. Selecting each quick filter updates query correctly', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );

      // Tap Mine
      await tester.tap(find.byKey(const Key('quick_filter_mine')));
      await tester.pumpAndSettle();
      expect(container.read(inboxFiltersProvider).assignedToMe, isTrue);
      var req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['assigned_to'], equals('42'));

      // Tap Unassigned
      await tester.tap(find.byKey(const Key('quick_filter_unassigned')));
      await tester.pumpAndSettle();
      expect(container.read(inboxFiltersProvider).unassigned, isTrue);
      expect(container.read(inboxFiltersProvider).assignedToMe, isFalse);
      req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['view'], equals('unassigned'));

      // Tap Unread
      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();
      expect(container.read(inboxFiltersProvider).unread, isTrue);
      expect(container.read(inboxFiltersProvider).unassigned, isFalse);
      req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['unread'], equals('true'));

      // Tap Open
      await tester.tap(find.byKey(const Key('quick_filter_open')));
      await tester.pumpAndSettle();
      expect(container.read(inboxFiltersProvider).status, equals('OPEN'));
      expect(container.read(inboxFiltersProvider).unread, isFalse);
      req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['status'], equals('OPEN'));

      // Tap All -> clears primary filters
      await tester.tap(find.byKey(const Key('quick_filter_all')));
      await tester.pumpAndSettle();
      expect(container.read(inboxFiltersProvider).status, isNull);
      expect(container.read(inboxFiltersProvider).assignedToMe, isFalse);
      expect(container.read(inboxFiltersProvider).unassigned, isFalse);
      expect(container.read(inboxFiltersProvider).unread, isFalse);
    });

    testWidgets('9-16. Platform account filters visible outside the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      // Facebook, Instagram, WhatsApp all have 2 accounts -> 3 selector buttons
      final buttons = find.byType(PlatformAccountSelectorButton);
      expect(buttons, findsNWidgets(3));

      // Tap Instagram selector (button 1)
      await tester.tap(buttons.at(1));
      await tester.pumpAndSettle();

      // Options popup shows accounts and 'All accounts'
      expect(find.text('Mohamed'), findsOneWidget);
      expect(find.text('Yousef Qandeel'), findsOneWidget);
      expect(
        find.widgetWithText(PopupMenuItem<int>, 'All accounts'),
        findsOneWidget,
      );

      // Select Yousef Qandeel (account 4)
      await tester.tap(find.text('Yousef Qandeel'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      expect(
        container.read(inboxFiltersProvider).selectedAccounts['INSTAGRAM'],
        equals(4),
      );
      expect(
        container.read(inboxFiltersProvider).channelConnections,
        contains(4),
      );
    });

    testWidgets('17-23. Combined filters work together seamlessly', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );

      // 1. Select Instagram account (Yousef Qandeel = 4)
      final buttons = find.byType(PlatformAccountSelectorButton);
      await tester.tap(buttons.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yousef Qandeel'));
      await tester.pumpAndSettle();

      // 2. Select Unread quick filter
      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();

      final filters = container.read(inboxFiltersProvider);
      expect(filters.unread, isTrue);
      expect(filters.selectedAccounts['INSTAGRAM'], equals(4));

      final req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['unread'], equals('true'));
      expect(req.uri.queryParameters['channel_connections'], isNotNull);

      // 3. Search also composes
      container
          .read(inboxFiltersProvider.notifier)
          .update(filters.copyWith(search: 'Order 123'));
      await tester.pumpAndSettle();

      final reqSearch = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(reqSearch.uri.queryParameters['unread'], equals('true'));
      expect(reqSearch.uri.queryParameters['search'], equals('Order 123'));
      expect(reqSearch.uri.queryParameters['channel_connections'], isNotNull);
    });

    testWidgets('24-27. Advanced filter sheet remains accessible', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      // Open advanced filter sheet via AppBar tune icon
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('PRIORITY'), findsOneWidget);
      expect(find.text('CHANNEL'), findsOneWidget);

      // Urgent priority is available
      expect(find.text('Urgent'), findsOneWidget);
      await tester.tap(find.text('Urgent'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      expect(container.read(inboxFiltersProvider).priority, equals('URGENT'));
      expect(container.read(inboxFiltersProvider).hasAdvancedFilters, isTrue);
    });

    testWidgets('28-30. Pagination resets on quick filter / account change', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      // Tap Unread -> resets to page 1
      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();

      var req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['page'], equals('1'));

      // Change account -> resets to page 1
      final buttons = find.byType(PlatformAccountSelectorButton);
      await tester.tap(buttons.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IndoTech'));
      await tester.pumpAndSettle();

      req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['page'], equals('1'));
    });

    testWidgets('35. Narrow screen (320px) has no overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PlatformAccountFilterBar), findsOneWidget);
      expect(find.byType(InboxQuickFilterBar), findsOneWidget);
    });

    testWidgets('36. Arabic / RTL localization works properly', (tester) async {
      await tester.pumpWidget(createInboxApp(locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('لي'), findsOneWidget);
      expect(find.text('غير مُسندة'), findsOneWidget);
      expect(find.text('غير مقروءة'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InboxQuickFilterBar),
          matching: find.text('مفتوحة'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('37. Dark mode renders without exceptions', (tester) async {
      await tester.pumpWidget(createInboxApp(theme: AppTheme.dark));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(InboxQuickFilterBar), findsOneWidget);
    });
  });
}
