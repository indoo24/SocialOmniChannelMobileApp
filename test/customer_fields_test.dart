/// Custom customer fields on mobile: the metadata decodes, each type renders
/// as it reads, editing sends only what changed and shows the server's
/// refusals by field, the section is absent for organizations without fields,
/// and free-form details are still shown.
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
import 'package:scenario_mobile/core/models/customer_fields.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/performance.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/customer_fields/custom_fields_section.dart';
import 'package:scenario_mobile/features/directory/customer_profile_screen.dart';
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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _definition(
  int id,
  String key,
  String type, {
  bool required = false,
  List<Map<String, String>> options = const [],
}) => {
  'id': id,
  'key': key,
  'label': key == 'vip'
      ? 'VIP'
      : key == 'customer_type'
      ? 'Customer type'
      : key == 'tags'
      ? 'Tags'
      : key == 'nickname'
      ? 'Nickname'
      : 'Birth date',
  'field_type': type,
  'options': options,
  'required': required,
  'is_active': true,
  'help_text': '',
  'placeholder': '',
};

const _types = [
  {'value': 'retail', 'label': 'Retail'},
  {'value': 'wholesale', 'label': 'Wholesale'},
];
const _tags = [
  {'value': 'vip', 'label': 'VIP customer'},
  {'value': 'late_payer', 'label': 'Late payer'},
];

List<Map<String, Object?>> _rows({bool nicknameRequired = false}) => [
  {
    'definition': _definition(1, 'vip', 'BOOLEAN'),
    'value': true,
    'fact_id': 10,
    'updated_by_name': '',
  },
  {
    'definition': _definition(2, 'customer_type', 'SELECT', options: _types),
    'value': 'wholesale',
    'fact_id': 11,
    'updated_by_name': '',
  },
  {
    'definition': _definition(3, 'tags', 'MULTI_SELECT', options: _tags),
    'value': ['vip'],
    'fact_id': 12,
    'updated_by_name': '',
  },
  {
    'definition': _definition(
      4,
      'nickname',
      'TEXT',
      required: nicknameRequired,
    ),
    'value': null,
    'fact_id': null,
    'updated_by_name': '',
  },
  {
    'definition': _definition(5, 'birth_date', 'DATE'),
    'value': null,
    'fact_id': null,
    'updated_by_name': '',
  },
];

class _Server {
  _Server({this.rows = const [], this.patchResponse});

  List<Map<String, Object?>> rows;
  (Object, int)? patchResponse;
  final writes = <RequestOptions>[];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) {
      final path = options.path;
      if (options.method != 'GET') writes.add(options);
      if (path == '/customers/42/fields/') {
        if (options.method == 'PATCH' && patchResponse != null) {
          return _json(patchResponse!.$1, patchResponse!.$2);
        }
        return _json(rows);
      }
      if (path == '/customers/42/conversations/') {
        return _json({'count': 0, 'results': []});
      }
      if (path == '/customers/42/') {
        return _json({
          'id': 42,
          'display_name': 'Mona',
          'lifecycle_stage': 'LEAD',
          'conversation_count': 0,
          'confirmed_purchase_count': 0,
          'identities': [],
          'facts': [
            {
              'id': 1,
              'key': 'adress',
              'value': '10 st.',
              'confidence': 1.0,
              'source': 'EMPLOYEE',
              'status': 'CONFIRMED',
              'needs_review': false,
              'definition': null,
              'validation_error': null,
            },
            {
              'id': 2,
              'key': 'vip',
              'value': 'true',
              'confidence': 1.0,
              'source': 'EMPLOYEE',
              'status': 'CONFIRMED',
              'needs_review': false,
              'definition': 1,
              'validation_error': null,
            },
          ],
        });
      }
      return _json({});
    });
    return client;
  }
}

Employee _employee({
  Set<String> permissions = const {Perm.customerView, Perm.customerManage},
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

Widget _harness(ApiClient client, Widget child, {Employee? employee}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('metadata', () {
    test('decodes definitions, options and typed values', () {
      final rows = _rows().map(CustomerFieldRow.fromJson).toList();

      expect(rows[0].definition.fieldType, 'BOOLEAN');
      expect(rows[0].value, true);
      expect(rows[1].definition.labelForOption('wholesale'), 'Wholesale');
      expect(rows[2].value, ['vip']);
      expect(rows[3].hasValue, isFalse);
      expect(rows[3].factId, isNull);
    });

    test('tolerates a field type this build does not know', () {
      final row = CustomerFieldRow.fromJson({
        'definition': {
          'id': 9,
          'key': 'future',
          'label': 'Future',
          'field_type': 'COLOR',
        },
        'value': '#ff0000',
      });
      expect(row.definition.fieldType, 'COLOR');
      expect(row.hasValue, isTrue);
    });

    test('marks typed facts and their validation error', () {
      final typed = CustomerFact.fromJson({
        'id': 1,
        'key': 'birth_date',
        'value': '2 April',
        'confidence': 0.6,
        'source': 'ANALYZER',
        'status': 'SUGGESTED',
        'needs_review': true,
        'definition': 5,
        'validation_error': 'Enter a date as YYYY-MM-DD.',
      });
      final legacy = CustomerFact.fromJson({
        'id': 2,
        'key': 'adress',
        'value': '10 st.',
        'confidence': 1,
        'source': 'EMPLOYEE',
        'status': 'CONFIRMED',
        'needs_review': false,
      });

      expect(
        (typed.isTypedField, typed.validationError),
        (true, 'Enter a date as YYYY-MM-DD.'),
      );
      expect((legacy.isTypedField, legacy.validationError), (false, null));
    });
  });

  group('the section', () {
    testWidgets('is absent when the organization has no fields', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(
        _harness(server.client(), const CustomFieldsSection(customerId: 42)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-fields-section')), findsNothing);
    });

    testWidgets('shows each value as it reads', (tester) async {
      final server = _Server(rows: _rows());
      await tester.pumpWidget(
        _harness(server.client(), const CustomFieldsSection(customerId: 42)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom fields'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('Wholesale'), findsOneWidget);
      expect(find.text('VIP customer'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('is read-only without customer.manage', (tester) async {
      final server = _Server(rows: _rows());
      await tester.pumpWidget(
        _harness(
          server.client(),
          const CustomFieldsSection(customerId: 42),
          employee: _employee(permissions: {Perm.customerView}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom fields'), findsOneWidget);
      expect(find.byKey(const Key('custom-fields-edit')), findsNothing);
    });
  });

  group('editing', () {
    Future<void> openSheet(WidgetTester tester, _Server server) async {
      await tester.pumpWidget(
        _harness(server.client(), const CustomFieldsSection(customerId: 42)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-fields-edit')));
      await tester.pumpAndSettle();
    }

    testWidgets('sends only the values that changed', (tester) async {
      final server = _Server(rows: _rows());
      await openSheet(tester, server);

      await tester.tap(find.byKey(const Key('custom-field-vip')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('custom-field-nickname')),
        'Mo',
      );
      await tester.tap(find.byKey(const Key('custom-field-tags-late_payer')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('custom-fields-save')));
      await tester.tap(find.byKey(const Key('custom-fields-save')));
      await tester.pumpAndSettle();

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'PATCH');
      final values = (server.writes.single.data as Map)['values'] as Map;
      expect(values.keys.toSet(), {'vip', 'nickname', 'tags'});
      expect(values['vip'], false);
      expect(values['nickname'], 'Mo');
      expect((values['tags'] as List).toSet(), {'vip', 'late_payer'});
    });

    testWidgets('shows the server refusal under the field it is about', (
      tester,
    ) async {
      final server = _Server(
        rows: _rows(),
        patchResponse: (
          {
            'error': {
              'code': 'invalid',
              'message': 'The submitted data was invalid.',
              'details': {
                'values': {
                  'nickname': ['Use a single line.'],
                },
              },
            },
          },
          400,
        ),
      );
      await openSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('custom-field-nickname')),
        'Mo',
      );
      await tester.ensureVisible(find.byKey(const Key('custom-fields-save')));
      await tester.tap(find.byKey(const Key('custom-fields-save')));
      await tester.pumpAndSettle();

      expect(find.text('Use a single line.'), findsOneWidget);
      expect(find.text('Edit custom fields'), findsOneWidget);
    });

    testWidgets('refuses to clear a required field without a request', (
      tester,
    ) async {
      final server = _Server(rows: _rows(nicknameRequired: true));
      await openSheet(tester, server);

      await tester.ensureVisible(find.byKey(const Key('custom-fields-save')));
      await tester.tap(find.byKey(const Key('custom-fields-save')));
      await tester.pumpAndSettle();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });
  });

  testWidgets(
    'the customer profile keeps free-form details and shows typed values once',
    (tester) async {
      final server = _Server(rows: _rows());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(server.client()),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CustomerProfileScreen(customerId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10 st.'), findsOneWidget);
      expect(find.text('Custom fields'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      // The typed fact's raw stored value is not repeated as a free-form detail.
      expect(find.text('true'), findsNothing);
    },
  );
}
