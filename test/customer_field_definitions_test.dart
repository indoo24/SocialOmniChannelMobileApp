/// Customer field *definitions* management (the Settings admin tab), not the
/// per-customer values screen (`custom_fields_section.dart` /
/// `test/customer_fields_test.dart`): listing, add, edit with a read-only
/// key, validation, enable/disable, reorder and its persistence, the empty
/// state, and error handling — `GET/POST/PATCH /customer-fields/` and
/// `POST /customer-fields/reorder/`.
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
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/customer_fields/customer_fields_settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Finder _sheetScrollable() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.byType(ListView),
);

Future<void> _scrollToAndTapSave(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byKey(const Key('field-form-save')),
    _sheetScrollable(),
    const Offset(0, -300),
  );
  await tester.tap(find.byKey(const Key('field-form-save')));
  await tester.pumpAndSettle();
}

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

Map<String, Object?> _definition({
  required int id,
  required String key,
  required String label,
  String fieldType = 'TEXT',
  bool required = false,
  bool isActive = true,
  int displayOrder = 0,
  String helpText = '',
  String placeholder = '',
}) => {
  'id': id,
  'key': key,
  'label': label,
  'field_type': fieldType,
  'field_type_display': fieldType,
  'options': const [],
  'required': required,
  'is_active': isActive,
  'display_order': displayOrder,
  'help_text': helpText,
  'placeholder': placeholder,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

class _Server {
  _Server({List<Map<String, Object?>>? fields, this.extra})
    : fields = fields ?? [];

  List<Map<String, Object?>> fields;
  final FutureOr<ResponseBody?> Function(RequestOptions options)? extra;
  final writes = <RequestOptions>[];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) async {
      final path = options.path;
      if (options.method != 'GET') writes.add(options);

      if (extra != null) {
        final result = await extra!(options);
        if (result != null) return result;
      }

      if (path == '/customer-fields/' && options.method == 'GET') {
        return _json(fields);
      }
      if (path == '/customer-fields/' && options.method == 'POST') {
        final body = Map<String, dynamic>.from(options.data as Map);
        final created = _definition(
          id: fields.length + 100,
          key: (body['key'] as String?)?.isNotEmpty == true
              ? body['key'] as String
              : (body['label'] as String).toLowerCase().replaceAll(' ', '_'),
          label: body['label'] as String,
          fieldType: body['field_type'] as String,
          required: body['required'] as bool? ?? false,
          helpText: body['help_text'] as String? ?? '',
          placeholder: body['placeholder'] as String? ?? '',
          displayOrder: fields.length,
        );
        fields = [...fields, created];
        return _json(created, 201);
      }
      if (path.startsWith('/customer-fields/') &&
          path.endsWith('/') &&
          options.method == 'PATCH') {
        final id = int.parse(path.split('/')[2]);
        final body = Map<String, dynamic>.from(options.data as Map);
        final index = fields.indexWhere((f) => f['id'] == id);
        final updated = Map<String, Object?>.from(fields[index]);
        body.forEach((key, value) => updated[key] = value);
        fields = [...fields]..[index] = updated;
        return _json(updated);
      }
      if (path == '/customer-fields/reorder/' && options.method == 'POST') {
        final order = List<int>.from(options.data['order'] as List);
        final byId = {for (final f in fields) f['id'] as int: f};
        final reordered = <Map<String, Object?>>[];
        for (var i = 0; i < order.length; i++) {
          final f = Map<String, Object?>.from(byId[order[i]]!);
          f['display_order'] = i;
          reordered.add(f);
        }
        fields = reordered;
        return _json(fields);
      }
      return _json({});
    });
    return client;
  }
}

Employee _employee({
  Set<String> permissions = const {Perm.customerView, Perm.customerFieldManage},
}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
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
    home: const Scaffold(body: CustomerFieldsSettingsTab()),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('listing', () {
    testWidgets('loads and shows every field from the API', (tester) async {
      final server = _Server(
        fields: [
          _definition(
            id: 1,
            key: 'nickname',
            label: 'Nickname',
            displayOrder: 0,
          ),
          _definition(
            id: 2,
            key: 'birth_date',
            label: 'Birth date',
            fieldType: 'DATE',
            displayOrder: 1,
          ),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Customer fields'), findsWidgets);
      expect(find.text('Nickname'), findsOneWidget);
      expect(find.text('Birth date'), findsOneWidget);
      expect(find.text('Key: nickname'), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no fields', (
      tester,
    ) async {
      final server = _Server();

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('No custom fields yet'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows a retryable error state on failure', (tester) async {
      final server = _Server(
        extra: (options) {
          if (options.path == '/customer-fields/' && options.method == 'GET') {
            return _json({
              'error': {'code': 'error', 'message': 'boom'},
            }, 500);
          }
          return null;
        },
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a disabled field shows the disabled badge', (tester) async {
      final server = _Server(
        fields: [
          _definition(
            id: 1,
            key: 'old_field',
            label: 'Old field',
            isActive: false,
          ),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('without customer_field.manage, actions are hidden', (
      tester,
    ) async {
      final server = _Server(
        fields: [_definition(id: 1, key: 'nickname', label: 'Nickname')],
      );

      await tester.pumpWidget(
        _harness(
          server.client(),
          employee: _employee(permissions: {Perm.customerView}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-customer-field')), findsNothing);
      expect(find.byKey(const Key('customer-field-1-edit')), findsNothing);
    });

    testWidgets('without customer.view, shows a permission-denied state', (
      tester,
    ) async {
      final server = _Server();

      await tester.pumpWidget(
        _harness(server.client(), employee: _employee(permissions: {})),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("You don't have permission to view customer fields."),
        findsOneWidget,
      );
    });
  });

  group('add field', () {
    Future<void> openAddSheet(WidgetTester tester, _Server server) async {
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-customer-field')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the type dropdown offers exactly the backend-supported types',
      (tester) async {
        final server = _Server();
        await openAddSheet(tester, server);

        await tester.tap(find.byKey(const Key('field-form-type')));
        await tester.pumpAndSettle();

        const expectedLabels = [
          'Text',
          'Long text',
          'Whole number',
          'Decimal number',
          'Date',
          'Date & time',
          'Yes / No',
          'Single choice',
          'Multiple choice',
          'Phone',
          'Email',
        ];
        for (final label in expectedLabels) {
          // The menu is a scrollable overlay — items past the fold exist in
          // the tree without being hit-testable yet, so presence is the
          // meaningful check here, not tap-ability.
          expect(find.text(label), findsWidgets);
        }

        // Nothing beyond the 11 backend-documented types is offered: nine of
        // the eleven show up twice (selected value in the field + menu entry),
        // and none should show three or more times.
        for (final label in expectedLabels) {
          expect(find.text(label).evaluate().length, lessThanOrEqualTo(2));
        }
      },
    );

    testWidgets('rejects an empty label without a request', (tester) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await _scrollToAndTapSave(tester);

      expect(find.text('Enter a label.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('creates a field and refreshes the list', (tester) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('field-form-label')),
        'Nickname',
      );
      await _scrollToAndTapSave(tester);

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'POST');
      final body = server.writes.single.data as Map;
      expect(body['label'], 'Nickname');
      expect(body['field_type'], 'TEXT');
      expect(find.text('Field added'), findsOneWidget);
      expect(find.text('Nickname'), findsOneWidget);
    });

    testWidgets('the key field only accepts letters, digits and underscores', (
      tester,
    ) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await tester.enterText(find.byKey(const Key('field-form-key')), 'a b!c');

      final keyField = tester.widget<TextField>(
        find.byKey(const Key('field-form-key')),
      );
      expect(keyField.controller!.text, 'abc');
    });

    testWidgets('a key that does not start with a letter is rejected locally', (
      tester,
    ) async {
      final server = _Server();
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('field-form-label')),
        'Nickname',
      );
      await tester.enterText(
        find.byKey(const Key('field-form-key')),
        '1nickname',
      );
      await _scrollToAndTapSave(tester);

      expect(
        find.text('Use only English letters, numbers and underscores.'),
        findsOneWidget,
      );
      expect(server.writes, isEmpty);
    });

    testWidgets('shows the server refusal on a validation error', (
      tester,
    ) async {
      final server = _Server(
        extra: (options) {
          if (options.path == '/customer-fields/' && options.method == 'POST') {
            return _json({
              'error': {
                'code': 'invalid',
                'message': 'That key is already used.',
                'details': {
                  'key': ['That key is already used.'],
                },
              },
            }, 400);
          }
          return null;
        },
      );
      await openAddSheet(tester, server);

      await tester.enterText(
        find.byKey(const Key('field-form-label')),
        'Nickname',
      );
      await _scrollToAndTapSave(tester);

      expect(find.text('That key is already used.'), findsOneWidget);
      // The sheet stayed open (its title is still on screen — the tab's own
      // "Add field" button, behind the still-open sheet, makes it a second
      // match) rather than popping on a failed save.
      expect(find.text('Add field'), findsNWidgets(2));
      expect(server.writes, hasLength(1));
    });
  });

  group('edit field', () {
    testWidgets('loads existing values and keeps the key read-only', (
      tester,
    ) async {
      final server = _Server(
        fields: [
          _definition(
            id: 1,
            key: 'nickname',
            label: 'Nickname',
            fieldType: 'TEXT',
            required: true,
            helpText: 'Shown to the customer',
            placeholder: 'e.g. Mo',
          ),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-edit')));
      await tester.pumpAndSettle();

      expect(find.text('Edit field'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Label'), findsOneWidget);
      final labelField = tester.widget<TextField>(
        find.byKey(const Key('field-form-label')),
      );
      expect(labelField.controller!.text, 'Nickname');

      final keyField = tester.widget<TextField>(
        find.byKey(const Key('field-form-key')),
      );
      expect(keyField.controller!.text, 'nickname');
      expect(keyField.enabled, isFalse);

      final helpTextField = tester.widget<TextField>(
        find.byKey(const Key('field-form-help-text')),
      );
      expect(helpTextField.controller!.text, 'Shown to the customer');

      final requiredSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('field-form-required')),
      );
      expect(requiredSwitch.value, isTrue);
    });

    testWidgets('saving an edit never sends the key', (tester) async {
      final server = _Server(
        fields: [_definition(id: 1, key: 'nickname', label: 'Nickname')],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-form-label')), 'Nick');
      await _scrollToAndTapSave(tester);

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'PATCH');
      final body = server.writes.single.data as Map;
      expect(body.containsKey('key'), isFalse);
      expect(body['label'], 'Nick');
      expect(find.text('Field updated'), findsOneWidget);
    });
  });

  group('enable / disable', () {
    testWidgets('disabling an active field calls PATCH is_active=false', (
      tester,
    ) async {
      final server = _Server(
        fields: [_definition(id: 1, key: 'nickname', label: 'Nickname')],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-toggle')));
      await tester.pumpAndSettle();

      expect(server.writes, hasLength(1));
      expect(server.writes.single.method, 'PATCH');
      expect(server.writes.single.path, '/customer-fields/1/');
      expect((server.writes.single.data as Map)['is_active'], false);
      expect(find.text('Field disabled'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('enabling a disabled field calls PATCH is_active=true', (
      tester,
    ) async {
      final server = _Server(
        fields: [
          _definition(
            id: 1,
            key: 'nickname',
            label: 'Nickname',
            isActive: false,
          ),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-toggle')));
      await tester.pumpAndSettle();

      expect((server.writes.single.data as Map)['is_active'], true);
      expect(find.text('Field enabled'), findsOneWidget);
    });

    testWidgets('a failed toggle shows an error and keeps prior state', (
      tester,
    ) async {
      final server = _Server(
        fields: [_definition(id: 1, key: 'nickname', label: 'Nickname')],
        extra: (options) {
          if (options.path == '/customer-fields/1/' &&
              options.method == 'PATCH') {
            return _json({
              'error': {'code': 'error', 'message': 'Could not update.'},
            }, 500);
          }
          return null;
        },
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Could not update.'), findsOneWidget);
      expect(find.text('Disabled'), findsNothing);
    });
  });

  group('reorder', () {
    testWidgets('moving a field down sends the new order and persists it', (
      tester,
    ) async {
      final server = _Server(
        fields: [
          _definition(id: 1, key: 'a_field', label: 'A field', displayOrder: 0),
          _definition(id: 2, key: 'b_field', label: 'B field', displayOrder: 1),
        ],
      );

      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('customer-field-1-move-down')));
      await tester.pumpAndSettle();

      expect(server.writes, hasLength(1));
      expect(server.writes.single.path, '/customer-fields/reorder/');
      expect((server.writes.single.data as Map)['order'], [2, 1]);
      expect(find.text('Field order updated'), findsOneWidget);

      // Reopening the tab (a fresh provider read) reflects the new order —
      // the server's own state was updated, not just the widget in front of us.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_harness(server.client()));
      await tester.pumpAndSettle();

      final bFieldTop = tester.getTopLeft(find.text('B field')).dy;
      final aFieldTop = tester.getTopLeft(find.text('A field')).dy;
      expect(bFieldTop, lessThan(aFieldTop));
    });

    testWidgets(
      'the first field cannot move up and the last cannot move down',
      (tester) async {
        final server = _Server(
          fields: [
            _definition(
              id: 1,
              key: 'a_field',
              label: 'A field',
              displayOrder: 0,
            ),
            _definition(
              id: 2,
              key: 'b_field',
              label: 'B field',
              displayOrder: 1,
            ),
          ],
        );

        await tester.pumpWidget(_harness(server.client()));
        await tester.pumpAndSettle();

        final moveUpFirst = tester.widget<IconButton>(
          find.byKey(const Key('customer-field-1-move-up')),
        );
        expect(moveUpFirst.onPressed, isNull);

        final moveDownLast = tester.widget<IconButton>(
          find.byKey(const Key('customer-field-2-move-down')),
        );
        expect(moveDownLast.onPressed, isNull);
      },
    );
  });
}
