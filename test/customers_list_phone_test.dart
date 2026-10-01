/// The Customers list shows the customer's phone under their name: the stored
/// `phone` if the backend has one, otherwise the WhatsApp number that
/// `identities[].external_id` already carries — and `—` when there is neither.
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
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/customers_screen.dart';
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

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _customerJson({
  required int id,
  required String name,
  String email = '',
  String phone = '',
  List<Map<String, Object?>> identities = const [],
}) => {
  'id': id,
  'display_name': name,
  'email': email,
  'phone': phone,
  'lifecycle_stage': 'UNKNOWN',
  'conversation_count': 1,
  'identities': identities,
  'last_seen_at': '2026-09-30T10:00:00Z',
};

Map<String, Object?> _whatsapp(int id, String externalId) => {
  'id': id,
  'provider': 'WHATSAPP',
  'external_id': externalId,
  'username': '@+$externalId',
  'display_name': '',
};

Employee _employee() => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Agent Alex',
  initials: 'AA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.customerView},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

Widget _harness(List<Map<String, Object?>> customers, {Locale? locale}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    if (options.path == '/customers/') {
      return _json({
        'count': customers.length,
        'next': null,
        'previous': null,
        'results': customers,
      });
    }
    return _json({});
  });
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(_employee()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      locale: locale ?? const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CustomersScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Customer.fromJson phone mapping', () {
    test('a stored phone is kept over the WhatsApp identity number', () {
      final customer = Customer.fromJson(
        _customerJson(
          id: 1,
          name: 'Mona',
          phone: '+201112223344',
          identities: [_whatsapp(1, '201069171483')],
        ),
      );

      expect(customer.displayPhone, '+201112223344');
      expect(customer.subtitle, '+201112223344');
    });

    test('an empty phone falls back to the WhatsApp identity number', () {
      final customer = Customer.fromJson(
        _customerJson(
          id: 1,
          name: 'Mona',
          identities: [_whatsapp(1, '201069171483')],
        ),
      );

      expect(customer.phone, '');
      expect(customer.displayPhone, '+201069171483');
      expect(customer.subtitle, '+201069171483');
      expect(customer.subtitleIsPhone, isTrue);
    });

    test('no phone and no WhatsApp identity keeps the — placeholder', () {
      final customer = Customer.fromJson(
        _customerJson(
          id: 1,
          name: 'Mona',
          identities: [
            {'id': 2, 'provider': 'INSTAGRAM', 'external_id': 'ig_789'},
          ],
        ),
      );

      expect(customer.displayPhone, '');
      expect(customer.subtitle, '—');
      expect(customer.subtitleIsPhone, isFalse);
    });

    test('an email still takes the subtitle, as before', () {
      final customer = Customer.fromJson(
        _customerJson(
          id: 1,
          name: 'Mona',
          email: 'mona@example.com',
          identities: [_whatsapp(1, '201069171483')],
        ),
      );

      expect(customer.subtitle, 'mona@example.com');
      expect(customer.subtitleIsPhone, isFalse);
    });
  });

  group('CustomersScreen rows', () {
    testWidgets('show the WhatsApp number under the name, — when none', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness([
          _customerJson(
            id: 1,
            name: 'Safaa Osman',
            identities: [_whatsapp(1, '201069171483')],
          ),
          _customerJson(
            id: 2,
            name: 'No Number',
            identities: [
              {'id': 3, 'provider': 'INSTAGRAM', 'external_id': 'ig_789'},
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Safaa Osman'), findsOneWidget);
      expect(find.text('No Number'), findsOneWidget);
      expect(find.textContaining('+201069171483'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      // Badges are untouched.
      expect(find.text('WhatsApp'), findsOneWidget);
    });

    testWidgets('a stored phone is shown instead of the identity number', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness([
          _customerJson(
            id: 1,
            name: 'Mona',
            phone: '+201112223344',
            identities: [_whatsapp(1, '201069171483')],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('+201112223344'), findsOneWidget);
      expect(find.textContaining('+201069171483'), findsNothing);
    });

    testWidgets('a very long number does not overflow the row', (tester) async {
      await tester.pumpWidget(
        _harness([
          _customerJson(
            id: 1,
            name: 'Mona',
            phone: '+2010691714830000000000000000000000000000',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('+20106917148300'), findsOneWidget);
    });

    testWidgets('renders in an Arabic (RTL) locale with the + kept in front', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness([
          _customerJson(
            id: 1,
            name: 'أميرة الأحلام',
            identities: [_whatsapp(1, '201069171483')],
          ),
        ], locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Left-to-right mark, then the number.
      expect(find.text('‎+201069171483'), findsOneWidget);
    });
  });
}
