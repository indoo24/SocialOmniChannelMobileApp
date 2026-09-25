/// Regression: toggling a Customer Field's active state (or adding/editing
/// one) in Settings must be reflected immediately in the Customers screen's
/// "Filter by field…" picker — no app restart, no stale list.
///
/// The bug: `customerFieldDefinitionsProvider` (Settings' admin list, active
/// + inactive) and `activeCustomerFieldDefinitionsProvider` (the Customers
/// filter picker's list, active only) both wrap the same
/// `GET /customer-fields/` call, but Settings' mutations only invalidated the
/// first — so the picker kept serving whatever it had cached the first time
/// it was opened, until the process restarted. Fixed by invalidating both
/// providers on every mutation (toggle, reorder, add, edit).
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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/customer_fields/customer_fields_settings_screen.dart';
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
  bool isActive = true,
  int displayOrder = 0,
}) => {
  'id': id,
  'key': key,
  'label': label,
  'field_type': 'TEXT',
  'field_type_display': 'Text',
  'options': const [],
  'required': false,
  'is_active': isActive,
  'display_order': displayOrder,
  'help_text': '',
  'placeholder': '',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

/// A mutable in-memory field list, exactly like
/// `customer_field_definitions_test.dart`'s `_Server` — `GET` reflects
/// whatever the field list currently is (filtered by `include_inactive` the
/// way the real endpoint documents), and `PATCH` actually mutates it, so a
/// toggle in one screen is visible to whichever screen asks next.
class _Server {
  _Server(this.fields);

  List<Map<String, Object?>> fields;
  final List<RequestOptions> received = [];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) {
      received.add(options);
      final path = options.path;

      if (path == '/customer-fields/' && options.method == 'GET') {
        final includeInactive =
            options.queryParameters['include_inactive'] == true;
        final visible = includeInactive
            ? fields
            : fields.where((f) => f['is_active'] == true).toList();
        return _json(visible);
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
      if (path == '/customers/' && options.method == 'GET') {
        return _json({
          'count': 0,
          'next': null,
          'previous': null,
          'results': [],
        });
      }
      return _json({});
    });
    return client;
  }
}

Employee _employee() => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.customerView, Perm.customerFieldManage},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

/// Every field label this regression toggles — the closed menu list this
/// test checks against isn't the full universe of fields the backend could
/// ever return, just the two the bug report names.
const _allKnownFieldLabels = ['أهلا', 'عايز تشتري'];

/// Opens the Customers "Filter by field…" sheet and its field dropdown, and
/// returns the subset of [_allKnownFieldLabels] actually offered as menu
/// items, then dismisses the sheet — leaving the screen clean for the next
/// step. Matches `customer_field_definitions_test.dart`'s own way of reading
/// an open `DropdownButtonFormField` menu (`find.text`, not enumerating
/// `DropdownMenuItem` widgets, whose `child` isn't reliably queryable once
/// Flutter's dropdown route wraps them).
Future<Set<String>> _openPickerAndReadOfferedFields(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('customer-field-filter-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('customer-field-filter-field-picker')));
  await tester.pumpAndSettle();

  final offered = {
    for (final label in _allKnownFieldLabels)
      if (find.text(label).evaluate().isNotEmpty) label,
  };

  // Close the dropdown menu, then the sheet.
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(CustomersScreen))).pop();
  await tester.pumpAndSettle();

  return offered;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'toggling fields in Settings updates the Customers filter picker without restarting',
    (tester) async {
      final server = _Server([
        _definition(id: 1, key: 'ahlan', label: 'أهلا', isActive: true),
        _definition(
          id: 2,
          key: 'aiz_tishtri',
          label: 'عايز تشتري',
          isActive: false,
          displayOrder: 1,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
      );
      addTearDown(container.dispose);

      Future<void> showCustomers() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CustomersScreen(),
          ),
        ),
      );

      Future<void> showSettings() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: CustomerFieldsSettingsTab()),
          ),
        ),
      );

      // 1. Start with أهلا enabled; verify it appears in Filter by field.
      await showCustomers();
      await tester.pumpAndSettle();
      expect(await _openPickerAndReadOfferedFields(tester), {'أهلا'});

      // 2. In Settings: disable أهلا, enable عايز تشتري.
      await showSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-2-toggle')));
      await tester.pumpAndSettle();

      // 3. Back on Customers, without restarting anything: the picker must
      // show the new configuration, not the one it first loaded.
      await showCustomers();
      await tester.pumpAndSettle();
      expect(
        await _openPickerAndReadOfferedFields(tester),
        {'عايز تشتري'},
        reason:
            'the picker must reflect the latest field configuration, '
            'not whatever it cached the first time it was opened',
      );

      // 4. Enable both — the picker should show both immediately.
      await showSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-toggle')));
      await tester.pumpAndSettle();

      await showCustomers();
      await tester.pumpAndSettle();
      expect(await _openPickerAndReadOfferedFields(tester), {
        'أهلا',
        'عايز تشتري',
      });

      // 5. Disable one again — the picker updates without an app restart.
      await showSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-2-toggle')));
      await tester.pumpAndSettle();

      await showCustomers();
      await tester.pumpAndSettle();
      expect(await _openPickerAndReadOfferedFields(tester), {'أهلا'});
    },
  );

  testWidgets(
    'applying a filter after a field was just re-enabled uses the new field, not a stale one',
    (tester) async {
      final server = _Server([
        _definition(id: 1, key: 'ahlan', label: 'أهلا', isActive: false),
      ]);

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
      );
      addTearDown(container.dispose);

      // Field starts disabled: the picker must be empty.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CustomersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-filter-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('No custom fields are set up for this organization.'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(CustomersScreen))).pop();
      await tester.pumpAndSettle();

      // Enable it from Settings.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: CustomerFieldsSettingsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-1-toggle')));
      await tester.pumpAndSettle();

      // Back on Customers: select the now-active field and apply a value —
      // the export/list request must carry the real, current field's key.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CustomersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customer-field-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('customer-field-filter-field-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('أهلا').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('customer-field-filter-value')),
        'hi',
      );
      await tester.tap(find.byKey(const Key('customer-field-filter-apply')));
      await tester.pumpAndSettle();

      final listRequest = server.received.lastWhere(
        (r) => r.path == '/customers/',
      );
      expect(listRequest.queryParameters['field__ahlan__contains'], 'hi');
    },
  );
}
