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

String _conversation({
  required int id,
  required String name,
  int unreadCount = 0,
  Map<String, dynamic>? assignedTo,
  int channelId = 1,
}) {
  final assignedJson = assignedTo == null
      ? 'null'
      : '{"id": ${assignedTo['id']}, "full_name": "${assignedTo['full_name']}"}';
  return '''
{
  "id": $id,
  "customer": {"id": $id, "display_name": "$name"},
  "provider": "FACEBOOK",
  "channel_id": $channelId,
  "channel_name": "IndoTech",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": $unreadCount,
  "message_count": 1,
  "assigned_to": $assignedJson
}
''';
}

const _idUnreadUnassigned = 201;
const _idUnreadAssigned = 202;
const _idReadUnassigned = 203;
const _idReadAssigned = 204;

final _unreadUnassigned = _conversation(
  id: _idUnreadUnassigned,
  name: 'Unread Unassigned',
  unreadCount: 2,
);
final _unreadAssigned = _conversation(
  id: _idUnreadAssigned,
  name: 'Unread Assigned',
  unreadCount: 3,
  assignedTo: {'id': 9, 'full_name': 'Mohamed'},
);
final _readUnassigned = _conversation(
  id: _idReadUnassigned,
  name: 'Read Unassigned',
);
final _readAssigned = _conversation(
  id: _idReadAssigned,
  name: 'Read Assigned',
  assignedTo: {'id': 10, 'full_name': 'Ahmed'},
);

final _allConversations = {
  _idUnreadUnassigned: _unreadUnassigned,
  _idUnreadAssigned: _unreadAssigned,
  _idReadUnassigned: _readUnassigned,
  _idReadAssigned: _readAssigned,
};

const _unreadIds = {_idUnreadUnassigned, _idUnreadAssigned};
const _unassignedIds = {_idUnreadUnassigned, _idReadUnassigned};

String _page(List<String> results, {bool hasNext = false, int? count}) =>
    '{"count": ${count ?? results.length}, "next": ${hasNext ? '"http://x/?page=2"' : 'null'}, "previous": null, "results": [${results.join(',')}]}';

void main() {
  group('ConversationFilters unread/unassigned query building', () {
    test('unread=false and unassigned=false send neither param', () {
      const filters = ConversationFilters();
      final query = filters.toQuery(1, null);
      expect(query.containsKey('unread'), isFalse);
      expect(query.containsKey('view'), isFalse);
      expect(query.containsKey('assigned_to__isnull'), isFalse);
    });

    test('unread=true sends the documented boolean `unread` param', () {
      const filters = ConversationFilters(unread: true);
      final query = filters.toQuery(1, null);
      expect(query['unread'], isTrue);
    });

    test(
      'unassigned=true sends view=unassigned, never the undocumented assigned_to__isnull',
      () {
        const filters = ConversationFilters(unassigned: true);
        final query = filters.toQuery(1, null);
        expect(query['view'], equals('unassigned'));
        expect(query.containsKey('assigned_to__isnull'), isFalse);
      },
    );

    test('unread and unassigned compose with each other and other filters', () {
      const filters = ConversationFilters(
        unread: true,
        unassigned: true,
        status: 'OPEN',
        search: 'Ahmed',
      );
      final query = filters.toQuery(1, 42);
      expect(query['unread'], isTrue);
      expect(query['view'], equals('unassigned'));
      expect(query['status'], equals('OPEN'));
      expect(query['search'], equals('Ahmed'));
      // assignedToMe defaults to false, so no assigned_to param leaks in.
      expect(query.containsKey('assigned_to'), isFalse);
    });

    test('assignedToMe and unread compose (assigned_to + unread)', () {
      const filters = ConversationFilters(assignedToMe: true, unread: true);
      final query = filters.toQuery(1, 42);
      expect(query['assigned_to'], equals(42));
      expect(query['unread'], isTrue);
    });

    test('hasSheetFilters and isEmpty account for unread', () {
      const base = ConversationFilters();
      expect(base.hasSheetFilters, isFalse);
      expect(base.isEmpty, isTrue);

      const withUnread = ConversationFilters(unread: true);
      expect(withUnread.hasSheetFilters, isTrue);
      expect(withUnread.isEmpty, isFalse);
    });

    test('copyWith updates unread independently of other fields', () {
      const base = ConversationFilters(status: 'OPEN', unassigned: true);
      final updated = base.copyWith(unread: true);
      expect(updated.unread, isTrue);
      expect(updated.status, equals('OPEN'));
      expect(updated.unassigned, isTrue);
    });

    test('equality and hashCode include unread', () {
      const f1 = ConversationFilters(unread: true);
      const f2 = ConversationFilters(unread: true);
      const f3 = ConversationFilters(unread: false);
      expect(f1, equals(f2));
      expect(f1.hashCode, equals(f2.hashCode));
      expect(f1 == f3, isFalse);
    });
  });

  group('Inbox Unread & Unassigned filter widget/flow tests', () {
    late _StubAdapter adapter;
    late ApiClient apiClient;

    final channels = [_fbAccount1];

    setUp(() {
      adapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/conversations/counts/')) {
          return _json('{"open": 4, "unassigned": 2, "unread": 2}', 200);
        }
        if (path.contains('/conversations/')) {
          final qp = options.uri.queryParameters;
          final unread = qp['unread'] == 'true';
          final unassigned = qp['view'] == 'unassigned';

          final ids = _allConversations.keys.where((id) {
            if (unread && !_unreadIds.contains(id)) return false;
            if (unassigned && !_unassignedIds.contains(id)) return false;
            return true;
          });
          final results = ids.map((id) => _allConversations[id]!).toList();

          return _json(_page(results), 200);
        }
        if (path.contains('/channels/')) {
          return _json(
            '{"count": 1, "next": null, "previous": null, "results": ['
            '{"id": 1, "provider": "FACEBOOK", "provider_display": "Facebook Messenger", "display_name": "IndoTech", "status": "CONNECTED", "is_active": true}'
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
          channelsProvider.overrideWith((ref) async => channels),
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
      'Unread and Unassigned quick filter pills exist on the inbox screen',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quick_filter_unread')), findsOneWidget);
        expect(
          find.byKey(const Key('quick_filter_unassigned')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('quick_filter_all')), findsOneWidget);
        expect(find.byKey(const Key('quick_filter_mine')), findsOneWidget);
        expect(find.byKey(const Key('quick_filter_open')), findsOneWidget);
      },
    );

    testWidgets('selecting Unread shows only unread conversations', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      expect(find.text('Unread Unassigned'), findsOneWidget);
      expect(find.text('Unread Assigned'), findsOneWidget);
      expect(find.text('Read Unassigned'), findsOneWidget);
      expect(find.text('Read Assigned'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();

      expect(find.text('Unread Unassigned'), findsOneWidget);
      expect(find.text('Unread Assigned'), findsOneWidget);
      expect(find.text('Read Unassigned'), findsNothing);
      expect(find.text('Read Assigned'), findsNothing);

      final lastConvoReq = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(lastConvoReq.uri.queryParameters['unread'], equals('true'));
      expect(lastConvoReq.uri.queryParameters['page'], equals('1'));
    });

    testWidgets(
      'clearing Unread restores the full inbox (existing behavior preserved)',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('quick_filter_unread')));
        await tester.pumpAndSettle();

        expect(find.text('Read Unassigned'), findsNothing);

        await tester.tap(find.byKey(const Key('quick_filter_all')));
        await tester.pumpAndSettle();

        expect(find.text('Unread Unassigned'), findsOneWidget);
        expect(find.text('Unread Assigned'), findsOneWidget);
        expect(find.text('Read Unassigned'), findsOneWidget);
        expect(find.text('Read Assigned'), findsOneWidget);
      },
    );

    testWidgets(
      'selecting Unassigned excludes assigned conversations (regression for the fix)',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('quick_filter_unassigned')));
        await tester.pumpAndSettle();

        // Only genuinely unassigned conversations remain.
        expect(find.text('Unread Unassigned'), findsOneWidget);
        expect(find.text('Read Unassigned'), findsOneWidget);
        // Assigned conversations (to Mohamed / Ahmed) must NOT appear.
        expect(find.text('Unread Assigned'), findsNothing);
        expect(find.text('Read Assigned'), findsNothing);

        final lastConvoReq = adapter.received.lastWhere(
          (r) =>
              r.uri.path.contains('/conversations/') &&
              !r.uri.path.contains('/counts/'),
        );
        expect(lastConvoReq.uri.queryParameters['view'], equals('unassigned'));
        expect(
          lastConvoReq.uri.queryParameters.containsKey('assigned_to__isnull'),
          isFalse,
        );
      },
    );

    testWidgets('Unread + Unassigned combine via filter update', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      container
          .read(inboxFiltersProvider.notifier)
          .update(const ConversationFilters(unread: true, unassigned: true));
      await tester.pumpAndSettle();

      // Only the one conversation satisfying BOTH conditions.
      expect(find.text('Unread Unassigned'), findsOneWidget);
      expect(find.text('Unread Assigned'), findsNothing);
      expect(find.text('Read Unassigned'), findsNothing);
      expect(find.text('Read Assigned'), findsNothing);

      final lastConvoReq = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(lastConvoReq.uri.queryParameters['unread'], equals('true'));
      expect(lastConvoReq.uri.queryParameters['view'], equals('unassigned'));
    });

    testWidgets(
      'Unassigned and "Mine" remain mutually exclusive in quick filters',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InboxScreen)),
        );

        await tester.tap(find.byKey(const Key('quick_filter_mine')));
        await tester.pumpAndSettle();
        expect(container.read(inboxFiltersProvider).assignedToMe, isTrue);

        await tester.tap(find.byKey(const Key('quick_filter_unassigned')));
        await tester.pumpAndSettle();
        expect(container.read(inboxFiltersProvider).unassigned, isTrue);
        expect(container.read(inboxFiltersProvider).assignedToMe, isFalse);

        await tester.tap(find.byKey(const Key('quick_filter_mine')));
        await tester.pumpAndSettle();
        expect(container.read(inboxFiltersProvider).assignedToMe, isTrue);
        expect(container.read(inboxFiltersProvider).unassigned, isFalse);

        // Unread is untouched by this exclusivity — it can be combined orthogonally.
        container
            .read(inboxFiltersProvider.notifier)
            .update(
              container.read(inboxFiltersProvider).copyWith(unread: true),
            );
        await tester.pumpAndSettle();
        expect(container.read(inboxFiltersProvider).unread, isTrue);
        expect(container.read(inboxFiltersProvider).assignedToMe, isTrue);
      },
    );

    testWidgets('Clear all resets Unread and Unassigned together', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );

      container
          .read(inboxFiltersProvider.notifier)
          .update(const ConversationFilters(unread: true, unassigned: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      final filters = container.read(inboxFiltersProvider);
      expect(filters.unread, isFalse);
      expect(filters.unassigned, isFalse);
    });

    testWidgets('Unread composes with search', (tester) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      final current = container.read(inboxFiltersProvider);
      container
          .read(inboxFiltersProvider.notifier)
          .update(current.copyWith(unread: true, search: 'Ahmed'));
      await tester.pumpAndSettle();

      final lastConvoReq = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(lastConvoReq.uri.queryParameters['unread'], equals('true'));
      expect(lastConvoReq.uri.queryParameters['search'], equals('Ahmed'));
    });

    testWidgets('Unread composes with channel_connections (account filter)', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      final current = container.read(inboxFiltersProvider);
      container
          .read(inboxFiltersProvider.notifier)
          .update(
            current.copyWith(unread: true, channelConnections: const [1]),
          );
      await tester.pumpAndSettle();

      final lastConvoReq = adapter.received.lastWhere(
        (r) =>
            r.uri.path.contains('/conversations/') &&
            !r.uri.path.contains('/counts/'),
      );
      expect(lastConvoReq.uri.queryParameters['unread'], equals('true'));
      expect(
        lastConvoReq.uri.queryParameters['channel_connections'],
        equals('1'),
      );
    });

    testWidgets(
      'selecting Unread resets pagination to page 1 (no stale page 2+ merge)',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(InboxScreen)),
        );

        // Confirm state starts on a fresh first page.
        final initialState = container.read(inboxControllerProvider).value!;
        expect(initialState.nextPage, equals(2));

        container
            .read(inboxFiltersProvider.notifier)
            .update(const ConversationFilters(unread: true));
        await tester.pumpAndSettle();

        final refreshedState = container.read(inboxControllerProvider).value!;
        expect(refreshedState.nextPage, equals(2));

        final lastConvoReq = adapter.received.lastWhere(
          (r) =>
              r.uri.path.contains('/conversations/') &&
              !r.uri.path.contains('/counts/'),
        );
        expect(lastConvoReq.uri.queryParameters['page'], equals('1'));
      },
    );

    testWidgets('No unread conversations shows the existing empty state', (
      tester,
    ) async {
      adapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/conversations/counts/')) {
          return _json('{"open": 4, "unassigned": 0, "unread": 0}', 200);
        }
        if (path.contains('/conversations/')) {
          final unread = options.uri.queryParameters['unread'] == 'true';
          return _json(_page(unread ? [] : [_readAssigned]), 200);
        }
        if (path.contains('/channels/')) {
          return _json(
            '{"count": 1, "next": null, "previous": null, "results": ['
            '{"id": 1, "provider": "FACEBOOK", "provider_display": "Facebook Messenger", "display_name": "IndoTech", "status": "CONNECTED", "is_active": true}'
            ']}',
            200,
          );
        }
        return _json('{}', 200);
      });
      apiClient.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches those filters'), findsOneWidget);
      expect(
        find.text('Try widening or clearing the filters.'),
        findsOneWidget,
      );
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('RTL/Arabic renders the Unread and Unassigned chip labels', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp(locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.text('غير مقروءة'), findsOneWidget);
      expect(find.text('غير مُسندة'), findsOneWidget);
    });

    testWidgets('dark mode renders the filter sheet without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(apiClient),
            currentEmployeeProvider.overrideWith((ref) => _adminEmployee),
            channelsProvider.overrideWith((ref) async => channels),
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

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.text('Filters'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow screen (320px width) does not overflow the sheet', (
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

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Filters'), findsOneWidget);
    });
  });
}
