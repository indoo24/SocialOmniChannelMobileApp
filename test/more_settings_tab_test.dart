import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/directory/customers_screen.dart';
import 'package:scenario_mobile/features/settings/more_settings_tab.dart';
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getTemporaryPath() async => directory.path;
}

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

ResponseBody _json(dynamic body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

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

final _sampleCustomerFields = [
  {
    'id': 1,
    'key': 'vip_status',
    'label': 'VIP Status',
    'field_type': 'TEXT',
    'is_required': false,
    'is_active': true,
    'order': 1,
  },
  {
    'id': 2,
    'key': 'account_balance',
    'label': 'Account Balance',
    'field_type': 'NUMBER',
    'is_required': false,
    'is_active': false,
    'order': 2,
  },
];

final _sampleSavedReplies = [
  {
    'id': 1,
    'public_id': 'uuid-1',
    'title': 'Greeting',
    'shortcut': 'hello',
    'body': 'Hello! How can I help you today?',
    'scope': 'organization',
    'category': 'General',
    'is_active': true,
    'can_edit': true,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  },
  {
    'id': 2,
    'public_id': 'uuid-2',
    'title': 'Pricing',
    'shortcut': 'price',
    'body': 'Our pricing details can be found on our website.',
    'scope': 'personal',
    'category': 'Sales',
    'is_active': true,
    'can_edit': true,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  },
];

Employee _employeeWithPermissions(Set<String> perms) => Employee(
  id: 7,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: perms,
  visibilityScope: 'ALL',
);

final _fullAdmin = _employeeWithPermissions({
  Perm.channelView,
  Perm.channelManage,
  Perm.routingManage,
  Perm.customerFieldManage,
  Perm.savedReplyManage,
  Perm.crmExport,
  Perm.conversationView,
  Perm.conversationReply,
  Perm.customerView,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeSharePlatform fakeShare;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('more_settings_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    fakeShare = _FakeSharePlatform();
    SharePlatform.instance = fakeShare;
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    fakeShare.shared.clear();
  });

  Widget createHarness({
    required ApiClient apiClient,
    Employee? employee,
    Locale locale = const Locale('en'),
    ThemeData? theme,
    Widget? home,
  }) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        currentEmployeeProvider.overrideWithValue(employee ?? _fullAdmin),
        cookieJarProvider.overrideWithValue(CookieJar()),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light,
        home: home ?? const SettingsScreen(),
      ),
    );
  }

  _StubAdapter defaultAdapter({
    FutureOr<ResponseBody>? Function(RequestOptions)? onRequest,
  }) {
    return _StubAdapter((options) {
      if (onRequest != null) {
        final handled = onRequest(options);
        if (handled != null) return handled;
      }
      if (options.path == '/customer-fields/') {
        return _json(_sampleCustomerFields);
      }
      if (options.path == '/saved-replies/') {
        return _json({
          'count': _sampleSavedReplies.length,
          'next': null,
          'previous': null,
          'results': _sampleSavedReplies,
        });
      }
      if (options.path == '/channels/') {
        return _json({'results': [], 'count': 0});
      }
      if (options.path == '/routing/policy/') {
        return _json({
          'is_enabled': true,
          'max_open_chats_per_agent': 200,
          'timezone': 'UTC',
          'heartbeat_max_seconds': 0,
          'first_response_sla_seconds': 300,
          'sticky_conversation_ownership': false,
          'escalation_max_hops': 3,
        });
      }
      if (options.path == '/conversations/export/') {
        return _csv('id,status\n1,OPEN\n');
      }
      if (options.path == '/customers/export/') {
        return _csv('id,name\n1,Alice\n');
      }
      return _json({}, 200);
    });
  }

  group('Settings Navigation & Tab Bar', () {
    testWidgets('Settings tabs are Channels, Routing, More settings, Profile', (
      tester,
    ) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createHarness(apiClient: client));
      await tester.pumpAndSettle();

      // Check the 4 tabs in order
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Routing'), findsOneWidget);
      expect(find.text('More settings'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      // Security is no longer a tab — it is a section inside Profile.
      expect(find.widgetWithText(Tab, 'Security'), findsNothing);

      // Separate Customer fields and Saved replies tabs are removed from TabBar
      expect(find.widgetWithText(Tab, 'Customer fields'), findsNothing);
      expect(find.widgetWithText(Tab, 'Saved replies'), findsNothing);
    });

    testWidgets(
      'Tab bar scrolls horizontally on narrow mobile screens (320px)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = defaultAdapter();
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(createHarness(apiClient: client));
        await tester.pumpAndSettle();

        // No RenderFlex overflow
        expect(tester.takeException(), isNull);

        // Scroll the tab bar to reveal the More settings tab
        await tester.drag(find.byType(TabBar), const Offset(-250, 0));
        await tester.pumpAndSettle();

        // More settings tab is accessible
        final moreSettingsTab = find.text('More settings');
        expect(moreSettingsTab, findsOneWidget);
        await tester.tap(moreSettingsTab);
        await tester.pumpAndSettle();

        expect(find.byType(MoreSettingsTab), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('More Settings Tab — Content & Sections', () {
    testWidgets(
      'Displays Customer fields, Saved replies, and Export data sections',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adapter = defaultAdapter();
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await tester.pumpWidget(createHarness(apiClient: client));
        await tester.pumpAndSettle();

        // Switch to More settings tab
        await tester.tap(find.text('More settings'));
        await tester.pumpAndSettle();

        // Section A: Customer fields
        expect(find.text('Customer fields'), findsWidgets);
        expect(find.text('VIP Status'), findsOneWidget);
        expect(find.text('Account Balance'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Add field'), findsOneWidget);

        // Section B: Saved replies
        expect(find.text('Saved replies'), findsWidgets);
        expect(find.text('Greeting'), findsOneWidget);
        expect(find.text('Pricing'), findsOneWidget);
        expect(find.byKey(const Key('add-saved-reply')), findsOneWidget);

        // Section C: Export data
        expect(find.text('Export data'), findsOneWidget);
        expect(
          find.text('Export your application data as CSV files.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('export-conversations-csv-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('export-customers-csv-button')),
          findsOneWidget,
        );
      },
    );

    testWidgets('Tapping Add field opens the Customer field dialog', (
      tester,
    ) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-customer-field')));
      await tester.pumpAndSettle();

      // Verify the Add field sheet is opened
      expect(find.text('Key'), findsOneWidget);
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
    });

    testWidgets('Tapping New reply opens the Saved reply dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-saved-reply')));
      await tester.pumpAndSettle();

      // Verify the New reply sheet is opened
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Shortcut'), findsOneWidget);
      expect(find.byKey(const Key('saved-reply-form-body')), findsOneWidget);
    });
  });

  group('Export Data in More Settings', () {
    testWidgets('Export conversations CSV triggers API and shares CSV file', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      // Tap Export conversations CSV under runAsync for real IO
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const Key('export-conversations-csv-button')),
        );
        // Allow async fetch and file write to complete
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Verify that the /conversations/export/ endpoint was called
      final exportReq = adapter.received.firstWhere(
        (r) => r.path == '/conversations/export/',
      );
      expect(exportReq, isNotNull);
      expect(fakeShare.shared, hasLength(1));
    });

    testWidgets('Export customers CSV triggers API and shares CSV file', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('export-customers-csv-button')));
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      final exportReq = adapter.received.firstWhere(
        (r) => r.path == '/customers/export/',
      );
      expect(exportReq, isNotNull);
      expect(fakeShare.shared, hasLength(1));
    });

    testWidgets('Export error displays error SnackBar', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = defaultAdapter(
        onRequest: (options) {
          if (options.path == '/conversations/export/') {
            return _jsonError('Rate limited. Please wait.', 429);
          }
          return null;
        },
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(createHarness(apiClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('export-conversations-csv-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Too many exports in the last minute. Please wait and try again.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Permission Gating', () {
    testWidgets('Employee without crm.export cannot trigger exports', (
      tester,
    ) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final limitedEmployee = _employeeWithPermissions({
        Perm.customerFieldManage,
        Perm.customerView,
        Perm.savedReplyManage,
        Perm.conversationReply,
      });

      await tester.pumpWidget(
        createHarness(apiClient: client, employee: limitedEmployee),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      // Export section is omitted when user lacks crm.export
      expect(find.text('Export data'), findsNothing);
      expect(find.text('Export conversations CSV'), findsNothing);
      expect(find.text('Export customers CSV'), findsNothing);
    });

    testWidgets('Employee without any more settings permissions sees no tab', (
      tester,
    ) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final minimalEmployee = _employeeWithPermissions({Perm.channelView});

      await tester.pumpWidget(
        createHarness(apiClient: client, employee: minimalEmployee),
      );
      await tester.pumpAndSettle();

      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('More settings'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Security'), findsNothing);
    });
  });

  group('Export actions removed from Inbox and Customers', () {
    testWidgets('InboxScreen does not display Export button', (tester) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(
        createHarness(apiClient: client, home: const InboxScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-csv-menu')), findsNothing);
      expect(find.text('Export CSV'), findsNothing);
    });

    testWidgets('CustomersScreen does not display Export button', (
      tester,
    ) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(
        createHarness(apiClient: client, home: const CustomersScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-csv-menu')), findsNothing);
      expect(find.text('Export CSV'), findsNothing);
    });
  });

  group('Arabic (RTL), Narrow Screens & Dark Theme', () {
    testWidgets('Arabic RTL renders properly without overflow', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(
        createHarness(apiClient: client, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      // Arabic More settings tab
      final moreSettingsTab = find.text('إعدادات إضافية');
      expect(moreSettingsTab, findsOneWidget);
      await tester.tap(moreSettingsTab);
      await tester.pumpAndSettle();

      // Arabic section titles
      expect(find.text('حقول العملاء'), findsWidgets);
      expect(find.text('الردود المحفوظة'), findsWidgets);
      expect(find.text('تصدير البيانات'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Narrow screen 320px in Arabic RTL has no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(
        createHarness(apiClient: client, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(TabBar), const Offset(250, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إعدادات إضافية'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Dark theme renders properly', (tester) async {
      final adapter = defaultAdapter();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await tester.pumpWidget(
        createHarness(apiClient: client, theme: AppTheme.dark),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('More settings'));
      await tester.pumpAndSettle();

      expect(find.byType(MoreSettingsTab), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
