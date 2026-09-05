/// Regression tests for the new-order confirmation UI in the Conversation
/// Actions Sheet's Orders section: a pending (`RECORDED`, `is_claim: true`)
/// order shows who recorded it, the "not counted as a sale" explanation, a
/// Confirm button, and a delete/cancel action — matching the web card.
///
/// Endpoints used, verified against the live OpenAPI schema (not guessed):
///   POST /orders/{id}/confirm/  — DirectoryRepository.confirmOrder()
///   POST /orders/{id}/cancel/   — DirectoryRepository.cancelOrder()
/// `DELETE /orders/{id}/` also exists in Swagger, but the web's trash icon on
/// a pending order is assumed (per product decision, since the web source is
/// not inspectable from here) to be the existing cancel workflow already
/// wired in this app — this suite exercises that assumption, not `DELETE`.
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

Employee _employee({Set<String> permissions = const {Perm.orderManage}}) =>
    Employee(
      id: 1,
      email: 'agent@acme.test',
      fullName: 'Sam Agent',
      initials: 'SA',
      role: 'AGENT',
      roleDisplay: 'Agent',
      availability: 'ONLINE',
      permissions: permissions,
      visibilityScope: 'ALL',
      organization: const Organization(id: 1, name: 'Acme Retail'),
    );

const _conversationDetail = '''
{
  "id": 1,
  "customer": {
    "id": 42,
    "display_name": "Sarah Connor",
    "initials": "SC",
    "phone": "+123456789"
  },
  "provider": "WHATSAPP",
  "channel_name": "Sales Line",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 0
}
''';

/// A single RECORDED (pending confirmation) order — the state the web
/// screenshot's card is in immediately after a new order is created.
String _pendingOrderJson({
  int id = 201,
  String recordedBy = 'Sam Agent',
  String productName = 'ffff',
  int quantity = 1,
  String unitPrice = '20.00',
  String total = '20.00',
}) =>
    '''
{
  "id": $id,
  "customer": 42,
  "conversation": 1,
  "status": "RECORDED",
  "status_display": "Recorded",
  "source": "EMPLOYEE",
  "is_claim": true,
  "total_amount": "$total",
  "currency": "EGP",
  "items": [
    {
      "id": 1,
      "product_name": "$productName",
      "quantity": $quantity,
      "unit_price": "$unitPrice",
      "line_total": "$total"
    }
  ],
  "recorded_by_name": "$recordedBy",
  "confirmed_by_name": "",
  "evidence": "",
  "note": ""
}
''';

const _confirmedOrderJson = '''
{
  "id": 202,
  "customer": 42,
  "conversation": 1,
  "status": "CONFIRMED",
  "status_display": "Confirmed",
  "source": "EMPLOYEE",
  "is_claim": false,
  "total_amount": "50.00",
  "currency": "EGP",
  "items": [
    {
      "id": 2,
      "product_name": "bbb",
      "quantity": 1,
      "unit_price": "50.00",
      "line_total": "50.00"
    }
  ],
  "recorded_by_name": "Sam Agent",
  "confirmed_by_name": "Jordan Lead",
  "evidence": "",
  "note": ""
}
''';

const _cancelledOrderJson = '''
{
  "id": 203,
  "customer": 42,
  "conversation": 1,
  "status": "CANCELLED",
  "status_display": "Cancelled",
  "source": "EMPLOYEE",
  "is_claim": false,
  "total_amount": "30.00",
  "currency": "EGP",
  "items": [
    {
      "id": 3,
      "product_name": "ccc",
      "quantity": 1,
      "unit_price": "30.00",
      "line_total": "30.00"
    }
  ],
  "recorded_by_name": "Sam Agent",
  "confirmed_by_name": "",
  "evidence": "",
  "note": ""
}
''';

_StubAdapter _adapterFor(
  String ordersBody, {
  FutureOr<ResponseBody>? Function(RequestOptions options)? extra,
}) {
  return _StubAdapter((options) {
    final fromExtra = extra?.call(options);
    if (fromExtra != null) return fromExtra;

    if (options.path.contains('/orders/') &&
        options.method == 'GET' &&
        !options.path.contains('/confirm') &&
        !options.path.contains('/cancel')) {
      return _json(ordersBody, 200);
    }
    if (options.path.endsWith('/conversations/1/')) {
      return _json(_conversationDetail, 200);
    }
    if (options.path.contains('/facts/')) return _json('[]', 200);
    if (options.path.contains('/intelligence/')) return _json('{}', 200);
    if (options.path.contains('/categories/')) return _json('[]', 200);
    if (options.path.contains('/messages/')) {
      return _json('{"results": [], "count": 0}', 200);
    }
    return _json('{}', 200);
  });
}

ApiClient _clientWith(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Future<void> _openOrdersSheet(
  WidgetTester tester,
  ApiClient client, {
  Employee? employee,
}) async {
  // A tall viewport so the sheet's DraggableScrollableSheet has room to
  // actually reveal the order card's action row — the default 800x600 test
  // window leaves it below the fold with no further scroll room once the
  // sheet itself is already at its max child size.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showConversationActionsSheet(context, conversationId: 1),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();

  await tester.scrollUntilVisible(
    find.text('Orders'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
}

void main() {
  group('Newly created pending order', () {
    testWidgets(
      'renders total, product line, recorded-by, pending text, Confirm and '
      'delete',
      (tester) async {
        final client = _clientWith(
          _adapterFor('''
        {"count": 1, "results": [${_pendingOrderJson()}]}
        '''),
        );

        await _openOrdersSheet(tester, client);

        expect(find.text('20.00 EGP'), findsOneWidget);
        expect(find.text('1× ffff'), findsOneWidget);
        expect(find.text('Recorded by Sam Agent'), findsOneWidget);
        expect(
          find.text("Not counted as a sale until someone confirms it."),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      },
    );

    testWidgets('recorded-by is omitted when the backend sends no name', (
      tester,
    ) async {
      final client = _clientWith(
        _adapterFor('''
      {"count": 1, "results": [${_pendingOrderJson(recordedBy: "")}]}
      '''),
      );

      await _openOrdersSheet(tester, client);

      expect(find.textContaining('Recorded by'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsOneWidget);
    });
  });

  group('Confirm button', () {
    testWidgets(
      'calls POST /orders/{id}/confirm/, shows loading, refreshes on success',
      (tester) async {
        var confirmCalls = 0;
        // Gated so the loading state has a real window to assert on — an
        // adapter that resolves instantly would clear _busy before the next
        // pump() ever observes it.
        final confirmGate = Completer<void>();
        final adapter = _adapterFor(
          '{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}',
          extra: (options) {
            if (options.path == '/orders/201/confirm/' &&
                options.method == 'POST') {
              confirmCalls++;
              return confirmGate.future.then(
                (_) => _json(_confirmedOrderJson, 200),
              );
            }
            return null;
          },
        );
        final client = _clientWith(adapter);

        await _openOrdersSheet(tester, client);

        await tester.scrollUntilVisible(
          find.widgetWithText(OutlinedButton, 'Confirm'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Confirm'));
        await tester.pump();
        // Loading state: the button shows a spinner while the request is
        // still gated open.
        expect(find.byType(CircularProgressIndicator), findsWidgets);

        confirmGate.complete();
        await tester.pumpAndSettle();

        expect(confirmCalls, 1);
        expect(find.text('Order confirmed'), findsOneWidget);
      },
    );

    testWidgets('a second tap while confirming is a no-op (no duplicate '
        'request)', (tester) async {
      var confirmCalls = 0;
      final confirmGate = Completer<void>();
      final adapter = _adapterFor(
        '{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}',
        extra: (options) {
          if (options.path == '/orders/201/confirm/' &&
              options.method == 'POST') {
            confirmCalls++;
            return confirmGate.future.then(
              (_) => _json(_confirmedOrderJson, 200),
            );
          }
          return null;
        },
      );
      final client = _clientWith(adapter);

      await _openOrdersSheet(tester, client);

      final confirmButton = find.widgetWithText(OutlinedButton, 'Confirm');
      await tester.scrollUntilVisible(
        confirmButton,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(confirmButton);
      // Not a bare pump(): dispatching the request goes through the CSRF
      // interceptor's own async cookie-jar read before it reaches this
      // adapter — a real elapsed duration is what lets that queued
      // microtask chain actually run, the same reasoning the composer's
      // own busy-spinner tests document for their own bounded waits.
      await tester.pump(const Duration(milliseconds: 50));
      // Button is disabled while busy, so a second tap must not reach the
      // handler at all — verified by the missed-tap not registering.
      await tester.tap(confirmButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(confirmCalls, 1);

      confirmGate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a backend confirm error is shown, order stays pending', (
      tester,
    ) async {
      final adapter = _adapterFor(
        '{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}',
        extra: (options) {
          if (options.path == '/orders/201/confirm/' &&
              options.method == 'POST') {
            return _json(
              '{"error": {"code": "invalid", "message": "The order is not in a state that can be confirmed."}}',
              400,
            );
          }
          return null;
        },
      );
      final client = _clientWith(adapter);

      await _openOrdersSheet(tester, client);

      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Confirm'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'The order is not in a state that can be confirmed.',
        ),
        findsOneWidget,
      );
      // Still pending: Confirm is still offered, nothing crashed.
      expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Delete (cancel) button', () {
    testWidgets('shows a confirmation dialog before cancelling', (
      tester,
    ) async {
      final client = _clientWith(
        _adapterFor('{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}'),
      );

      await _openOrdersSheet(tester, client);

      await tester.scrollUntilVisible(
        find.byIcon(Icons.delete_outline),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Cancel this order?'), findsOneWidget);
      expect(find.text('Keep order'), findsOneWidget);
    });

    testWidgets(
      'confirming the dialog calls POST /orders/{id}/cancel/ and removes '
      'the pending actions',
      (tester) async {
        var cancelCalls = 0;
        final adapter = _adapterFor(
          '{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}',
          extra: (options) {
            if (options.path == '/orders/201/cancel/' &&
                options.method == 'POST') {
              cancelCalls++;
              return _json(_cancelledOrderJson, 200);
            }
            return null;
          },
        );
        final client = _clientWith(adapter);

        await _openOrdersSheet(tester, client);

        await tester.scrollUntilVisible(
          find.byIcon(Icons.delete_outline),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();
        // The confirmation dialog's own destructive action is labelled the
        // same as the tooltip ("Cancel this order").
        await tester.tap(
          find.widgetWithText(FilledButton, 'Cancel this order'),
        );
        await tester.pumpAndSettle();

        expect(cancelCalls, 1);
        expect(find.text('Order cancelled'), findsOneWidget);
      },
    );

    testWidgets('dismissing the dialog (Keep order) sends no request', (
      tester,
    ) async {
      var cancelCalls = 0;
      final adapter = _adapterFor(
        '{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}',
        extra: (options) {
          if (options.path == '/orders/201/cancel/') cancelCalls++;
          return null;
        },
      );
      final client = _clientWith(adapter);

      await _openOrdersSheet(tester, client);

      await tester.scrollUntilVisible(
        find.byIcon(Icons.delete_outline),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep order'));
      await tester.pumpAndSettle();

      expect(cancelCalls, 0);
      // Still pending — Confirm/delete still offered.
      expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsOneWidget);
    });

    testWidgets('a backend cancel error is shown, order stays visible', (
      tester,
    ) async {
      final adapter = _adapterFor(
        '{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}',
        extra: (options) {
          if (options.path == '/orders/201/cancel/' &&
              options.method == 'POST') {
            return _json(
              '{"error": {"code": "forbidden", "message": "Authenticated, but the employee lacks the required capability."}}',
              403,
            );
          }
          return null;
        },
      );
      final client = _clientWith(adapter);

      await _openOrdersSheet(tester, client);

      await tester.scrollUntilVisible(
        find.byIcon(Icons.delete_outline),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel this order'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('lacks the required capability'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Already-resolved orders do not show pending actions', () {
    testWidgets('a CONFIRMED order shows no Confirm button', (tester) async {
      final client = _clientWith(
        _adapterFor('{"count": 1, "results": [$_confirmedOrderJson]}'),
      );

      await _openOrdersSheet(tester, client);

      expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text('Confirmed by Jordan Lead'), findsOneWidget);
      expect(find.textContaining('Recorded by'), findsNothing);
    });

    testWidgets('a CANCELLED order renders with no pending actions', (
      tester,
    ) async {
      final client = _clientWith(
        _adapterFor('{"count": 1, "results": [$_cancelledOrderJson]}'),
      );

      await _openOrdersSheet(tester, client);

      expect(find.text('30.00 EGP'), findsOneWidget);
      expect(find.text('1× ccc'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without order.manage, a pending order shows no actions at '
        'all', (tester) async {
      final client = _clientWith(
        _adapterFor('{"count": 1, "results": [${_pendingOrderJson(id: 201)}]}'),
      );

      await _openOrdersSheet(
        tester,
        client,
        employee: _employee(permissions: {Perm.conversationReply}),
      );

      expect(find.widgetWithText(OutlinedButton, 'Confirm'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // The read-only indicators still show — visibility of an action is
      // gated, visibility of the order's own state is not.
      expect(find.text('Recorded by Sam Agent'), findsOneWidget);
      expect(
        find.text("Not counted as a sale until someone confirms it."),
        findsOneWidget,
      );
    });
  });
}
