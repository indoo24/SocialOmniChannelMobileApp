/// Richer orders on mobile: the fields parse tolerantly, render only when they
/// say something, fulfilment moves without touching status, delivery details
/// travel only when typed, and a quick order is the request it always was.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/performance.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_actions_sheet.dart';
import 'package:scenario_mobile/features/orders/order_and_fact_dialogs.dart';
import 'package:scenario_mobile/features/orders/order_details.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => handler(options);

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

class _Call {
  _Call(this.method, this.path, this.body);
  final String method;
  final String path;
  final Object? body;
}

const _plainOrder = '''{
  "id": 101, "customer": 42, "conversation": 1, "status": "RECORDED",
  "status_display": "Recorded", "source": "EMPLOYEE", "is_claim": true,
  "total_amount": "100.00", "currency": "EGP",
  "items": [{"id": 1, "product_name": "Vase", "quantity": 2, "unit_price": "50.00", "line_total": "100.00"}],
  "recorded_by_name": "Alex", "confirmed_by_name": "", "evidence": "", "note": ""
}''';

const _richOrder = '''{
  "id": 101, "customer": 42, "conversation": 1, "status": "RECORDED",
  "status_display": "Recorded", "source": "EMPLOYEE", "is_claim": true,
  "total_amount": "125.00", "subtotal": "100.00", "discount": "10.00", "shipping_cost": "35.00",
  "currency": "EGP",
  "items": [{"id": 1, "product_name": "Vase", "quantity": 2, "unit_price": "50.00", "line_total": "100.00"}],
  "recorded_by_name": "Alex", "confirmed_by_name": "", "evidence": "", "note": "",
  "recipient_name": "Mona", "recipient_phone": "+201000000000", "city": "Tanta", "governorate": "Gharbia",
  "address": "12 Nile St", "landmark": "Near the station", "expected_delivery_date": "2026-09-20",
  "delivery_notes": "Ring twice", "payment_method": "CASH_ON_DELIVERY", "payment_status": "PAID",
  "fulfilment_status": "PACKING", "fulfilment_status_display": "Packing",
  "assigned_to_name": "Sara", "assigned_team_name": "", "internal_note": "", "cancellation_reason": ""
}''';

(ApiClient, List<_Call>) _client({String orderJson = _richOrder}) {
  final calls = <_Call>[];
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    calls.add(_Call(options.method, options.path, options.data));
    final path = options.path;
    if (path.endsWith('/conversations/1/')) {
      return _json(
        '{"id": 1, "customer": {"id": 42, "display_name": "Mona", "initials": "M"}, '
        '"provider": "WHATSAPP", "status": "OPEN", "priority": "NORMAL", '
        '"unread_count": 0, "message_count": 1}',
        200,
      );
    }
    if (path == '/orders/101/' && options.method == 'PATCH') {
      return _json(orderJson.replaceFirst('"PACKING"', '"SHIPPED"'), 200);
    }
    if (path.contains('/cancel/')) return _json(orderJson, 200);
    if (path == '/orders/' && options.method == 'POST') return _json(_plainOrder, 201);
    if (path.contains('/orders/')) {
      return _json('{"count": 1, "results": [$orderJson]}', 200);
    }
    if (path.contains('/facts/')) return _json('[]', 200);
    if (path.contains('/categories/')) return _json('[]', 200);
    if (path.contains('/messages/')) return _json('{"results": [], "count": 0}', 200);
    return _json('{}', 200);
  });
  return (client, calls);
}

Employee _employee({Set<String> permissions = const {Perm.orderManage}}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Agent Alex',
  initials: 'AA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: permissions,
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

Widget _harness(ApiClient client, Widget child, {Locale locale = const Locale('en'), Employee? employee}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

Order _parse(String json) =>
    Order.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));

void main() {
  group('the order model', () {
    test('parses every richer field', () {
      final order = _parse(_richOrder);

      expect(order.subtotal, '100.00');
      expect(order.discount, '10.00');
      expect(order.shippingCost, '35.00');
      expect(order.city, 'Tanta');
      expect(order.expectedDeliveryDate, '2026-09-20');
      expect(order.paymentStatus, 'PAID');
      expect(order.fulfilmentStatus, 'PACKING');
      expect(order.assignedToName, 'Sara');
      expect(order.canMoveFulfilment, isTrue);
      expect(order.hasPricingAdjustments, isTrue);
    });

    test('an order from a server without the fields offers no fulfilment', () {
      final order = _parse(_plainOrder);

      expect(order.fulfilmentStatus, isNull);
      expect(order.canMoveFulfilment, isFalse);
      expect(order.hasPricingAdjustments, isFalse);
      expect(order.discount, '0.00');
    });

    test('an ended order or a suggestion keeps its fulfilment', () {
      expect(
        _parse(_richOrder.replaceFirst('"RECORDED"', '"CANCELLED"')).canMoveFulfilment,
        isFalse,
      );
      expect(
        _parse(_richOrder.replaceFirst('"RECORDED"', '"SUGGESTED"')).canMoveFulfilment,
        isFalse,
      );
    });
  });

  group('the details lines', () {
    testWidgets('render pricing, fulfilment, delivery, payment and follow-up', (tester) async {
      final (client, _) = _client();
      await tester.pumpWidget(_harness(client, OrderDetailsLines(order: _parse(_richOrder))));

      expect(find.text('−10.00'), findsOneWidget);
      expect(find.text('+35.00'), findsOneWidget);
      expect(find.text('Fulfilment: Packing'), findsOneWidget);
      expect(find.text('Mona · +201000000000 — Tanta، Gharbia'), findsOneWidget);
      expect(find.text('12 Nile St (Near the station)'), findsOneWidget);
      expect(find.text('Cash on delivery · Paid (reported)'), findsOneWidget);
      expect(find.text('Follow-up: Sara'), findsOneWidget);
    });

    testWidgets('read in Arabic', (tester) async {
      final (client, _) = _client();
      await tester.pumpWidget(
        _harness(client, OrderDetailsLines(order: _parse(_richOrder)), locale: const Locale('ar')),
      );

      expect(find.text('التنفيذ: قيد التغليف'), findsOneWidget);
      expect(find.text('الدفع عند الاستلام · مدفوع (حسب الإفادة)'), findsOneWidget);
    });

    testWidgets('render nothing for a plain order', (tester) async {
      final (client, _) = _client();
      await tester.pumpWidget(_harness(client, OrderDetailsLines(order: _parse(_plainOrder))));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('show why a cancelled order ended, and no fulfilment', (tester) async {
      final (client, _) = _client();
      final cancelled = _parse(
        _richOrder
            .replaceFirst('"RECORDED"', '"CANCELLED"')
            .replaceFirst('"cancellation_reason": ""', '"cancellation_reason": "Out of stock"'),
      );
      await tester.pumpWidget(_harness(client, OrderDetailsLines(order: cancelled)));

      expect(find.text('Reason: Out of stock'), findsOneWidget);
      expect(find.textContaining('Fulfilment'), findsNothing);
    });
  });

  group('the repository', () {
    test('sends only typed delivery fields and the cancel reason', () async {
      final (client, calls) = _client();
      final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(client)]);
      addTearDown(container.dispose);
      final repository = container.read(directoryRepositoryProvider);

      await repository.recordOrder(
        customerId: 42,
        conversationId: 1,
        items: const [{'product_name': 'Vase', 'quantity': 1, 'unit_price': '9.00'}],
        delivery: const {'city': ' Tanta ', 'address': '  '},
      );
      await repository.cancelOrder(101, reason: 'Out of stock');
      await repository.updateOrderFulfilment(101, 'SHIPPED');

      final post = calls.firstWhere((c) => c.method == 'POST' && c.path == '/orders/');
      expect((post.body as Map).keys.toSet(), {'customer', 'conversation', 'items', 'city'});
      expect((post.body as Map)['city'], 'Tanta');
      final cancel = calls.firstWhere((c) => c.path.contains('/cancel/'));
      expect(cancel.body, {'refunded': false, 'reason': 'Out of stock'});
      final patch = calls.firstWhere((c) => c.method == 'PATCH');
      expect(patch.path, '/orders/101/');
      expect(patch.body, {'fulfilment_status': 'SHIPPED'});
    });
  });

  group('the record dialog', () {
    Future<List<_Call>> openDialog(WidgetTester tester) async {
      final (client, calls) = _client();
      await tester.pumpWidget(
        _harness(
          client,
          Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordOrderDialog(context, ref: ref, customerId: 42, conversationId: 1),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('keeps delivery collapsed and a quick order unchanged', (tester) async {
      final calls = await openDialog(tester);

      expect(find.byType(TextField), findsNWidgets(3));
      await tester.enterText(find.byType(TextField).at(0), 'Vase');
      await tester.tap(find.widgetWithText(FilledButton, 'Record an order'));
      await tester.pumpAndSettle();

      final post = calls.firstWhere((c) => c.method == 'POST' && c.path == '/orders/');
      expect((post.body as Map).keys.toSet(), {'customer', 'conversation', 'items'});
    });

    testWidgets('sends delivery details typed into the opened section', (tester) async {
      final calls = await openDialog(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Vase');
      await tester.tap(find.byKey(const Key('order-delivery-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(9));

      await tester.enterText(find.byKey(const Key('order-delivery-city')), 'Tanta');
      await tester.enterText(find.byKey(const Key('order-delivery-recipient_phone')), '+201000000000');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Record an order'));
      await tester.tap(find.widgetWithText(FilledButton, 'Record an order'));
      await tester.pumpAndSettle();

      final post = calls.firstWhere((c) => c.method == 'POST' && c.path == '/orders/');
      expect(post.body, containsPair('city', 'Tanta'));
      expect(post.body, containsPair('recipient_phone', '+201000000000'));
      expect((post.body as Map).containsKey('address'), isFalse);
    });
  });

  group('fulfilment in the conversation actions sheet', () {
    Future<void> openSheet(WidgetTester tester, ApiClient client, {Employee? employee}) async {
      await tester.pumpWidget(
        _harness(
          client,
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showConversationActionsSheet(context, conversationId: 1),
              child: const Text('open sheet'),
            ),
          ),
          employee: employee,
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();
    }

    testWidgets('moves fulfilment with a PATCH and nothing else', (tester) async {
      final (client, calls) = _client();
      await openSheet(tester, client);

      final picker = find.byKey(const ValueKey('fulfilment-picker-101'));
      await tester.scrollUntilVisible(picker, 200, scrollable: find.byType(Scrollable).last);
      // Opened through the button itself: inside the draggable sheet a
      // coordinate tap can land on the sheet's own gesture layer.
      tester.state<PopupMenuButtonState<String>>(picker).showButtonMenu();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shipped').last);
      await tester.pumpAndSettle();

      // Opening the sheet marks the conversation read; only order writes count.
      final writes = calls
          .where((c) => c.method != 'GET' && c.path.contains('/orders/'))
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.path, '/orders/101/');
      expect(writes.single.body, {'fulfilment_status': 'SHIPPED'});
    });

    testWidgets('is read-only without order.manage', (tester) async {
      final (client, _) = _client();
      await openSheet(tester, client, employee: _employee(permissions: {Perm.conversationReply}));

      await tester.scrollUntilVisible(
        find.text('Order #101'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const ValueKey('fulfilment-picker-101')), findsNothing);
      expect(find.text('Fulfilment: Packing'), findsOneWidget);
    });
  });
}
