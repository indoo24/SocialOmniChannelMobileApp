/// Contact vs Customer data: the split between how you reach a customer and
/// what somebody recorded about them.
///
/// The distinction these pin down is the one that was previously wrong in the
/// mobile UI: "Customer data" means free-form recorded facts ("Age: 23"), not
/// the conversation's own metadata (status, priority, assignment, timestamps)
/// and not contact information. Contact keeps email/phone/location/language
/// and the custom fields; Customer data holds the facts; Orders is untouched
/// and stays its own section.
///
/// Everything goes through the existing API — `GET /customers/{id}/facts/`
/// and `POST /customers/{id}/facts/` — so a regression that invents an
/// endpoint or drops the real one fails here.
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
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_actions_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  List<RequestOptions> postsTo(String path) => received
      .where((r) => r.method == 'POST' && r.path.contains(path))
      .toList();

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

const _conversationJson = '''
{
  "id": 1,
  "customer": {
    "id": 42,
    "display_name": "Sarah Connor",
    "initials": "SC",
    "phone": "+123456789",
    "email": "sarah@example.com",
    "country": "Egypt",
    "city": "Cairo",
    "preferred_language": "ar"
  },
  "provider": "WHATSAPP",
  "channel_name": "Sales Line",
  "status": "OPEN",
  "priority": "NORMAL",
  "unread_count": 0,
  "message_count": 10
}
''';

/// Mirrors the web screenshot, including an Arabic key and a non-EMPLOYEE
/// source, so the source label cannot be hard-coded to "Employee".
const _factsJson = '''
[
  {"id": 1, "key": "Age", "value": "23", "source": "EMPLOYEE",
   "status": "CONFIRMED", "needs_review": false, "confidence": 1.0},
  {"id": 2, "key": "عنوان الغربية", "value": "طنطا طنطا", "source": "EMPLOYEE",
   "status": "CONFIRMED", "needs_review": false, "confidence": 1.0},
  {"id": 3, "key": "Num", "value": "01126737783", "source": "EMPLOYEE",
   "status": "CONFIRMED", "needs_review": false, "confidence": 1.0},
  {"id": 4, "key": "Adress", "value": "10 st.", "source": "ANALYZER",
   "status": "CONFIRMED", "needs_review": false, "confidence": 0.9},
  {"id": 5, "key": "pending_guess", "value": "ignore me", "source": "ANALYZER",
   "status": "SUGGESTED", "needs_review": true, "confidence": 0.4},
  {"id": 6, "key": "typed", "value": "field value", "source": "EMPLOYEE",
   "status": "CONFIRMED", "needs_review": false, "confidence": 1.0,
   "definition": 7}
]
''';

const _fieldsJson = '''
[
  {"definition": {"id": 7, "key": "loyalty_tier", "label": "Loyalty tier",
    "field_type": "TEXT", "is_required": false, "is_active": true,
    "options": [], "order": 1},
   "value": "Gold"}
]
''';

/// Many facts, to prove the sheet scrolls rather than overflowing.
String _manyFactsJson(int n) {
  final rows = [
    for (var i = 0; i < n; i++)
      '{"id": ${100 + i}, "key": "Detail $i", "value": "Value $i", '
          '"source": "EMPLOYEE", "status": "CONFIRMED", '
          '"needs_review": false, "confidence": 1.0}',
  ];
  return '[${rows.join(',')}]';
}

Employee _employee({
  Set<String> permissions = const {Perm.orderManage, Perm.customerManage},
}) {
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

({Widget widget, _StubAdapter adapter}) _harness({
  Employee? employee,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  String? factsJson,
  FutureOr<ResponseBody>? Function(RequestOptions)? extra,
}) {
  late final _StubAdapter adapter;
  adapter = _StubAdapter((options) {
    final fromExtra = extra?.call(options);
    if (fromExtra != null) return fromExtra;

    if (options.path.endsWith('/conversations/1/')) {
      return _json(_conversationJson, 200);
    }
    if (options.path.contains('/facts/')) {
      if (options.method == 'POST') {
        return _json(
          '{"id": 99, "key": "address", "value": "12 Nile St, Giza", '
          '"source": "EMPLOYEE", "status": "CONFIRMED", '
          '"needs_review": false, "confidence": 1.0}',
          201,
        );
      }
      return _json(factsJson ?? _factsJson, 200);
    }
    if (options.path.contains('/fields/')) return _json(_fieldsJson, 200);
    if (options.path.contains('/orders/')) {
      return _json('{"count": 0, "results": []}', 200);
    }
    return _json('{}', 200);
  });

  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;

  final widget = ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      cookieJarProvider.overrideWithValue(CookieJar()),
      currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
    ],
    child: MaterialApp(
      locale: locale,
      theme: theme ?? AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showConversationActionsSheet(context, conversationId: 1),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    ),
  );

  return (widget: widget, adapter: adapter);
}

Future<void> _openSheet(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
}

Future<void> _openCustomerData(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.chevron_right).first);
  await tester.pumpAndSettle();
}

void _sizeFor(WidgetTester tester, {Size size = const Size(900, 2400)}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('Contact section', () {
    testWidgets('1. displays contact information', (tester) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);

      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('Customer details'), findsNothing);

      // Email / Phone / Location / Language — the reach-the-customer facts.
      expect(find.text('sarah@example.com'), findsOneWidget);
      expect(find.text('+123456789'), findsOneWidget);
      expect(find.text('Cairo, Egypt'), findsOneWidget);
      expect(find.text('ar'), findsOneWidget);
    });

    testWidgets('2. Edit opens the existing edit customer flow', (
      tester,
    ) async {
      _sizeFor(tester);
      var detailFetched = false;
      final h = _harness(
        extra: (options) {
          if (options.method == 'GET' &&
              options.path.endsWith('/customers/42/')) {
            detailFetched = true;
            return _json('''
{"id": 42, "display_name": "Sarah Connor", "initials": "SC",
 "phone": "+123456789", "email": "sarah@example.com",
 "country": "Egypt", "city": "Cairo", "facts": [], "notes": []}
''', 200);
          }
          return null;
        },
      );
      await _openSheet(tester, h.widget);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      // The existing sheet, reached through the existing GET — not a new form.
      expect(detailFetched, isTrue);
      expect(find.text('Edit customer'), findsOneWidget);
    });

    testWidgets('3. custom fields appear under Contact', (tester) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);

      expect(find.text('Custom fields'), findsOneWidget);
      expect(find.text('Loyalty tier'), findsOneWidget);
      expect(find.text('Gold'), findsOneWidget);
    });

    testWidgets('does not show conversation metadata under Customer data', (
      tester,
    ) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      // Status/priority/assignment describe the thread, not the customer, so
      // they must not have followed the facts into this sheet. They stay in
      // the conversation sheet underneath, which is why this is scoped to the
      // Customer data sheet's own subtree rather than the whole tree.
      final sheet = find
          .ancestor(
            of: find.textContaining('Age: 23').last,
            matching: find.byType(ListView),
          )
          .last;
      for (final label in const [
        'Status',
        'Priority',
        'Assigned to',
        'Messages',
        'Started',
        'Last message',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.text(label)),
          findsNothing,
          reason: '"$label" is conversation metadata, not customer data',
        );
      }
    });
  });

  group('Customer data sheet', () {
    testWidgets('4 & 5. opens and shows the details the API returned', (
      tester,
    ) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      expect(find.text('Customer data'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Age: 23'), findsAtLeastNWidgets(1));
      expect(
        find.textContaining('عنوان الغربية: طنطا طنطا'),
        findsAtLeastNWidgets(1),
      );
      expect(find.textContaining('Num: 01126737783'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Adress: 10 st.'), findsAtLeastNWidgets(1));
    });

    testWidgets('excludes typed-field values and unreviewed guesses', (
      tester,
    ) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      // A custom field's value belongs under its field in Contact, not loose
      // in this list where it would appear twice.
      expect(find.textContaining('Typed: field value'), findsNothing);

      // An analyzer guess nobody has accepted stays in the Orders review
      // tray. Scoped to this sheet: the tray legitimately renders it further
      // down the conversation sheet underneath.
      final sheet = find.ancestor(
        of: find.textContaining('Age: 23').last,
        matching: find.byType(ListView),
      );
      expect(
        find.descendant(
          of: sheet.last,
          matching: find.textContaining('ignore me'),
        ),
        findsNothing,
      );
    });

    testWidgets('9. shows the source the API reported, not a fixed label', (
      tester,
    ) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      // EMPLOYEE is localized; ANALYZER is shown as its own source.
      expect(find.text('Employee'), findsAtLeastNWidgets(3));
      expect(find.text('Analyzer'), findsAtLeastNWidgets(1));
    });

    testWidgets('13. a long list scrolls', (tester) async {
      _sizeFor(tester, size: const Size(800, 1400));
      final h = _harness(factsJson: _manyFactsJson(40));
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Detail 0:'), findsAtLeastNWidgets(1));

      // Row 30 is far below the fold: it only exists once the list scrolls,
      // which is the point — a Column would have overflowed instead.
      expect(find.textContaining('Detail 30:'), findsNothing);
      await tester.fling(
        find.byType(ListView).last,
        const Offset(0, -2000),
        2000,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Detail 30:'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an empty state when there are no recorded details', (
      tester,
    ) async {
      _sizeFor(tester);
      final h = _harness(factsJson: '[]');
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      expect(
        find.text('No customer details recorded yet.'),
        findsAtLeastNWidgets(1),
      );
    });
  });

  group('Recording a detail', () {
    testWidgets('6 & 7 & 8. + Detail records through the existing API and the '
        'new detail appears', (tester) async {
      _sizeFor(tester);
      var factsCalls = 0;
      final h = _harness(
        extra: (options) {
          if (options.method == 'GET' && options.path.contains('/facts/')) {
            factsCalls++;
            // After the POST, the refetch includes the new row.
            return _json(
              factsCalls > 1
                  ? '''
[{"id": 99, "key": "address", "value": "12 Nile St, Giza",
  "source": "EMPLOYEE", "status": "CONFIRMED", "needs_review": false,
  "confidence": 1.0}]
'''
                  : '[]',
              200,
            );
          }
          return null;
        },
      );
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Detail'));
      await tester.pumpAndSettle();

      // 6. The existing dialog, with its existing copy.
      expect(find.text('Record a customer detail'), findsOneWidget);
      expect(
        find.text(
          'Something the customer shared — an address, a phone number, a '
          'preference.',
        ),
        findsOneWidget,
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'address');
      await tester.enterText(fields.last, '12 Nile St, Giza');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // 7. Exactly the existing endpoint and payload.
      final posts = h.adapter.postsTo('/customers/42/facts/');
      expect(posts, hasLength(1));
      final body = posts.single.data as Map;
      expect(body['key'], 'address');
      expect(body['value'], '12 Nile St, Giza');
      expect(body['conversation'], 1);

      // 8. The saved detail is on screen.
      expect(
        find.textContaining('Address: 12 Nile St, Giza'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('+ Detail is hidden without order.manage', (tester) async {
      _sizeFor(tester);
      final h = _harness(employee: _employee(permissions: const {}));
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      expect(find.widgetWithText(TextButton, 'Detail'), findsNothing);
    });
  });

  group('Orders stays separate', () {
    testWidgets('10. Orders is still its own section', (tester) async {
      _sizeFor(tester);
      final h = _harness();
      await _openSheet(tester, h.widget);

      await tester.scrollUntilVisible(
        find.text('Orders'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Orders'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Order'), findsOneWidget);
    });
  });

  group('Localization and theming', () {
    testWidgets('11. Arabic renders RTL with translated titles', (
      tester,
    ) async {
      _sizeFor(tester);
      final h = _harness(locale: const Locale('ar'));
      await _openSheet(tester, h.widget);

      expect(find.text('جهة الاتصال'), findsOneWidget);
      expect(find.text('بيانات العميل'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('بيانات العميل'))),
        TextDirection.rtl,
      );

      await _openCustomerData(tester);
      expect(find.textContaining('طنطا طنطا'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. dark theme renders without error', (tester) async {
      _sizeFor(tester);
      final h = _harness(theme: AppTheme.dark);
      await _openSheet(tester, h.widget);
      await _openCustomerData(tester);

      expect(find.text('Customer data'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('14. narrow 320px width does not overflow', (tester) async {
      _sizeFor(tester, size: const Size(320, 1200));
      final h = _harness();
      await _openSheet(tester, h.widget);
      expect(tester.takeException(), isNull);

      await _openCustomerData(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Age: 23'), findsAtLeastNWidgets(1));
    });
  });
}
