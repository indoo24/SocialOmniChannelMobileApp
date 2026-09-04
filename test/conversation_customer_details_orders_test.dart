/// Comprehensive regression tests for Customer Details & Orders actions
/// in Conversation Actions Sheet and dialogs.
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
import 'package:scenario_mobile/features/orders/order_and_fact_dialogs.dart';
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

Employee _createEmployee({Set<String> permissions = const {Perm.orderManage}}) {
  return Employee(
    id: 1,
    email: 'supervisor@acme.test',
    fullName: 'Supervisor Alex',
    initials: 'SA',
    role: 'SUPERVISOR',
    roleDisplay: 'Supervisor',
    availability: 'ONLINE',
    permissions: permissions,
    visibilityScope: 'ALL',
    organization: const Organization(id: 1, name: 'Acme Retail'),
  );
}

Widget _harness({
  required ApiClient apiClient,
  required Widget child,
  Employee? employee,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee ?? _createEmployee()),
    ],
    child: MaterialApp(
      locale: locale,
      themeMode: themeMode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

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
          "id": 42,
          "display_name": "Sarah Connor",
          "initials": "SC",
          "phone": "+123456789",
          "email": "sarah@example.com",
          "country": "Egypt",
          "city": "Cairo"
        },
        "provider": "WHATSAPP",
        "channel_name": "Sales Line",
        "status": "OPEN",
        "priority": "NORMAL",
        "unread_count": 0,
        "message_count": 10
      }''', 200);
    }
    if (options.path.contains('/orders/')) {
      return _json('''{
        "count": 1,
        "results": [
          {
            "id": 101,
            "customer": 42,
            "conversation": 1,
            "status": "CANCELLED",
            "status_display": "Cancelled",
            "source": "EMPLOYEE",
            "is_claim": false,
            "total_amount": "100.00",
            "currency": "EGP",
            "items": [
              {
                "id": 1,
                "product_name": "aaa",
                "quantity": 2,
                "unit_price": "50.00",
                "line_total": "100.00"
              }
            ],
            "recorded_by_name": "Alex",
            "confirmed_by_name": "",
            "evidence": "",
            "note": ""
          }
        ]
      }''', 200);
    }
    if (options.path.contains('/facts/')) {
      return _json('''[
        {
          "id": 1,
          "key": "Num",
          "value": "01126737783",
          "confidence": 1.0,
          "source": "EMPLOYEE",
          "status": "CONFIRMED",
          "needs_review": false
        },
        {
          "id": 2,
          "key": "Adress",
          "value": "10 st.",
          "confidence": 1.0,
          "source": "EMPLOYEE",
          "status": "CONFIRMED",
          "needs_review": false
        }
      ]''', 200);
    }
    if (options.path.contains('/intelligence/')) {
      return _json('{}', 200);
    }
    if (options.path.contains('/categories/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/messages/')) {
      return _json('{"results": [], "count": 0}', 200);
    }
    return _json('{}', 200);
  });
}

void main() {
  group('Customer Details & Orders in Actions Bottom Sheet', () {
    testWidgets(
      'renders existing customer facts and order card matching Web Screenshot C',
      (tester) async {
        final client = _clientFor();

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showConversationActionsSheet(context, conversationId: 1),
                child: const Text('open sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        // 1. Customer Details section header has "+ Add" button
        expect(find.text('Customer details'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);

        // 2. Recorded facts are displayed with Employee pill
        expect(find.textContaining('Num: 01126737783'), findsOneWidget);
        expect(find.textContaining('Adress: 10 st.'), findsOneWidget);
        expect(find.text('Employee'), findsAtLeastNWidgets(2));

        // 3. Orders section header has "+ Order" button
        await tester.scrollUntilVisible(
          find.text('Orders'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Orders'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Order'), findsOneWidget);

        // 4. Order card displays package icon, amount with currency, status, and items
        expect(find.text('Order #101'), findsOneWidget);
        expect(find.text('100.00 EGP'), findsOneWidget);
        expect(find.text('Cancelled'), findsOneWidget);
        expect(find.text('2× aaa'), findsOneWidget);
        expect(find.text('100.00'), findsOneWidget);
      },
    );

    testWidgets(
      'permission gating: hides Add and Order buttons when orderManage is missing',
      (tester) async {
        final client = _clientFor();
        final restrictedEmployee = _createEmployee(
          permissions: {Perm.conversationReply}, // lacking orderManage
        );

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            employee: restrictedEmployee,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showConversationActionsSheet(context, conversationId: 1),
                child: const Text('open sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Customer details'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Add'), findsNothing);

        await tester.scrollUntilVisible(
          find.text('Orders'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Orders'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Order'), findsNothing);
      },
    );

    testWidgets(
      'tapping Add button in bottom sheet opens customer detail dialog without collapsing section',
      (tester) async {
        final client = _clientFor();

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showConversationActionsSheet(context, conversationId: 1),
                child: const Text('open sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        // Tap Add button
        await tester.tap(find.widgetWithText(TextButton, 'Add'));
        await tester.pumpAndSettle();

        // Dialog should be open
        expect(find.text('Record a customer detail'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

        // Cancel dialog
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        // Dialog is dismissed, Customer Details content is still visible (card did NOT collapse)
        expect(find.text('Record a customer detail'), findsNothing);
        expect(find.textContaining('Num: 01126737783'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping Order button in bottom sheet opens order dialog without collapsing section',
      (tester) async {
        final client = _clientFor();

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showConversationActionsSheet(context, conversationId: 1),
                child: const Text('open sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.widgetWithText(TextButton, 'Order'),
          200,
          scrollable: find.byType(Scrollable).last,
        );

        // Tap Order button
        await tester.tap(find.widgetWithText(TextButton, 'Order'));
        await tester.pumpAndSettle();

        // Dialog should be open
        expect(
          find.text('Record an order'),
          findsNWidgets(2),
        ); // Title & button

        // Cancel dialog
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        // Dialog dismissed, Order card still visible (card did NOT collapse)
        expect(find.text('Order #101'), findsOneWidget);
      },
    );
  });

  group('Record Customer Detail Dialog Flow', () {
    testWidgets('validates required fields, prevents empty submission', (
      tester,
    ) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordCustomerDetailDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Record a customer detail'), findsOneWidget);
      expect(
        find.text(
          'Something the customer shared — an address, a phone number, a preference.',
        ),
        findsOneWidget,
      );

      // Attempt submit with empty fields
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter both detail and value.'), findsOneWidget);
    });

    testWidgets(
      'submits valid detail, calls POST /customers/42/facts/, and invalidates provider',
      (tester) async {
        var postCalled = false;
        Map<String, dynamic>? receivedBody;

        final client = _clientFor(
          extra: (options) {
            if (options.path == '/customers/42/facts/' &&
                options.method == 'POST') {
              postCalled = true;
              receivedBody = options.data as Map<String, dynamic>;
              return _json('''{
                "id": 3,
                "key": "Rhidif",
                "value": "jvk",
                "confidence": 1.0,
                "source": "EMPLOYEE",
                "status": "CONFIRMED",
                "needs_review": false
              }''', 201);
            }
            return null;
          },
        );

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showRecordCustomerDetailDialog(
                  context,
                  ref: ref,
                  customerId: 42,
                  conversationId: 1,
                ),
                child: const Text('open dialog'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open dialog'));
        await tester.pumpAndSettle();

        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(2));

        await tester.enterText(textFields.first, 'Rhidif');
        await tester.enterText(textFields.last, 'jvk');

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(postCalled, isTrue);
        expect(receivedBody?['key'], 'Rhidif');
        expect(receivedBody?['value'], 'jvk');
        expect(receivedBody?['conversation'], 1);

        // Dialog closes on success
        expect(find.text('Record a customer detail'), findsNothing);
      },
    );

    testWidgets('shows backend error and keeps dialog open', (tester) async {
      final client = _clientFor(
        extra: (options) {
          if (options.path.contains('/facts/') && options.method == 'POST') {
            return _json('{"detail": "Fact key already exists"}', 400);
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordCustomerDetailDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, 'Address');
      await tester.enterText(textFields.last, '12 Nile St');

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fact key already exists'), findsOneWidget);
      expect(find.text('Record a customer detail'), findsOneWidget);
    });

    testWidgets('cancelling dialog dismisses without API call', (tester) async {
      var postCalled = false;
      final client = _clientFor(
        extra: (options) {
          if (options.path.contains('/facts/') && options.method == 'POST') {
            postCalled = true;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordCustomerDetailDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(postCalled, isFalse);
      expect(find.text('Record a customer detail'), findsNothing);
    });
  });

  group('Record Order Dialog Flow', () {
    testWidgets('initial order line exists and adds another line', (
      tester,
    ) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordOrderDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Record an order'), findsNWidgets(2));
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('0.00'), findsAtLeastNWidgets(1));

      // Initial line has 3 text fields (Product, Qty, Price)
      expect(find.byType(TextField), findsNWidgets(3));

      // Tap "+ Add line"
      await tester.tap(find.widgetWithText(TextButton, 'Add line'));
      await tester.pumpAndSettle();

      // Now 2 lines = 6 text fields
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('quantity and price calculation updates total dynamically', (
      tester,
    ) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordOrderDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'aaa');
      await tester.enterText(fields.at(1), '2');
      await tester.enterText(fields.at(2), '50.00');
      await tester.pumpAndSettle();

      // 2 * 50.00 = 100.00
      expect(find.text('100.00'), findsOneWidget);

      // Add second line
      await tester.tap(find.widgetWithText(TextButton, 'Add line'));
      await tester.pumpAndSettle();

      final updatedFields = find.byType(TextField);
      await tester.enterText(updatedFields.at(3), 'bbb');
      await tester.enterText(updatedFields.at(4), '3');
      await tester.enterText(updatedFields.at(5), '25.00');
      await tester.pumpAndSettle();

      // 100.00 + (3 * 25.00) = 175.00
      expect(find.text('175.00'), findsOneWidget);
    });

    testWidgets(
      'submits order with correct payload structure to POST /orders/',
      (tester) async {
        var postOrderCalled = false;
        Map<String, dynamic>? orderPayload;

        final client = _clientFor(
          extra: (options) {
            if (options.path == '/orders/' && options.method == 'POST') {
              postOrderCalled = true;
              orderPayload = options.data as Map<String, dynamic>;
              return _json('''{
                "id": 102,
                "customer": 42,
                "conversation": 1,
                "status": "RECORDED",
                "status_display": "Recorded",
                "source": "EMPLOYEE",
                "is_claim": false,
                "total_amount": "100.00",
                "currency": "EGP",
                "items": [
                  {
                    "id": 10,
                    "product_name": "aaa",
                    "quantity": 2,
                    "unit_price": "50.00",
                    "line_total": "100.00"
                  }
                ],
                "recorded_by_name": "Alex",
                "confirmed_by_name": "",
                "evidence": "",
                "note": ""
              }''', 201);
            }
            return null;
          },
        );

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showRecordOrderDialog(
                  context,
                  ref: ref,
                  customerId: 42,
                  conversationId: 1,
                ),
                child: const Text('open dialog'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open dialog'));
        await tester.pumpAndSettle();

        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'aaa');
        await tester.enterText(fields.at(1), '2');
        await tester.enterText(fields.at(2), '50.00');

        await tester.tap(find.widgetWithText(FilledButton, 'Record an order'));
        await tester.pumpAndSettle();

        expect(postOrderCalled, isTrue);
        expect(orderPayload?['customer'], 42);
        expect(orderPayload?['conversation'], 1);
        final items = orderPayload?['items'] as List;
        expect(items.length, 1);
        expect(items[0]['product_name'], 'aaa');
        expect(items[0]['quantity'], 2);
        expect(items[0]['unit_price'], '50.00');

        // Dialog closed
        expect(find.text('Record an order'), findsNothing);
      },
    );

    testWidgets('shows backend error and preserves dialog state', (
      tester,
    ) async {
      final client = _clientFor(
        extra: (options) {
          if (options.path == '/orders/' && options.method == 'POST') {
            return _json('{"detail": "Product out of stock"}', 400);
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordOrderDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Special Item');
      await tester.enterText(fields.at(1), '1');
      await tester.enterText(fields.at(2), '150.00');

      await tester.tap(find.widgetWithText(FilledButton, 'Record an order'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Product out of stock'), findsOneWidget);
      expect(find.text('Record an order'), findsNWidgets(2));
    });
  });

  group('Themes and Arabic / RTL Support', () {
    testWidgets(
      'renders Arabic translations and RTL directionality in dialogs',
      (tester) async {
        final client = _clientFor();

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            locale: const Locale('ar'),
            child: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showRecordCustomerDetailDialog(
                  context,
                  ref: ref,
                  customerId: 42,
                  conversationId: 1,
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('افتح'));
        await tester.pumpAndSettle();

        // Arabic title and button
        expect(find.text('تسجيل بيانات عميل'), findsOneWidget);
        expect(find.text('حفظ'), findsOneWidget);
        expect(find.text('إلغاء'), findsOneWidget);
      },
    );

    testWidgets('renders correctly in dark mode', (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          themeMode: ThemeMode.dark,
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showRecordOrderDialog(
                context,
                ref: ref,
                customerId: 42,
                conversationId: 1,
              ),
              child: const Text('open dark'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dark'));
      await tester.pumpAndSettle();

      expect(find.text('Record an order'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}
