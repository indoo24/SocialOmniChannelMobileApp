/// Tests for Dashboard Recent Activity section:
/// - Parsing of `recent_conversations` from `GET /api/dashboard/` response
/// - Null safety / missing optional fields handling
/// - Rendering of the Recent Activity section in `DashboardScreen`
/// - Navigation to `/inbox` via "Open inbox"
/// - Navigation to `/inbox/:id` via conversation item tap
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/dashboard/dashboard_screen.dart';
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

const _sampleDashboardWithRecentJson = '''
{
  "conversations": {
    "open": 5, "new": 2, "unassigned": 1, "waiting": 1,
    "resolved_today": 3, "unread": 2, "mine_open": 2
  },
  "intelligence": {
    "qualified_leads": 4, "hot_leads": 1, "purchase_claims": 2,
    "agent_confirmed_purchases": 1, "confirmed_today": 1,
    "pending_review": 0, "average_lead_score": 82.5
  },
  "team": {
    "online_agents": 3,
    "workload": []
  },
  "recent_conversations": [
    {
      "id": 42,
      "customer": {
        "id": 101,
        "display_name": "Sarah Connor",
        "avatar_url": "",
        "lifecycle_stage": "LEAD",
        "preferred_language": "en",
        "email": "sarah@cyberdyne.test",
        "phone": "+1234567890",
        "country": "US",
        "city": "Los Angeles"
      },
      "provider": "WHATSAPP",
      "channel_name": "WhatsApp Support",
      "channel_id": 1,
      "assigned_to": {
        "id": 1,
        "full_name": "Sam Self",
        "initials": "SS",
        "email": "sam@acme.test",
        "role": "ADMIN"
      },
      "assigned_team": {
        "id": 2,
        "name": "Support VIP",
        "color": "#0F766E"
      },
      "status": "OPEN",
      "priority": "HIGH",
      "category": {
        "id": 3,
        "label": "Billing",
        "slug": "billing",
        "color": "#F59E0B"
      },
      "unread_count": 2,
      "message_count": 5,
      "last_message_preview": "Can you check my payment?",
      "last_message_at": "2026-08-30T10:00:00Z",
      "started_at": "2026-08-30T09:00:00Z",
      "intelligence": {
        "stage": "PURCHASE_INTENT",
        "lead_score": 88,
        "purchase_status": "CLAIMED",
        "needs_human_review": false
      },
      "is_follow_up": true,
      "follow_up_date": "2026-09-05T00:00:00Z",
      "follow_up_marked_at": "2026-08-30T10:00:00Z",
      "follow_up_marked_by_name": "Sam Self"
    }
  ]
}
''';

const _sampleDashboardEmptyRecentJson = '''
{
  "conversations": {
    "open": 0, "new": 0, "unassigned": 0, "waiting": 0,
    "resolved_today": 0, "unread": 0, "mine_open": 0
  },
  "intelligence": {
    "qualified_leads": 0, "hot_leads": 0, "purchase_claims": 0,
    "agent_confirmed_purchases": 0, "confirmed_today": 0,
    "pending_review": 0, "average_lead_score": 0.0
  },
  "recent_conversations": []
}
''';

Employee _employee() => const Employee(
  id: 1,
  email: 'sam@acme.test',
  fullName: 'Sam Self',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {Perm.conversationView},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

Widget _dashboardHarness({
  required ApiClient apiClient,
  GoRouter? customRouter,
}) {
  final router =
      customRouter ??
      GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/inbox',
            builder: (_, _) => const Scaffold(body: Text('INBOX_SCREEN')),
          ),
          GoRoute(
            path: '/inbox/:id',
            builder: (context, state) => Scaffold(
              body: Text('CONVERSATION_SCREEN_${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee()),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
    ),
  );
}

void main() {
  group('DashboardSummary.fromJson — recent_conversations parsing', () {
    test(
      'parses full recent_conversations list with customer and intelligence',
      () {
        final summary = DashboardSummary.fromJson({
          'conversations': {
            'open': 1,
            'new': 0,
            'unassigned': 0,
            'waiting': 0,
            'resolved_today': 0,
            'unread': 0,
            'mine_open': 1,
          },
          'intelligence': {
            'qualified_leads': 0,
            'hot_leads': 0,
            'purchase_claims': 0,
            'agent_confirmed_purchases': 0,
            'confirmed_today': 0,
            'pending_review': 0,
            'average_lead_score': 0,
          },
          'recent_conversations': [
            {
              'id': 12,
              'customer': {
                'id': 50,
                'display_name': 'Alice Wonder',
                'avatar_url': 'https://example.com/alice.png',
                'lifecycle_stage': 'CUSTOMER',
                'preferred_language': 'ar',
                'email': 'alice@example.com',
                'phone': '+966500000000',
                'country': 'SA',
                'city': 'Riyadh',
              },
              'provider': 'WHATSAPP',
              'channel_name': 'Support WA',
              'channel_id': 99,
              'status': 'OPEN',
              'priority': 'HIGH',
              'unread_count': 3,
              'message_count': 10,
              'last_message_preview': 'Hello there!',
              'last_message_at': '2026-08-30T12:00:00Z',
              'started_at': '2026-08-30T11:00:00Z',
              'is_follow_up': true,
              'follow_up_date': '2026-09-01T00:00:00Z',
              'follow_up_marked_at': '2026-08-30T12:00:00Z',
              'follow_up_marked_by_name': 'Agent Smith',
            },
          ],
        });

        expect(summary.recentConversations.length, 1);
        final c = summary.recentConversations.first;
        expect(c.id, 12);
        expect(c.customer.displayName, 'Alice Wonder');
        expect(c.customer.email, 'alice@example.com');
        expect(c.customer.phone, '+966500000000');
        expect(c.customer.country, 'SA');
        expect(c.customer.city, 'Riyadh');
        expect(c.provider, 'WHATSAPP');
        expect(c.channelId, 99);
        expect(c.status, 'OPEN');
        expect(c.priority, 'HIGH');
        expect(c.unreadCount, 3);
        expect(c.hasUnread, isTrue);
        expect(c.lastMessagePreview, 'Hello there!');
        expect(c.isFollowUp, isTrue);
        expect(c.followUpMarkedByName, 'Agent Smith');
      },
    );

    test('handles missing or empty recent_conversations gracefully', () {
      final summary = DashboardSummary.fromJson({
        'conversations': {
          'open': 0,
          'new': 0,
          'unassigned': 0,
          'waiting': 0,
          'resolved_today': 0,
          'unread': 0,
          'mine_open': 0,
        },
        'intelligence': {
          'qualified_leads': 0,
          'hot_leads': 0,
          'purchase_claims': 0,
          'agent_confirmed_purchases': 0,
          'confirmed_today': 0,
          'pending_review': 0,
          'average_lead_score': 0,
        },
      });

      expect(summary.recentConversations, isEmpty);
    });

    test(
      'handles null/missing optional fields inside conversation items safely',
      () {
        final summary = DashboardSummary.fromJson({
          'conversations': {
            'open': 0,
            'new': 0,
            'unassigned': 0,
            'waiting': 0,
            'resolved_today': 0,
            'unread': 0,
            'mine_open': 0,
          },
          'intelligence': {
            'qualified_leads': 0,
            'hot_leads': 0,
            'purchase_claims': 0,
            'agent_confirmed_purchases': 0,
            'confirmed_today': 0,
            'pending_review': 0,
            'average_lead_score': 0,
          },
          'recent_conversations': [
            {
              'id': 77,
              'customer': null,
              'provider': null,
              'status': null,
              'priority': null,
              'assigned_to': null,
              'assigned_team': null,
              'category': null,
              'intelligence': null,
              'last_message_at': null,
              'started_at': null,
              'follow_up_date': null,
            },
          ],
        });

        expect(summary.recentConversations.length, 1);
        final c = summary.recentConversations.first;
        expect(c.id, 77);
        expect(c.customer.displayName, 'Unknown Customer');
        expect(c.provider, 'MOCK');
        expect(c.status, 'NEW');
        expect(c.priority, 'NORMAL');
        expect(c.assignedTo, isNull);
        expect(c.assignedTeam, isNull);
        expect(c.category, isNull);
        expect(c.intelligence, isNull);
        expect(c.lastMessageAt, isNull);
        expect(c.isFollowUp, isFalse);
      },
    );
  });

  group('DashboardScreen — Recent Activity Widget', () {
    testWidgets('renders Recent Activity section with conversations', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path == '/dashboard/') {
          return _json(_sampleDashboardWithRecentJson, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_dashboardHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Verify section heading and "Open inbox" action
      await tester.dragUntilVisible(
        find.text('Recent activity'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Open inbox'), findsOneWidget);

      // Verify conversation content
      await tester.dragUntilVisible(
        find.text('Sarah Connor'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('Can you check my payment?'), findsOneWidget);
      expect(
        find.text('Purchase intent'),
        findsOneWidget,
      ); // Intelligence stage badge
      expect(find.text('2'), findsWidgets); // Unread pill count
    });

    testWidgets(
      'renders different intelligence stages (New lead, Qualified lead, Hot lead)',
      (tester) async {
        const customDashboardJson = '''
{
  "conversations": { "open": 3, "new": 0, "unassigned": 0, "waiting": 0, "resolved_today": 0, "unread": 0, "mine_open": 0 },
  "intelligence": { "qualified_leads": 0, "hot_leads": 0, "purchase_claims": 0, "agent_confirmed_purchases": 0, "confirmed_today": 0, "pending_review": 0, "average_lead_score": 0.0 },
  "recent_conversations": [
    {
      "id": 1,
      "customer": { "id": 1, "display_name": "Lead One", "avatar_url": "" },
      "provider": "WHATSAPP",
      "status": "OPEN",
      "priority": "NORMAL",
      "unread_count": 0,
      "message_count": 1,
      "intelligence": { "stage": "NEW_LEAD", "lead_score": 40, "purchase_status": "", "needs_human_review": false }
    },
    {
      "id": 2,
      "customer": { "id": 2, "display_name": "Lead Two", "avatar_url": "" },
      "provider": "WHATSAPP",
      "status": "OPEN",
      "priority": "NORMAL",
      "unread_count": 0,
      "message_count": 1,
      "intelligence": { "stage": "QUALIFIED_LEAD", "lead_score": 75, "purchase_status": "", "needs_human_review": false }
    },
    {
      "id": 3,
      "customer": { "id": 3, "display_name": "Lead Three", "avatar_url": "" },
      "provider": "WHATSAPP",
      "status": "OPEN",
      "priority": "NORMAL",
      "unread_count": 0,
      "message_count": 1,
      "intelligence": { "stage": "HOT_LEAD", "lead_score": 95, "purchase_status": "", "needs_human_review": false }
    }
  ]
}
''';
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path == '/dashboard/') {
            return _json(customDashboardJson, 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_dashboardHarness(apiClient: client));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Lead One'),
          find.byType(ListView),
          const Offset(0, -300),
        );
        expect(find.text('New lead'), findsOneWidget);
        expect(find.text('Qualified lead'), findsOneWidget);
        expect(find.text('Hot lead'), findsOneWidget);
      },
    );

    testWidgets('tapping Open inbox navigates to /inbox', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path == '/dashboard/') {
          return _json(_sampleDashboardWithRecentJson, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_dashboardHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Open inbox'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Open inbox'));
      await tester.pumpAndSettle();

      expect(find.text('INBOX_SCREEN'), findsOneWidget);
    });

    testWidgets('tapping a conversation row navigates to /inbox/:id', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        if (options.path == '/dashboard/') {
          return _json(_sampleDashboardWithRecentJson, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_dashboardHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Sarah Connor'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Sarah Connor'));
      await tester.pumpAndSettle();

      expect(find.text('CONVERSATION_SCREEN_42'), findsOneWidget);
    });

    testWidgets(
      'shows empty state message when recent_conversations is empty',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path == '/dashboard/') {
            return _json(_sampleDashboardEmptyRecentJson, 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(_dashboardHarness(apiClient: client));
        await tester.pumpAndSettle();

        expect(find.text('Recent activity'), findsOneWidget);
        expect(find.text('No recent activity yet.'), findsOneWidget);
      },
    );
  });
}
