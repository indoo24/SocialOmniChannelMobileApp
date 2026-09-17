/// CSV export: `ApiClient.getBytes`, the Customers/Inbox export request
/// shape, and the Export CSV action on both screens — loading state, the
/// filtered query actually sent (not just the label), and error handling
/// including the 429 rate limit the backend documents.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/csv_export.dart';
import 'package:scenario_mobile/core/widgets/export_csv_action.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/customers_screen.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// `getTemporaryDirectory()` behind a real, test-scratch folder — the export
/// flow genuinely writes a file, and this proves it produced real bytes
/// rather than mocking the write away entirely.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getTemporaryPath() async => directory.path;
}

/// Captures what the app tried to share instead of invoking a real share
/// sheet, which has no platform channel handler under `flutter test`.
class _FakeSharePlatform extends SharePlatform {
  final List<ShareParams> shared = [];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
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

ResponseBody _csv(String text, [int status = 200]) {
  final bom = [0xEF, 0xBB, 0xBF];
  final bytes = [...bom, ...utf8.encode(text)];
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/csv'],
    },
  );
}

ResponseBody _jsonError(String message, int status) => ResponseBody.fromString(
  jsonEncode({
    'error': {
      'code': status == 429 ? 'rate_limited' : 'error',
      'message': message,
    },
  }),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ApiClient _clientFrom(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Employee _employee({Set<String> permissions = const {}}) => Employee(
  id: 7,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeSharePlatform fakeShare;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('csv_export_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    fakeShare = _FakeSharePlatform();
    SharePlatform.instance = fakeShare;
  });

  tearDown(() async {
    // Best-effort only: Windows can briefly hold the file open past the
    // share call returning, and leaking a scratch temp dir between test
    // runs is harmless — failing the test over cleanup is not.
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on Object {
      // Ignored.
    }
  });

  group('ApiClient.getBytes', () {
    test('returns the raw bytes on success, BOM included', () async {
      final adapter = _StubAdapter((options) => _csv('a,b\n1,2\n'));
      final client = _clientFrom(adapter);

      final bytes = await client.getBytes('/conversations/export/');

      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.sublist(3)), 'a,b\n1,2\n');
    });

    test(
      'decodes a JSON error body even though bytes were requested',
      () async {
        final adapter = _StubAdapter(
          (options) => _jsonError('Too many exports in the last minute.', 429),
        );
        final client = _clientFrom(adapter);

        await expectLater(
          client.getBytes('/conversations/export/'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 429)
                .having(
                  (e) => e.message,
                  'message',
                  'Too many exports in the last minute.',
                ),
          ),
        );
      },
    );

    test(
      'a 403 permission_denied surfaces as an ordinary ApiException',
      () async {
        final adapter = _StubAdapter(
          (options) =>
              _jsonError('You do not have permission to do that.', 403),
        );
        final client = _clientFrom(adapter);

        await expectLater(
          client.getBytes('/customers/export/'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
          ),
        );
      },
    );

    test('forwards query parameters unchanged', () async {
      RequestOptions? captured;
      final adapter = _StubAdapter((options) {
        captured = options;
        return _csv('a\n1\n');
      });
      final client = _clientFrom(adapter);

      await client.getBytes(
        '/conversations/export/',
        query: {'status': 'OPEN', 'search': 'sara'},
      );

      expect(captured!.queryParameters['status'], 'OPEN');
      expect(captured!.queryParameters['search'], 'sara');
    });
  });

  group('Inbox — Export CSV action', () {
    testWidgets('is no longer displayed on InboxScreen even with crm.export', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) => _csv('id\n'));
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _employee(permissions: {Perm.conversationView, Perm.crmExport}),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const InboxScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-csv-menu')), findsNothing);
    });

    testWidgets('sends the currently active filters, not the whole inbox', (
      tester,
    ) async {
      final requests = <RequestOptions>[];
      final adapter = _StubAdapter((options) {
        requests.add(options);
        if (options.path == '/conversations/export/') {
          return _csv('id,title\n1,Hello\n');
        }
        return _csv('', 200);
      });
      final client = _clientFrom(adapter);

      final router = GoRouter(
        initialLocation: '/inbox',
        routes: [
          GoRoute(path: '/inbox', builder: (_, _) => const InboxScreen()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _employee(permissions: {Perm.conversationView, Perm.crmExport}),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Activate the Unread quick filter before exporting.
      await tester.tap(find.byKey(const Key('quick_filter_unread')));
      await tester.pumpAndSettle();
      requests.clear();

      // Drive `exportCsvAndShare` directly with the same repository call the
      // Export CSV menu item wires up, using the currently-active filters
      // read from the live provider state — this exercises the real
      // filter-forwarding and file-write/share code without tapping through
      // `ExportCsvAction`'s `PopupMenuButton`, whose interaction sequence
      // hangs `pumpAndSettle` on the real `dart:io` write it triggers (a
      // widget-test-only limitation, confirmed not to reproduce with
      // `dart run` outside `flutter test`).
      final context = tester.element(find.byType(InboxScreen));
      final container = ProviderScope.containerOf(context);
      final filters = container.read(inboxFiltersProvider);
      final employee = container.read(currentEmployeeProvider);

      await tester.runAsync(() async {
        await exportCsvAndShare(
          context,
          fileNamePrefix: 'conversations',
          fetch: () => container
              .read(conversationRepositoryProvider)
              .exportCsv(filters: filters, currentEmployeeId: employee?.id),
        );
      });
      await tester.pumpAndSettle();

      final exportReq = requests.firstWhere(
        (r) => r.path == '/conversations/export/',
      );
      expect(exportReq.queryParameters['unread'], true);
      // The export must never carry pagination — every matching row, not a page.
      expect(exportReq.queryParameters.containsKey('page'), isFalse);
      expect(exportReq.queryParameters.containsKey('page_size'), isFalse);
      expect(fakeShare.shared, hasLength(1));
    });

    testWidgets('shows the rate-limit message on a 429', (tester) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/conversations/export/') {
          return _jsonError('Too many exports in the last minute.', 429);
        }
        return _csv('', 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _employee(permissions: {Perm.conversationView, Perm.crmExport}),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ExportCsvAction(
                  fileNamePrefix: 'conversations',
                  fetch: () =>
                      ref.read(conversationRepositoryProvider).exportCsv(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-csv-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-csv-item')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Too many exports in the last minute. Please wait and try again.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Customers — Export CSV action', () {
    testWidgets(
      'is no longer displayed on CustomersScreen even with crm.export',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.path == '/customers/') {
            return ResponseBody.fromString(
              jsonEncode({
                'count': 0,
                'next': null,
                'previous': null,
                'results': [],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return _csv('', 200);
        });
        final client = _clientFrom(adapter);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(
                _employee(permissions: {Perm.customerView, Perm.crmExport}),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const CustomersScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('export-csv-menu')), findsNothing);
      },
    );

    testWidgets('sends the active search filter on export', (tester) async {
      final requests = <RequestOptions>[];
      final adapter = _StubAdapter((options) {
        requests.add(options);
        if (options.path == '/customers/') {
          return ResponseBody.fromString(
            jsonEncode({
              'count': 0,
              'next': null,
              'previous': null,
              'results': [],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (options.path == '/customers/export/') {
          return _csv('id,name\n1,Sara\n');
        }
        return _csv('', 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _employee(permissions: {Perm.customerView, Perm.crmExport}),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CustomersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open search, type, submit — matching the existing search-field flow.
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sara');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      requests.clear();

      // Drive `exportCsvAndShare` directly (see the matching Inbox test for
      // why: tapping through `ExportCsvAction`'s `PopupMenuButton` triggers a
      // real `dart:io` write that never resolves under `pumpAndSettle`).
      final context = tester.element(find.byType(CustomersScreen));
      final container = ProviderScope.containerOf(context);
      final search = container.read(customerSearchProvider);

      await tester.runAsync(() async {
        await exportCsvAndShare(
          context,
          fileNamePrefix: 'customers',
          fetch: () => container
              .read(directoryRepositoryProvider)
              .exportCustomersCsv(search: search),
        );
      });
      await tester.pumpAndSettle();

      final exportReq = requests.firstWhere(
        (r) => r.path == '/customers/export/',
      );
      expect(exportReq.queryParameters['search'], 'sara');
      expect(exportReq.queryParameters.containsKey('page'), isFalse);
      expect(fakeShare.shared, hasLength(1));
    });

    testWidgets('a generic failure shows the fallback export error', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.path == '/customers/') {
          return ResponseBody.fromString(
            jsonEncode({
              'count': 0,
              'next': null,
              'previous': null,
              'results': [],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (options.path == '/customers/export/') {
          return _jsonError('Internal Server Error', 500);
        }
        return _csv('', 200);
      });
      final client = _clientFrom(adapter);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(
              _employee(permissions: {Perm.customerView, Perm.crmExport}),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ExportCsvAction(
                  fileNamePrefix: 'customers',
                  fetch: () => ref
                      .read(directoryRepositoryProvider)
                      .exportCustomersCsv(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-csv-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-csv-item')));
      await tester.pumpAndSettle();

      expect(find.text('Internal Server Error'), findsOneWidget);
    });
  });

  group('ExportCsvAction widget', () {
    testWidgets('shows a spinner while the export is in flight', (
      tester,
    ) async {
      // Reject rather than resolve to bytes: `_exporting` is driven purely by
      // `fetch()`'s lifecycle (see `ExportCsvAction`'s try/finally), so an
      // error still exercises the spinner showing/hiding without ever
      // reaching the real `dart:io` file write — that write's Future never
      // resolves under `pumpAndSettle` when triggered from inside a tapped
      // widget interaction, even wrapped in `runAsync` (a widget-test-only
      // limitation; the same write completes normally outside `flutter
      // test`). The write/share path itself is covered directly by the
      // Inbox/Customers export tests above, which call `exportCsvAndShare`
      // as a plain function under `runAsync`.
      final completer = Completer<List<int>>();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExportCsvAction(
              fileNamePrefix: 'test',
              fetch: () => completer.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-csv-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-csv-item')));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
