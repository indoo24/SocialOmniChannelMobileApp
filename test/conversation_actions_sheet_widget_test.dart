/// Tests for the comprehensive Actions Bottom Sheet containing:
/// 1. Customer Details DATA
/// 2. Intelligence DATA
/// 3. Orders DATA
/// 4. Conversation Actions
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_actions_sheet.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply, Perm.conversationChangeCategory},
  visibilityScope: 'ASSIGNED',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

ApiClient _clientFor({
  FutureOr<ResponseBody>? Function(RequestOptions options)? extra,
}) {
  return _stubClient((options) {
    final fromExtra = extra?.call(options);
    if (fromExtra != null) return fromExtra;
    if (options.path.endsWith('/conversations/1/')) {
      return _json('''{
          "id": 1,
          "customer": {
            "id": 1,
            "display_name": "Sarah Connor",
            "initials": "SC",
            "phone": "+123456789",
            "email": "sarah@example.com",
            "country": "USA",
            "city": "Los Angeles"
          },
          "provider": "WHATSAPP",
          "channel_name": "Support Line",
          "status": "OPEN",
          "priority": "NORMAL",
          "unread_count": 0,
          "message_count": 5
        }''', 200);
    }
    if (options.path.contains('/messages/')) {
      return _json('{"results": [], "count": 0}', 200);
    }
    if (options.path.contains('/intelligence/')) {
      return _json('''{
          "stage": "CONSIDERING",
          "confidence": 0.85,
          "purchase_status": "NONE",
          "purchase_evidence": "",
          "purchase_intent": "HIGH",
          "intent_strength": "STRONG",
          "urgency": "high",
          "sentiment": "positive",
          "interested_products": ["Widget Pro", "Accessories"],
          "objections": ["Price hesitation"],
          "buying_signals": ["Asked about delivery"],
          "quantity_signal": "2",
          "summary": "Customer interested in buying 2 units of Widget Pro.",
          "next_best_action": "Send checkout link",
          "lead_score": 85,
          "lead_score_signals": [],
          "lead_score_auto": 85,
          "lead_score_override": null,
          "is_lead_score_overridden": false,
          "lead_score_overridden_by_name": "",
          "lead_score_overridden_at": null,
          "needs_human_review": false,
          "review_reason": "",
          "is_purchase_claim_pending": false,
          "is_agent_confirmed": false,
          "confirmed_by_name": "",
          "purchase_confirmed_at": null,
          "purchase_confirmation_note": "",
          "analysis_version": "1.0",
          "analyzer_key": "v1",
          "analyzed_at": "2026-09-02T12:00:00Z"
        }''', 200);
    }
    if (options.path.contains('/orders')) {
      return _json('''{
          "count": 1,
          "next": null,
          "previous": null,
          "results": [
            {
              "id": 99,
              "customer": 1,
              "conversation": 1,
              "status": "CONFIRMED",
              "status_display": "Confirmed",
              "source": "AGENT",
              "is_claim": false,
              "total_amount": "250.00",
              "currency": "USD",
              "items": [
                {
                  "id": 1,
                  "product_name": "Widget Pro",
                  "quantity": 2,
                  "unit_price": "125.00",
                  "line_total": "250.00"
                }
              ],
              "recorded_by_name": "Sam Agent",
              "confirmed_by_name": "Sam Agent",
              "evidence": "",
              "note": ""
            }
          ]
        }''', 200);
    }
    if (options.path.contains('/facts')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/conversions')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/events')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/notes')) {
      return _json('[]', 200);
    }
    return _json('{}', 200);
  });
}

Widget _harness({required ApiClient apiClient, required Widget child}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () => showConversationActionsSheet(context, conversationId: 1),
  child: const Text('open actions'),
);

void main() {
  testWidgets(
    'Actions bottom sheet renders Customer details data, Orders data, Intelligence data, and Actions',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );

      await tester.tap(find.text('open actions'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // 1. Customer Details DATA is rendered
      expect(find.text('Customer details'), findsOneWidget);
      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('+123456789'), findsOneWidget);
      expect(find.text('sarah@example.com'), findsOneWidget);

      // 2. Intelligence DATA is rendered
      expect(find.text('Intelligence'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(
        find.text('Customer interested in buying 2 units of Widget Pro.'),
        findsOneWidget,
      );
      expect(find.text('Widget Pro'), findsOneWidget);
      expect(find.text('Price hesitation'), findsOneWidget);

      // 3. Orders DATA is rendered (scroll down)
      await tester.scrollUntilVisible(
        find.text('Orders'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Order #99'), findsOneWidget);
      expect(find.text('250.00 USD'), findsOneWidget);

      // 4. Actions are rendered and functional (scroll down)
      await tester.scrollUntilVisible(
        find.text('Actions'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Actions'), findsOneWidget);
      expect(find.text('View history'), findsOneWidget);
      expect(find.text('Internal notes'), findsOneWidget);
      expect(find.text('Conversions'), findsOneWidget);
    },
  );

  testWidgets(
    'opening the real Actions sheet and tapping Conversions opens conversions sheet',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open actions'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Scroll to Conversions tile and tap it
      await tester.scrollUntilVisible(
        find.text('Conversions'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(find.text('Conversions'), findsOneWidget);

      await tester.tap(find.text('Conversions'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Nothing reported to Meta yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'opening and closing the real Actions sheet repeatedly does not throw',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('open actions'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(find.text('open actions'))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'ConversationScreen AppBar 3-dot button opens comprehensive actions sheet with data',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3-dot actions button exists
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // Tapping 3-dot actions button opens comprehensive sheet
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Verify data sections are rendered
      expect(find.text('Customer details'), findsOneWidget);
      expect(find.text('Sarah Connor'), findsNWidgets(2));
      expect(find.text('Intelligence'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Orders'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Orders'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Actions'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Actions'), findsOneWidget);
    },
  );
}
