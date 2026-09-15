/// Customer Details screen (`CustomerProfileScreen`, reached by tapping a
/// customer in `CustomersScreen`): loading, the full data set — contact
/// info, custom fields, channels, known facts, confirmed purchases/orders —
/// empty states for each optional section, Export CSV for orders, and that
/// tapping a customer in the list actually navigates here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/customer_profile_screen.dart';
import 'package:scenario_mobile/features/directory/customers_screen.dart';
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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _customerDetailJson({
  int id = 42,
  String displayName = 'Mona',
  String email = 'mona@example.com',
  String phone = '+201112223344',
  String city = 'Cairo',
  String country = 'Egypt',
  String preferredLanguage = 'ar',
  int confirmedPurchaseCount = 2,
  List<Map<String, Object?>> identities = const [],
  List<Map<String, Object?>> facts = const [],
}) => {
  'id': id,
  'display_name': displayName,
  'lifecycle_stage': 'EXISTING_CUSTOMER',
  'conversation_count': 3,
  'confirmed_purchase_count': confirmedPurchaseCount,
  'facts': facts,
  'email': email,
  'phone': phone,
  'city': city,
  'country': country,
  'preferred_language': preferredLanguage,
  'identities': identities,
  'first_seen_at': '2026-08-17T05:32:00Z',
  'last_seen_at': '2026-09-15T00:22:00Z',
};

Map<String, Object?> _identityJson({
  required int id,
  required String provider,
  String externalId = '',
  String username = '',
}) => {
  'id': id,
  'provider': provider,
  'external_id': externalId,
  'username': username,
  'display_name': '',
};

Map<String, Object?> _factJson({
  required int id,
  required String key,
  required String value,
  String source = 'EMPLOYEE',
  bool needsReview = false,
}) => {
  'id': id,
  'key': key,
  'value': value,
  'confidence': 1.0,
  'source': source,
  'status': needsReview ? 'SUGGESTED' : 'CONFIRMED',
  'needs_review': needsReview,
};

Map<String, Object?> _orderJson({
  required int id,
  required String status,
  String totalAmount = '100.00',
  String currency = 'EGP',
  List<Map<String, Object?>> items = const [],
  String confirmedByName = '',
  String placedAt = '2026-09-06T19:10:00Z',
}) => {
  'id': id,
  'customer': 42,
  'status': status,
  'status_display': status,
  'source': 'EMPLOYEE',
  'is_claim': status != 'CONFIRMED',
  'total_amount': totalAmount,
  'currency': currency,
  'items': items,
  'confirmed_by_name': confirmedByName,
  'placed_at': placedAt,
};

class _Server {
  _Server({
    required this.detail,
    this.facts = const [],
    this.orders = const [],
    this.ordersStatus = 200,
  });

  Map<String, Object?> detail;
  List<Map<String, Object?>> facts;
  List<Map<String, Object?>> orders;
  int ordersStatus;
  late _StubAdapter adapter;

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    adapter = _StubAdapter((options) {
      final path = options.path;
      if (path == '/customers/42/') return _json(detail);
      if (path == '/customers/42/conversations/') {
        return _json({
          'count': 0,
          'next': null,
          'previous': null,
          'results': [],
        });
      }
      if (path == '/customers/42/fields/') return _json([]);
      if (path == '/customer-fields/') return _json([]);
      if (path == '/customers/42/facts/') return _json(facts);
      if (path == '/customers/42/orders/') {
        if (ordersStatus != 200) {
          return _json({
            'error': {'code': 'error', 'message': 'Could not load orders.'},
          }, ordersStatus);
        }
        return _json(orders);
      }
      if (path == '/orders/export/') {
        return ResponseBody.fromBytes(
          utf8.encode('id,amount\n1,100.00\n'),
          200,
          headers: {
            Headers.contentTypeHeader: ['text/csv'],
          },
        );
      }
      return _json({});
    });
    client.raw.httpClientAdapter = adapter;
    return client;
  }
}

Employee _employee({
  Set<String> permissions = const {Perm.customerView, Perm.crmExport},
}) => Employee(
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

Widget _harness(ApiClient client, {Employee? employee}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: CustomerProfileScreen(customerId: 42)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a loading state before the customer detail arrives', (
    tester,
  ) async {
    final completer = Completer<ResponseBody>();
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) async {
      if (options.path == '/customers/42/') return completer.future;
      return _json({});
    });

    await tester.pumpWidget(_harness(client));
    await tester.pump();

    expect(find.byType(LoadingState), findsWidgets);
    completer.complete(_json(_customerDetailJson()));
    await tester.pumpAndSettle();
  });

  testWidgets('shows a retryable error state when the detail request fails', (
    tester,
  ) async {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) {
      if (options.path == '/customers/42/') {
        return _json({
          'error': {'code': 'error', 'message': 'boom'},
        }, 500);
      }
      return _json({});
    });

    await tester.pumpWidget(_harness(client));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
  });

  group('contact info', () {
    testWidgets(
      'displays name, avatar initials, status badge and contact fields',
      (tester) async {
        final server = _Server(detail: _customerDetailJson());
        await tester.pumpWidget(_harness(server.client()));
        await tester.pumpAndSettle();

        expect(find.text('Mona'), findsWidgets);
        expect(find.text('Existing customer'), findsOneWidget);
        expect(find.text('mona@example.com'), findsOneWidget);
        expect(find.text('+201112223344'), findsOneWidget);
        expect(find.text('Cairo, Egypt'), findsOneWidget);
        expect(find.text('AR'), findsOneWidget);
      },
    );

    testWidgets('shows first seen and last seen', (tester) async {
      final server = _Server(detail: _customerDetailJson());
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('First seen'), findsOneWidget);
      expect(find.text('Last seen'), findsOneWidget);
    });

    testWidgets('missing fields show a placeholder rather than blank space', (
      tester,
    ) async {
      final server = _Server(
        detail: _customerDetailJson(
          email: '',
          phone: '',
          city: '',
          country: '',
        ),
      );
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
    });
  });

  group('channels', () {
    testWidgets('shows the platform and account identifier for each channel', (
      tester,
    ) async {
      final server = _Server(
        detail: _customerDetailJson(
          identities: [
            _identityJson(
              id: 1,
              provider: 'WHATSAPP',
              username: '@+201124868273',
              externalId: '201124868273',
            ),
            _identityJson(id: 2, provider: 'INSTAGRAM', externalId: 'ig_789'),
          ],
        ),
      );
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customer-channel-1')), findsOneWidget);
      expect(find.byKey(const Key('customer-channel-2')), findsOneWidget);
      expect(find.textContaining('@+201124868273'), findsOneWidget);
      expect(find.textContaining('ig_789'), findsOneWidget);
    });

    testWidgets('a customer with no channels shows the empty message', (
      tester,
    ) async {
      final server = _Server(detail: _customerDetailJson());
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(
        find.text('No channels recorded for this customer yet.'),
        findsOneWidget,
      );
    });
  });

  group('known facts', () {
    testWidgets('shows recorded facts with a source badge', (tester) async {
      final server = _Server(
        detail: _customerDetailJson(),
        facts: [
          _factJson(id: 1, key: 'age', value: '23', source: 'EMPLOYEE'),
          _factJson(
            id: 2,
            key: 'city_hint',
            value: 'Tanta',
            source: 'ANALYZER',
          ),
        ],
      );
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Age: 23', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('City hint: Tanta', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Employee'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('a still-pending suggestion is not shown as a known fact', (
      tester,
    ) async {
      final server = _Server(
        detail: _customerDetailJson(),
        facts: [
          _factJson(id: 3, key: 'guess', value: 'maybe', needsReview: true),
        ],
      );
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing known yet.'), findsOneWidget);
      expect(find.textContaining('maybe'), findsNothing);
    });

    testWidgets('a customer with no facts shows the empty message', (
      tester,
    ) async {
      final server = _Server(detail: _customerDetailJson());
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing known yet.'), findsOneWidget);
    });
  });

  group('confirmed purchases and orders', () {
    testWidgets('shows the confirmed purchase count from the detail payload', (
      tester,
    ) async {
      final server = _Server(
        detail: _customerDetailJson(confirmedPurchaseCount: 5),
      );
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Confirmed purchases'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets(
      'shows each order with amount, items, status and confirmed-by',
      (tester) async {
        final server = _Server(
          detail: _customerDetailJson(),
          orders: [
            _orderJson(
              id: 1,
              status: 'CONFIRMED',
              totalAmount: '1000.00',
              currency: 'EGP',
              items: [
                {
                  'id': 1,
                  'product_name': 'controller',
                  'quantity': 1,
                  'unit_price': '1000.00',
                  'line_total': '1000.00',
                },
              ],
              confirmedByName: 'Yousef Kandeel',
            ),
          ],
        );
        await tester.pumpWidget(_harness(server.client()));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('order-card-1')), findsOneWidget);
        expect(find.textContaining('1000.00'), findsWidgets);
        expect(find.textContaining('controller'), findsOneWidget);
        expect(find.textContaining('Confirmed'), findsWidgets);
        expect(find.textContaining('Yousef Kandeel'), findsOneWidget);
        expect(find.textContaining('Ordered'), findsOneWidget);
      },
    );

    testWidgets('a customer with no orders shows the empty message', (
      tester,
    ) async {
      final server = _Server(detail: _customerDetailJson());
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(
        find.text('No orders recorded for this customer yet.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a retryable error state when orders fail to load', (
      tester,
    ) async {
      final server = _Server(detail: _customerDetailJson(), ordersStatus: 500);
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Could not load orders.'), findsOneWidget);
    });

    testWidgets('Export CSV for orders is offered with crm.export', (
      tester,
    ) async {
      final server = _Server(detail: _customerDetailJson());
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-csv-menu')), findsOneWidget);
    });

    testWidgets('Export CSV is hidden without crm.export', (tester) async {
      final server = _Server(detail: _customerDetailJson());
      await tester.pumpWidget(
        _harness(
          server.client(),
          employee: _employee(permissions: {Perm.customerView}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-csv-menu')), findsNothing);
    });

    test(
      'exporting sends the customer id filter to the orders export endpoint',
      () async {
        // A plain `test`, not `testWidgets`: calls the repository directly
        // rather than tapping through `ExportCsvAction`'s `PopupMenuButton`.
        // The button's wiring itself (present/absent by permission) is
        // covered by the two widget tests above, and driving the full tap →
        // temp-file-write → share-sheet flow here would need the same
        // `path_provider`/`share_plus` platform fakes `csv_export_test.dart`
        // registers for exactly that reason — this only needs to confirm the
        // query the repository method builds.
        final server = _Server(detail: _customerDetailJson());
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(server.client()),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(directoryRepositoryProvider)
            .exportOrdersCsv(customerId: 42);

        final exportRequest = server.adapter.received.firstWhere(
          (r) => r.path == '/orders/export/',
        );
        expect(exportRequest.queryParameters['customer'], 42);
      },
    );
  });

  testWidgets(
    'tapping a customer in the Customers list navigates to Customer Details',
    (tester) async {
      final server = _Server(detail: _customerDetailJson());
      final adapter = server.adapter = _StubAdapter((options) {
        final path = options.path;
        if (path == '/customers/') {
          return _json({
            'count': 1,
            'next': null,
            'previous': null,
            'results': [
              {
                'id': 42,
                'display_name': 'Mona',
                'lifecycle_stage': 'EXISTING_CUSTOMER',
                'conversation_count': 3,
                'identities': [],
              },
            ],
          });
        }
        if (path == '/customers/42/') return _json(_customerDetailJson());
        if (path == '/customers/42/conversations/' ||
            path == '/customers/42/fields/') {
          return _json({
            'count': 0,
            'next': null,
            'previous': null,
            'results': [],
          });
        }
        if (path == '/customers/42/facts/' || path == '/customers/42/orders/') {
          return _json([]);
        }
        return _json({});
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final router = GoRouter(
        initialLocation: '/customers',
        routes: [
          GoRoute(
            path: '/customers',
            builder: (_, _) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/customers/:id',
            builder: (_, state) => CustomerProfileScreen(
              customerId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mona'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerProfileScreen), findsOneWidget);
      expect(find.byType(CustomersScreen), findsNothing);
    },
  );
}
