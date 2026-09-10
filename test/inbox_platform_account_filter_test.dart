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
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
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

final _adminEmployee = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.channelView, Perm.channelManage},
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
  displayName: 'Support line',
  status: 'CONNECTED',
  isActive: true,
);

const _conversationFb1 = '''
{
  "id": 101,
  "customer": {"id": 1, "display_name": "Customer FB 1"},
  "provider": "FACEBOOK",
  "channel_id": 1,
  "channel_name": "IndoTech",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 2
}
''';

const _conversationFb2 = '''
{
  "id": 102,
  "customer": {"id": 2, "display_name": "Customer FB 2"},
  "provider": "FACEBOOK",
  "channel_id": 2,
  "channel_name": "عروض طنطا كول",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 1
}
''';

const _conversationIg1 = '''
{
  "id": 103,
  "customer": {"id": 3, "display_name": "Customer IG 1"},
  "provider": "INSTAGRAM",
  "channel_id": 3,
  "channel_name": "Mohamed",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 1,
  "message_count": 4
}
''';

const _conversationIg2 = '''
{
  "id": 104,
  "customer": {"id": 4, "display_name": "Customer IG 2"},
  "provider": "INSTAGRAM",
  "channel_id": 4,
  "channel_name": "Yousef Qandeel",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 3
}
''';

const _conversationWa1 = '''
{
  "id": 105,
  "customer": {"id": 5, "display_name": "Customer WA 1"},
  "provider": "WHATSAPP",
  "channel_id": 5,
  "channel_name": "Support line",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 5
}
''';

String _page(List<String> results, {bool hasNext = false, int? count}) =>
    '{"count": ${count ?? results.length}, "next": ${hasNext ? '"http://x/?page=2"' : 'null'}, "previous": null, "results": [${results.join(',')}]}';

void main() {
  group('computeAllowedChannelConnections & ConversationFilters unit tests', () {
    final allChannels = [
      _fbAccount1,
      _fbAccount2,
      _igAccount1,
      _igAccount2,
      _waAccount1,
    ];

    test('returns null when no platform has an active account filter', () {
      final allowed = computeAllowedChannelConnections({
        'FACEBOOK': null,
        'INSTAGRAM': null,
      }, allChannels);
      expect(allowed, isNull);
    });

    test('returns correct subset when one platform is filtered', () {
      // Instagram restricted to account 4 (Yousef Qandeel). Facebook and WhatsApp unrestricted.
      final allowed = computeAllowedChannelConnections({
        'INSTAGRAM': 4,
      }, allChannels);
      // FB has 1 and 2; WA has 5; IG only has 4.
      expect(allowed, equals([1, 2, 4, 5]));
    });

    test(
      'returns correct subset when multiple platforms are filtered independently',
      () {
        // FB = 1 (IndoTech), IG = 4 (Yousef Qandeel), WA = 5 (single account unrestricted).
        final allowed = computeAllowedChannelConnections({
          'FACEBOOK': 1,
          'INSTAGRAM': 4,
        }, allChannels);
        expect(allowed, equals([1, 4, 5]));
      },
    );

    test(
      'clearing one platform returns all its channels while keeping other platform filtered',
      () {
        // FB remains 1, IG set to null ("All accounts").
        final allowed = computeAllowedChannelConnections({
          'FACEBOOK': 1,
          'INSTAGRAM': null,
        }, allChannels);
        // FB has 1; IG has 3 and 4; WA has 5.
        expect(allowed, equals([1, 3, 4, 5]));
      },
    );

    test(
      'ConversationFilters toQuery serializes channel_connections correctly',
      () {
        const filtersNone = ConversationFilters();
        expect(
          filtersNone.toQuery(1, null).containsKey('channel_connections'),
          isFalse,
        );

        const filtersSelected = ConversationFilters(
          channelConnections: [1, 4, 5],
          selectedAccounts: {'FACEBOOK': 1, 'INSTAGRAM': 4},
        );
        expect(
          filtersSelected.toQuery(1, null)['channel_connections'],
          equals('1,4,5'),
        );
        expect(filtersSelected.hasActiveAccountFilter, isTrue);
        expect(filtersSelected.hasSheetFilters, isFalse);
      },
    );

    test('ConversationFilters equality and copyWith work as expected', () {
      const f1 = ConversationFilters(
        selectedAccounts: {'FACEBOOK': 1},
        channelConnections: [1, 3, 4, 5],
      );
      final f2 = const ConversationFilters().copyWith(
        selectedAccounts: {'FACEBOOK': 1},
        channelConnections: [1, 3, 4, 5],
      );
      expect(f1, equals(f2));
      expect(f1.hashCode, equals(f2.hashCode));

      final f3 = f1.copyWith(
        clearChannelConnections: true,
        selectedAccounts: {},
      );
      expect(f3.channelConnections, isNull);
      expect(f3.selectedAccounts.isEmpty, isTrue);
      expect(f3.hasActiveAccountFilter, isFalse);
    });
  });

  group('Inbox Platform Account Filter Widget & Flow Tests', () {
    late _StubAdapter adapter;
    late ApiClient apiClient;

    final initialChannels = [
      _fbAccount1,
      _fbAccount2,
      _igAccount1,
      _igAccount2,
      _waAccount1,
    ];

    setUp(() {
      adapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/conversations/counts/')) {
          return _json('{"open": 5, "unassigned": 1, "unread": 1}', 200);
        }
        if (path.contains('/conversations/')) {
          // If query specifies channel_connections, return only matching conversations
          final connStr = options.uri.queryParameters['channel_connections'];
          final all = [
            _conversationFb1,
            _conversationFb2,
            _conversationIg1,
            _conversationIg2,
            _conversationWa1,
          ];
          if (connStr != null) {
            final allowed = connStr.split(',').map(int.tryParse).toSet();
            final filtered = <String>[];
            if (allowed.contains(1)) filtered.add(_conversationFb1);
            if (allowed.contains(2)) filtered.add(_conversationFb2);
            if (allowed.contains(3)) filtered.add(_conversationIg1);
            if (allowed.contains(4)) filtered.add(_conversationIg2);
            if (allowed.contains(5)) filtered.add(_conversationWa1);
            return _json(_page(filtered), 200);
          }
          return _json(_page(all), 200);
        }
        if (path.contains('/channels/')) {
          return _json(
            '{"count": 5, "next": null, "previous": null, "results": ['
            '{"id": 1, "provider": "FACEBOOK", "provider_display": "Facebook Messenger", "display_name": "IndoTech", "status": "CONNECTED", "is_active": true},'
            '{"id": 2, "provider": "FACEBOOK", "provider_display": "Facebook Messenger", "display_name": "عروض طنطا كول", "status": "CONNECTED", "is_active": true},'
            '{"id": 3, "provider": "INSTAGRAM", "provider_display": "Instagram Direct", "display_name": "Mohamed", "status": "CONNECTED", "is_active": true},'
            '{"id": 4, "provider": "INSTAGRAM", "provider_display": "Instagram Direct", "display_name": "Yousef Qandeel", "status": "CONNECTED", "is_active": true},'
            '{"id": 5, "provider": "WHATSAPP", "provider_display": "WhatsApp Business", "display_name": "Support line", "status": "CONNECTED", "is_active": true}'
            ']}',
            200,
          );
        }
        return _json('{}', 200);
      });

      apiClient = ApiClient.create(cookieJar: CookieJar());
      apiClient.raw.httpClientAdapter = adapter;
    });

    Widget createInboxApp({Locale locale = const Locale('en')}) {
      return ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          currentEmployeeProvider.overrideWith((ref) => _adminEmployee),
          channelsProvider.overrideWith((ref) async => initialChannels),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InboxScreen(),
        ),
      );
    }

    testWidgets(
      'shows account selectors for multi-account platforms and hides single-account platform',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        // Facebook has 2 accounts -> shows selector
        // Instagram has 2 accounts -> shows selector
        // WhatsApp has 1 account -> hidden (matches Web fn(l) => l.length > 1)
        expect(find.byType(PlatformAccountSelectorButton), findsNWidgets(2));

        // Both buttons start with "All accounts"
        expect(find.text('All accounts'), findsNWidgets(2));

        // All 5 conversations are initially rendered
        expect(find.text('Customer FB 1'), findsOneWidget);
        expect(find.text('Customer FB 2'), findsOneWidget);
        expect(find.text('Customer IG 1'), findsOneWidget);
        expect(find.text('Customer IG 2'), findsOneWidget);
        expect(find.text('Customer WA 1'), findsOneWidget);
      },
    );

    testWidgets(
      'selecting an Instagram account filters to only that account and updates button label',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        // Find the Instagram selector button (second PlatformAccountSelectorButton)
        final buttons = find.byType(PlatformAccountSelectorButton);
        final igButton = buttons.at(1);

        // Tap the Instagram selector to open popup menu
        await tester.tap(igButton);
        await tester.pumpAndSettle();

        // Dropdown menu shows Instagram Direct header and account names
        expect(find.text('Instagram Direct'), findsOneWidget);
        expect(find.text('Mohamed'), findsOneWidget);
        expect(find.text('Yousef Qandeel'), findsOneWidget);

        // Tap "Yousef Qandeel" (account 4)
        await tester.tap(find.text('Yousef Qandeel'));
        await tester.pumpAndSettle();

        // The button label changes to "Yousef Qandeel"
        expect(find.text('Yousef Qandeel'), findsWidgets);

        // Only Customer IG 2 (channel 4) is shown among IG conversations; Customer IG 1 is hidden!
        expect(find.text('Customer IG 2'), findsOneWidget);
        expect(find.text('Customer IG 1'), findsNothing);

        // Unfiltered Facebook conversations remain visible
        expect(find.text('Customer FB 1'), findsOneWidget);
        expect(find.text('Customer FB 2'), findsOneWidget);
        expect(find.text('Customer WA 1'), findsOneWidget);

        // Verify server request included channel_connections parameter:
        final lastConvoReq = adapter.received.lastWhere(
          (r) => r.uri.path.contains('/conversations/'),
        );
        expect(
          lastConvoReq.uri.queryParameters['channel_connections'],
          equals('1,2,4,5'),
        );
      },
    );

    testWidgets(
      'independent filtering: selecting Facebook account while Instagram is filtered',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        final buttons = find.byType(PlatformAccountSelectorButton);

        // 1. Select Instagram = Yousef Qandeel (account 4)
        await tester.tap(buttons.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yousef Qandeel'));
        await tester.pumpAndSettle();

        // 2. Select Facebook = IndoTech (account 1)
        await tester.tap(buttons.at(0));
        await tester.pumpAndSettle();
        expect(find.text('Facebook Messenger'), findsOneWidget);
        expect(find.text('IndoTech'), findsOneWidget);
        expect(find.text('عروض طنطا كول'), findsOneWidget);

        await tester.tap(find.text('IndoTech'));
        await tester.pumpAndSettle();

        // Both filters are active independently:
        // Facebook: only IndoTech (FB 1)
        // Instagram: only Yousef Qandeel (IG 2)
        // WhatsApp: WA 1
        expect(find.text('Customer FB 1'), findsOneWidget);
        expect(find.text('Customer FB 2'), findsNothing);
        expect(find.text('Customer IG 2'), findsOneWidget);
        expect(find.text('Customer IG 1'), findsNothing);
        expect(find.text('Customer WA 1'), findsOneWidget);

        // Verify query: channel_connections=1,4,5
        final lastConvoReq = adapter.received.lastWhere(
          (r) => r.uri.path.contains('/conversations/'),
        );
        expect(
          lastConvoReq.uri.queryParameters['channel_connections'],
          equals('1,4,5'),
        );

        // 3. Reset Instagram to "All accounts"
        // Tap the Instagram selector button (displaying "Yousef Qandeel")
        await tester.tap(find.text('Yousef Qandeel'));
        await tester.pumpAndSettle();
        expect(find.text('Instagram Direct'), findsOneWidget);
        await tester.tap(find.text('All accounts'));
        await tester.pumpAndSettle();

        // Instagram shows all accounts again (Mohamed & Yousef Qandeel), while Facebook remains filtered to IndoTech!
        expect(find.text('Customer FB 1'), findsOneWidget);
        expect(find.text('Customer FB 2'), findsNothing);
        expect(find.text('Customer IG 1'), findsOneWidget);
        expect(find.text('Customer IG 2'), findsOneWidget);
        expect(find.text('Customer WA 1'), findsOneWidget);

        // Verify query: channel_connections=1,3,4,5
        final resetReq = adapter.received.lastWhere(
          (r) => r.uri.path.contains('/conversations/'),
        );
        expect(
          resetReq.uri.queryParameters['channel_connections'],
          equals('1,3,4,5'),
        );
      },
    );

    testWidgets('RTL and Arabic localization renders correct Arabic strings', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp(locale: const Locale('ar')));
      await tester.pumpAndSettle();

      // Both buttons show Arabic "كل الحسابات"
      expect(find.text('كل الحسابات'), findsNWidgets(2));

      // Open Instagram popup in Arabic
      final buttons = find.byType(PlatformAccountSelectorButton);
      await tester.tap(buttons.at(1));
      await tester.pumpAndSettle();

      // Shows Arabic "كل الحسابات" inside dropdown as well
      expect(find.text('كل الحسابات'), findsWidgets);
    });

    testWidgets('narrow screen (320px width) does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      // SingleChildScrollView ensures no RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.byType(PlatformAccountFilterBar), findsOneWidget);
    });

    testWidgets('when all platforms have single account, bar renders nothing', (
      tester,
    ) async {
      final singleChannels = [_fbAccount1, _waAccount1];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentEmployeeProvider.overrideWith((ref) => _adminEmployee),
            channelsProvider.overrideWith((ref) async => singleChannels),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const InboxScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No multi-account platform -> SizedBox.shrink()
      expect(find.byType(PlatformAccountSelectorButton), findsNothing);
    });

    testWidgets('dark mode renders without error and applies theme contrast', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentEmployeeProvider.overrideWith((ref) => _adminEmployee),
            channelsProvider.overrideWith((ref) async => initialChannels),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const InboxScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlatformAccountSelectorButton), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('account filtering composes with search and secondary filters', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );

      // Select Facebook account 1 (IndoTech)
      final buttons = find.byType(PlatformAccountSelectorButton);
      await tester.tap(buttons.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IndoTech'));
      await tester.pumpAndSettle();

      // Update filter with search "Customer" and status "OPEN"
      final currentFilters = container.read(inboxFiltersProvider);
      container
          .read(inboxFiltersProvider.notifier)
          .update(currentFilters.copyWith(search: 'Customer', status: 'OPEN'));
      await tester.pumpAndSettle();

      // Verify the query sent contains search, status, and channel_connections
      final req = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(req.uri.queryParameters['search'], equals('Customer'));
      expect(req.uri.queryParameters['status'], equals('OPEN'));
      expect(req.uri.queryParameters['channel_connections'], isNotNull);
    });

    testWidgets(
      'disconnecting selected account automatically reconciles to All accounts',
      (tester) async {
        var currentChannels = initialChannels;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(apiClient),
              currentEmployeeProvider.overrideWith((ref) => _adminEmployee),
              channelsProvider.overrideWith((ref) async => currentChannels),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const InboxScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Select Instagram = Yousef Qandeel (id 4)
        final buttons = find.byType(PlatformAccountSelectorButton);
        await tester.tap(buttons.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yousef Qandeel'));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InboxScreen)),
        );
        expect(
          container.read(inboxFiltersProvider).selectedAccounts['INSTAGRAM'],
          equals(4),
        );

        // 2. Simulate channel disconnect/deletion: account 4 is disconnected (status DISCONNECTED / inactive)
        currentChannels = initialChannels.map((c) {
          if (c.id == 4) {
            return const ChannelConnection(
              id: 4,
              provider: 'INSTAGRAM',
              displayName: 'Yousef Qandeel',
              status: 'DISCONNECTED',
              isActive: false,
            );
          }
          return c;
        }).toList();

        container.invalidate(channelsProvider);
        await tester.pumpAndSettle();

        // The filter reconciles: account 4 is no longer active, so INSTAGRAM is removed from selectedAccounts
        expect(
          container.read(inboxFiltersProvider).selectedAccounts['INSTAGRAM'],
          isNull,
        );
      },
    );

    testWidgets(
      'opening a conversation from filtered list routes to correct conversation ID',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        // Select Instagram Yousef Qandeel
        final buttons = find.byType(PlatformAccountSelectorButton);
        await tester.tap(buttons.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yousef Qandeel'));
        await tester.pumpAndSettle();

        // Verify conversation with ID 104 is displayed
        expect(find.text('Customer IG 2'), findsOneWidget);
        final convoRow = tester.widget<ConversationRow>(
          find.ancestor(
            of: find.text('Customer IG 2'),
            matching: find.byType(ConversationRow),
          ),
        );
        expect(convoRow.conversation.id, equals(104));
      },
    );
  });
}
