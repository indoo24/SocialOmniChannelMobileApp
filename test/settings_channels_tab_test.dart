/// Tests for Settings > Channels tab:
/// - Dynamic grouping by provider/platform (multiple channels in one platform card)
/// - Direct visible action buttons on each channel card (NO 3-dot overflow menu)
/// - Platform-level actions (Connect another number, Connect another account, Reconnect)
/// - Connected/degraded/error/disconnected status badges
/// - Token days remaining display
/// - Test action (loading state, snackbar, no double-submit)
/// - Mute/unmute action
/// - Disconnect confirmation dialog and provider-specific endpoint calls
/// - WhatsApp-only "Check status" action
/// - Hide/Show: local-only, no API call, available without channel.manage
/// - Permission gating (channel.manage gates write actions; viewer only sees Hide)
/// - Layout resilience (narrow phone width, long channel names, no RenderFlex overflow)
/// - Light and dark themes
/// - Arabic locale (RTL) rendering
/// - Loading, error, and empty states
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
import 'package:scenario_mobile/features/settings/settings_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];
  bool launchSucceeds = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return launchSucceeds;
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

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final _managerEmployee = Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin User',
  initials: 'AU',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {Perm.channelView, Perm.channelManage},
  visibilityScope: 'ALL',
);

final _viewerEmployee = Employee(
  id: 2,
  email: 'supervisor@acme.test',
  fullName: 'Supervisor User',
  initials: 'SU',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

String _channelsPage(List<String> channelsJson) =>
    '{"count": ${channelsJson.length}, "next": null, "previous": null, "results": [${channelsJson.join(',')}]}';

const _whatsappChannel = '''
{
  "id": 5,
  "provider": "WHATSAPP",
  "provider_display": "WhatsApp Business",
  "display_name": "Support line",
  "external_account_id": "1234567890",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "",
  "conversation_count": 12,
  "is_muted": false,
  "has_credentials": true,
  "is_operational": true,
  "connected_at": "2026-06-01T09:00:00Z",
  "last_message_at": "2026-09-02T08:00:00Z"
}
''';

const _whatsappChannel2 = '''
{
  "id": 6,
  "provider": "WHATSAPP",
  "provider_display": "WhatsApp Business",
  "display_name": "Sales line",
  "external_account_id": "1234567891",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "",
  "conversation_count": 5,
  "is_muted": false,
  "has_credentials": true,
  "is_operational": true,
  "token_days_remaining": 43,
  "connected_at": "2026-08-18T08:26:00Z",
  "last_message_at": "2026-09-03T12:00:00Z"
}
''';

const _instagramChannel = '''
{
  "id": 7,
  "provider": "INSTAGRAM",
  "provider_display": "Instagram",
  "display_name": "Acme Shop",
  "external_account_id": "17800000000000000",
  "status": "DEGRADED",
  "is_active": true,
  "status_detail": "Token expiring soon.",
  "conversation_count": 4,
  "is_muted": true,
  "muted_by_name": "Mona",
  "has_credentials": true,
  "is_operational": true
}
''';

const _facebookChannel1 = '''
{
  "id": 10,
  "provider": "FACEBOOK",
  "provider_display": "Facebook Messenger",
  "display_name": "Gadiat - جاديات",
  "external_account_id": "102174258212607",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "",
  "conversation_count": 1,
  "is_muted": false,
  "has_credentials": true,
  "is_operational": true
}
''';

const _facebookChannel2 = '''
{
  "id": 11,
  "provider": "FACEBOOK",
  "provider_display": "Facebook Messenger",
  "display_name": "Gado Tex جادو تكس",
  "external_account_id": "682298908899556",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "",
  "conversation_count": 2,
  "is_muted": false,
  "has_credentials": true,
  "is_operational": true
}
''';

const _tiktokChannel = '''
{
  "id": 15,
  "provider": "TIKTOK",
  "provider_display": "TikTok",
  "display_name": "Acme TikTok",
  "external_account_id": "tt_12345",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "",
  "conversation_count": 0,
  "is_muted": false,
  "has_credentials": true,
  "is_operational": true
}
''';

Widget _settingsHarness({
  required ApiClient apiClient,
  Employee? employee,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(employee ?? _managerEmployee),
      cookieJarProvider.overrideWithValue(CookieJar()),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? AppTheme.light,
      home: const SettingsScreen(),
    ),
  );
}

Future<void> _pumpChannelsTab(
  WidgetTester tester, {
  required ApiClient apiClient,
  Employee? employee,
  Locale locale = const Locale('en'),
  ThemeData? theme,
  Size size = const Size(390, 1600),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    _settingsHarness(
      apiClient: apiClient,
      employee: employee,
      locale: locale,
      theme: theme,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen — Channels tab rendering & platform grouping', () {
    testWidgets('shows the empty state when no channels are connected', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage(const []), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('No channels connected'), findsOneWidget);
    });

    testWidgets('renders connected channels with status and identifier', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel, _instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('WhatsApp Business'), findsOneWidget);
      expect(find.text('Support line'), findsOneWidget);
      expect(find.text('ID: 1234567890'), findsOneWidget);
      expect(find.text('Connected'), findsWidgets);
      expect(find.text('Degraded'), findsWidgets);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.text('Muted by Mona'), findsOneWidget);
    });

    testWidgets(
      'groups multiple channels of the same platform inside ONE parent card',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(
            _channelsPage([
              _whatsappChannel,
              _whatsappChannel2,
              _facebookChannel1,
              _facebookChannel2,
              _tiktokChannel,
            ]),
            200,
          ),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        // Exactly ONE parent platform card for WhatsApp
        expect(find.text('WhatsApp Business'), findsOneWidget);
        // Both WhatsApp numbers rendered inside
        expect(find.text('Support line'), findsOneWidget);
        expect(find.text('Sales line'), findsOneWidget);

        // Exactly ONE parent platform card for Facebook Messenger
        expect(find.text('Facebook Messenger'), findsOneWidget);
        // Both Facebook pages rendered inside
        expect(find.text('Gadiat - جاديات'), findsOneWidget);
        expect(find.text('Gado Tex جادو تكس'), findsOneWidget);

        // Exactly ONE parent platform card for TikTok
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text('TikTok'), findsOneWidget);
        expect(find.text('Acme TikTok'), findsOneWidget);

        // Token days remaining display
        expect(find.text('Access token: expires in 43 days'), findsOneWidget);

        // NO 3-dot overflow menu is present anywhere
        expect(find.byIcon(Icons.more_vert), findsNothing);
      },
    );

    testWidgets('does not overflow horizontally on a narrow phone width', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(
          _channelsPage([
            _whatsappChannel,
            _whatsappChannel2,
            _facebookChannel1,
            _instagramChannel,
          ]),
          200,
        ),
      );

      await _pumpChannelsTab(
        tester,
        apiClient: client,
        size: const Size(320, 1600),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('handles long channel names gracefully without overflow', (
      tester,
    ) async {
      const longNameChannel = '''
{
  "id": 99,
  "provider": "WHATSAPP",
  "provider_display": "WhatsApp Business",
  "display_name": "Extremely Long Channel Name That Might Wrap Over Multiple Lines In A Very Compact Mobile Layout 123456789",
  "external_account_id": "99999999999999999",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "Some detail description text that is also lengthy and descriptive.",
  "conversation_count": 999,
  "is_muted": false,
  "has_credentials": true,
  "is_operational": true
}
''';
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([longNameChannel]), 200),
      );

      await _pumpChannelsTab(
        tester,
        apiClient: client,
        size: const Size(320, 1600),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders properly in dark theme', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel, _instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client, theme: AppTheme.dark);

      expect(find.text('WhatsApp Business'), findsOneWidget);
      expect(find.text('Support line'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen — Channels tab permission gating', () {
    testWidgets(
      'channel.manage-only actions are hidden for a channel.view-only role',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );

        await _pumpChannelsTab(
          tester,
          apiClient: client,
          employee: _viewerEmployee,
        );

        expect(find.text('Test'), findsNothing);
        expect(find.text('Mute'), findsNothing);
        expect(find.text('Disconnect'), findsNothing);
        expect(find.byIcon(Icons.more_vert), findsNothing);
        // Hide is available without channel.manage (presentation-only)
        expect(find.text('Hide'), findsOneWidget);
      },
    );

    testWidgets(
      'write actions are directly visible for a channel.manage role',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        expect(find.text('Test'), findsOneWidget);
        expect(find.text('Mute'), findsOneWidget);
        expect(find.text('Hide'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);
        expect(find.text('Check status'), findsOneWidget);
        expect(find.text('Connect another number'), findsOneWidget);
        // No 3-dot overflow menu
        expect(find.byIcon(Icons.more_vert), findsNothing);
      },
    );
  });

  group('SettingsScreen — Channels tab: Test', () {
    testWidgets('shows a success snackbar and does not double-submit', (
      tester,
    ) async {
      var testCallCount = 0;
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path.contains('/test/')) {
          testCallCount++;
          return _json('{"ok": true, "detail": "Connection verified."}', 200);
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Test'));
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(testCallCount, 1);
      expect(find.text('Connection verified.'), findsOneWidget);
    });

    testWidgets('displays an error message when testing fails with 400', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path.contains('/test/')) {
          return _json(
            '{"error": {"code": "invalid", "message": "Channel is not reachable.", "details": {}}}',
            400,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('Channel is not reachable.'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channels tab: Mute/Unmute', () {
    testWidgets('Mute calls /channels/<id>/mute/ and refreshes', (
      tester,
    ) async {
      late final _StubAdapter adapter;
      adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path == '/channels/5/mute/') {
          return _json('''
{
  "id": 5, "provider": "WHATSAPP", "display_name": "Support line",
  "status": "CONNECTED", "is_active": true, "is_muted": true,
  "conversation_count": 12, "has_credentials": true, "is_operational": true
}
''', 200);
        }
        if (options.method == 'GET' && options.path == '/channels/') {
          final isMuted = adapter.received.any(
            (r) => r.method == 'POST' && r.path == '/channels/5/mute/',
          );
          return _json(
            _channelsPage([
              _whatsappChannel.replaceFirst(
                '"is_muted": false',
                '"is_muted": $isMuted',
              ),
            ]),
            200,
          );
        }
        return _json('{}', 404);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Mute'), findsOneWidget);
      await tester.tap(find.text('Mute'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) => r.method == 'POST' && r.path == '/channels/5/mute/',
        ),
        isTrue,
      );
      expect(find.text('Unmute'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channels tab: Disconnect', () {
    testWidgets('shows a confirmation dialog before disconnecting', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      // Disconnect button is directly tapped without 3-dot menu
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect Support line?'), findsOneWidget);
      expect(
        find.text(
          "This removes the stored credential. The conversation history "
          "stays, but no new messages can be sent or received on this "
          "channel until it's reconnected.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the dialog sends no request', (tester) async {
      final adapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any((r) => r.path.contains('/disconnect/')),
        isFalse,
      );
    });

    testWidgets(
      'confirming calls the WhatsApp-specific disconnect endpoint and refreshes',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path.contains('/disconnect/')) {
            return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
          }
          return _json(_channelsPage([_whatsappChannel]), 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await _pumpChannelsTab(tester, apiClient: client);

        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Disconnect').last);
        await tester.pumpAndSettle();

        expect(
          adapter.received.any(
            (r) =>
                r.method == 'POST' &&
                r.path == '/integrations/whatsapp/5/disconnect/',
          ),
          isTrue,
        );
        expect(find.text('Support line disconnected.'), findsOneWidget);
      },
    );

    testWidgets('disconnects Instagram via the Instagram-specific endpoint', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path.contains('/disconnect/')) {
          return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
        }
        return _json(_channelsPage([_instagramChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect').last);
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'POST' &&
              r.path == '/integrations/instagram/7/disconnect/',
        ),
        isTrue,
      );
    });

    testWidgets('a 403 on disconnect shows the server message, not a crash', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path.contains('/disconnect/')) {
          return _json(
            '{"error": {"code": "forbidden", "message": "You do not have permission to do that.", "details": {}}}',
            403,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect').last);
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to do that.'),
        findsOneWidget,
      );
    });
  });

  group('SettingsScreen — Channels tab: WhatsApp check-status', () {
    testWidgets('Check status appears only for WhatsApp channels', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Check status'), findsNothing);
    });

    testWidgets('tapping Check status POSTs to the check-status endpoint', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path.contains('/check-status/')) {
          return _json('''
{"id": 5, "display_name": "Support line", "status": "CONNECTED", "detail": "Ready."}
''', 200);
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      // Check status is directly visible
      expect(find.text('Check status'), findsOneWidget);
      await tester.tap(find.text('Check status'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'POST' &&
              r.path == '/integrations/whatsapp/5/check-status/',
        ),
        isTrue,
      );
      expect(find.text('Ready.'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channels tab: Connect another (Platform Actions)', () {
    testWidgets('WhatsApp card calls the mobile embedded-signup start endpoint', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path.contains('/embedded-signup/mobile/start/')) {
          return _json(
            '{"authorization_url": "https://business.facebook.com/wa/signup?x=1"}',
            200,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final fakeLauncher = _FakeUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Connect another number'), findsOneWidget);
      await tester.tap(find.text('Connect another number'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'POST' &&
              r.path == '/integrations/whatsapp/embedded-signup/mobile/start/',
        ),
        isTrue,
      );
      expect(fakeLauncher.launchedUrls, [
        'https://business.facebook.com/wa/signup?x=1',
      ]);
    });

    testWidgets('Instagram card calls the Instagram authorize endpoint', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path.contains('/instagram/authorize/')) {
          return _json(
            '{"authorization_url": "https://instagram.com/oauth/authorize?x=1"}',
            200,
          );
        }
        return _json(_channelsPage([_instagramChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final fakeLauncher = _FakeUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Connect another account'), findsOneWidget);
      await tester.tap(find.text('Connect another account'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'POST' &&
              r.path == '/integrations/instagram/authorize/',
        ),
        isTrue,
      );
      expect(fakeLauncher.launchedUrls, [
        'https://instagram.com/oauth/authorize?x=1',
      ]);
    });

    testWidgets(
      'shows an error when the browser cannot be opened, without hanging',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path.contains('/instagram/authorize/')) {
            return _json(
              '{"authorization_url": "https://instagram.com/oauth/authorize?x=1"}',
              200,
            );
          }
          return _json(_channelsPage([_instagramChannel]), 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final fakeLauncher = _FakeUrlLauncher()..launchSucceeds = false;
        final previousLauncher = UrlLauncherPlatform.instance;
        UrlLauncherPlatform.instance = fakeLauncher;
        addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

        await _pumpChannelsTab(tester, apiClient: client);

        expect(find.text('Connect another account'), findsOneWidget);
        await tester.tap(find.text('Connect another account'));
        await tester.pumpAndSettle();

        expect(
          find.text("Couldn't open the browser for this connection."),
          findsOneWidget,
        );
      },
    );
  });

  group('SettingsScreen — Channels tab: Hide/Show', () {
    testWidgets(
      'Hide moves a channel into the Hidden section without any API call',
      (tester) async {
        final adapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await _pumpChannelsTab(tester, apiClient: client);

        final requestsBeforeHide = adapter.received.length;

        // Hide is directly visible
        expect(find.text('Hide'), findsOneWidget);
        await tester.tap(find.text('Hide'));
        await tester.pumpAndSettle();

        expect(find.text('Hidden (1)'), findsOneWidget);
        // Purely local state — no request fired for the hide action itself.
        expect(adapter.received.length, requestsBeforeHide);
      },
    );

    testWidgets('a hidden channel can be shown again from the section', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();

      // Expand the collapsed "Hidden" section, then directly tap "Show"
      await tester.tap(find.text('Hidden (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Show'), findsOneWidget);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Hidden (1)'), findsNothing);
    });
  });

  group('SettingsScreen — Channels tab: Arabic (RTL)', () {
    testWidgets('renders channel status and actions in Arabic', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(
        tester,
        apiClient: client,
        locale: const Locale('ar'),
      );

      expect(find.text('متصل'), findsWidgets);
      expect(find.text('اختبار'), findsOneWidget);
      expect(find.text('كتم'), findsOneWidget);
      expect(find.text('إخفاء'), findsOneWidget);
      expect(find.text('قطع الاتصال'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen — Channels tab: 2-column action grid', () {
    testWidgets('action buttons render in 2-column rows', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel, _instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      // Verify buttons exist
      expect(find.text('Check status'), findsOneWidget);
      expect(find.text('Test'), findsNWidgets(2));
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Unmute'), findsOneWidget);
      expect(find.text('Hide'), findsNWidgets(2));
      expect(find.text('Disconnect'), findsNWidgets(2));

      // Buttons are inside Rows with Expanded widgets
      final expandedButtons = find.ancestor(
        of: find.byType(OutlinedButton),
        matching: find.byType(Expanded),
      );
      expect(expandedButtons, findsWidgets);
    });

    testWidgets(
      'Disconnect button remains visually distinct with error color',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        final disconnectFinder = find.widgetWithText(
          OutlinedButton,
          'Disconnect',
        );
        expect(disconnectFinder, findsOneWidget);

        final button = tester.widget<OutlinedButton>(disconnectFinder);
        final errorColor = Theme.of(
          tester.element(disconnectFinder),
        ).colorScheme.error;
        expect(button.style?.foregroundColor?.resolve({}), errorColor);
      },
    );

    testWidgets(
      'WhatsApp with 5 actions does not create a horizontal overflow on 320px width',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );

        await _pumpChannelsTab(
          tester,
          apiClient: client,
          size: const Size(320, 1600),
        );

        expect(find.text('Check status'), findsOneWidget);
        expect(find.text('Test'), findsOneWidget);
        expect(find.text('Mute'), findsOneWidget);
        expect(find.text('Hide'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('SettingsScreen — Channels tab: Collapsible Platform Groups', () {
    testWidgets('platform groups are expanded by default', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(
          _channelsPage([
            _whatsappChannel,
            _facebookChannel1,
            _instagramChannel,
          ]),
          200,
        ),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      // Channels are visible without any interaction
      expect(find.text('Support line'), findsOneWidget);
      expect(find.text('Gadiat - جاديات'), findsOneWidget);
      expect(find.text('Acme Shop'), findsOneWidget);
    });

    testWidgets('tapping a platform header collapses its channels', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Support line'), findsOneWidget);

      // Tap WhatsApp Business header
      await tester.tap(find.text('WhatsApp Business'));
      await tester.pumpAndSettle();

      // Channel is collapsed (not visible)
      expect(find.text('Support line'), findsNothing);
      // Header remains visible
      expect(find.text('WhatsApp Business'), findsOneWidget);
      // Platform action remains accessible
      expect(find.text('Connect another number'), findsOneWidget);
    });

    testWidgets('tapping again expands its channels', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      // Collapse
      await tester.tap(find.text('WhatsApp Business'));
      await tester.pumpAndSettle();
      expect(find.text('Support line'), findsNothing);

      // Expand again
      await tester.tap(find.text('WhatsApp Business'));
      await tester.pumpAndSettle();
      expect(find.text('Support line'), findsOneWidget);
    });

    testWidgets('collapsing Facebook does not collapse Instagram', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) =>
            _json(_channelsPage([_facebookChannel1, _instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Gadiat - جاديات'), findsOneWidget);
      expect(find.text('Acme Shop'), findsOneWidget);

      // Tap Facebook Messenger header
      await tester.tap(find.text('Facebook Messenger'));
      await tester.pumpAndSettle();

      // Facebook is collapsed
      expect(find.text('Gadiat - جاديات'), findsNothing);
      // Instagram remains expanded
      expect(find.text('Acme Shop'), findsOneWidget);
    });

    testWidgets('collapsing Instagram does not collapse Facebook', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) =>
            _json(_channelsPage([_facebookChannel1, _instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      // Tap Instagram Direct header
      await tester.tap(find.text('Instagram Direct'));
      await tester.pumpAndSettle();

      // Instagram is collapsed
      expect(find.text('Acme Shop'), findsNothing);
      // Facebook remains expanded
      expect(find.text('Gadiat - جاديات'), findsOneWidget);
    });

    testWidgets(
      'multiple channels inside the same platform collapse together',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) =>
              _json(_channelsPage([_facebookChannel1, _facebookChannel2]), 200),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        expect(find.text('Gadiat - جاديات'), findsOneWidget);
        expect(find.text('Gado Tex جادو تكس'), findsOneWidget);

        // Collapse Facebook Messenger
        await tester.tap(find.text('Facebook Messenger'));
        await tester.pumpAndSettle();

        // Both channels collapsed
        expect(find.text('Gadiat - جاديات'), findsNothing);
        expect(find.text('Gado Tex جادو تكس'), findsNothing);

        // Reconnect action at platform level remains visible
        expect(find.text('Reconnect'), findsOneWidget);
      },
    );

    testWidgets('platform-level actions remain accessible when collapsed', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path.contains('/embedded-signup/mobile/start/')) {
          return _json(
            '{"authorization_url": "https://business.facebook.com/wa/signup?x=1"}',
            200,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final fakeLauncher = _FakeUrlLauncher();
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      await _pumpChannelsTab(tester, apiClient: client);

      // Collapse WhatsApp Business
      await tester.tap(find.text('WhatsApp Business'));
      await tester.pumpAndSettle();
      expect(find.text('Support line'), findsNothing);

      // Platform action is still tappable and triggers OAuth flow
      expect(find.text('Connect another number'), findsOneWidget);
      await tester.tap(find.text('Connect another number'));
      await tester.pumpAndSettle();

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'POST' &&
              r.path == '/integrations/whatsapp/embedded-signup/mobile/start/',
        ),
        isTrue,
      );
    });

    testWidgets('collapse state survives widget rebuilds and data refreshes', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      // Collapse WhatsApp
      await tester.tap(find.text('WhatsApp Business'));
      await tester.pumpAndSettle();
      expect(find.text('Support line'), findsNothing);

      // Rebuild via drag refresh
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // Remains collapsed after refresh
      expect(find.text('Support line'), findsNothing);
      expect(find.text('WhatsApp Business'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channels tab: Loading and error states', () {
    testWidgets('renders ErrorStateView when channelsProvider fails', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        return _json('{"error": {"message": "Network error"}}', 500);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channels tab: WhatsApp Update token', () {
    testWidgets('Update token button appears on each WhatsApp channel card', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel, _whatsappChannel2]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Update token'), findsNWidgets(2));
    });

    testWidgets('is hidden for a channel.view-only role', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(
        tester,
        apiClient: client,
        employee: _viewerEmployee,
      );

      expect(find.text('Update token'), findsNothing);
    });

    testWidgets(
      'opens the connect sheet pre-filled with the phone number id, locked',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        await tester.tap(find.text('Update token'));
        await tester.pumpAndSettle();

        expect(find.text('Update access token'), findsOneWidget);
        final phoneField = tester.widget<TextField>(
          find.widgetWithText(TextField, '1234567890'),
        );
        expect(phoneField.enabled, isFalse);
        // No WABA field in update mode — only the token changes.
        expect(find.text('WhatsApp Business Account ID'), findsNothing);
      },
    );

    testWidgets(
      'submitting calls connect/ with the same phone_number_id and refreshes channels',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path == '/integrations/whatsapp/connect/') {
            return _json(
              '{"id": 5, "display_name": "Support line", "status": "CONNECTED", "detail": "ok"}',
              201,
            );
          }
          return _json(_channelsPage([_whatsappChannel]), 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await _pumpChannelsTab(tester, apiClient: client);

        await tester.tap(find.text('Update token'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Access token'),
          'new-token-value',
        );
        await tester.tap(find.text('Update'));
        await tester.pumpAndSettle();

        final connectReq = adapter.received.firstWhere(
          (r) =>
              r.method == 'POST' && r.path == '/integrations/whatsapp/connect/',
        );
        expect(connectReq.data, {
          'phone_number_id': '1234567890',
          'access_token': 'new-token-value',
        });
        expect(find.text('Access token updated.'), findsOneWidget);
        // Sheet closed on success.
        expect(find.text('Update access token'), findsNothing);
      },
    );

    testWidgets('empty access token is rejected locally, no request sent', (
      tester,
    ) async {
      final adapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Update token'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(
        adapter.received.any((r) => r.path.contains('/connect/')),
        isFalse,
      );
    });

    testWidgets('a 409 conflict from the server is shown verbatim', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/integrations/whatsapp/connect/') {
          return _json(
            '{"error": {"code": "conflict", "message": "Already connected to another workspace.", "details": {}}}',
            409,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Update token'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Access token'),
        'stale-token',
      );
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(
        find.text('Already connected to another workspace.'),
        findsOneWidget,
      );
      // Sheet stays open so the admin can correct and retry.
      expect(find.text('Update access token'), findsOneWidget);
    });

    testWidgets('does not allow a second submit while the first is in flight', (
      tester,
    ) async {
      var connectCalls = 0;
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/integrations/whatsapp/connect/') {
          connectCalls++;
          return _json(
            '{"id": 5, "display_name": "Support line", "status": "CONNECTED", "detail": "ok"}',
            201,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Update token'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Access token'),
        'new-token-value',
      );

      // Two rapid taps before the first request resolves.
      await tester.tap(find.text('Update'));
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(connectCalls, 1);
    });
  });

  group('SettingsScreen — Channels tab: Other ways to connect', () {
    testWidgets(
      'section is collapsed by default and expands on tap (WhatsApp)',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(_channelsPage([_whatsappChannel]), 200),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        expect(find.text('Other ways to connect'), findsOneWidget);
        expect(find.text('Add another number'), findsNothing);

        await tester.tap(find.text('Other ways to connect'));
        await tester.pumpAndSettle();

        expect(find.text('Add another number'), findsOneWidget);
        expect(
          find.text('via phone number ID and access token'),
          findsOneWidget,
        );
      },
    );

    testWidgets('is absent for a channel.view-only role', (tester) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(
        tester,
        apiClient: client,
        employee: _viewerEmployee,
      );

      expect(find.text('Other ways to connect'), findsNothing);
    });

    testWidgets('Add another number opens a blank form and connects on submit', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/integrations/whatsapp/connect/') {
          return _json(
            '{"id": 12, "display_name": "New line", "status": "CONNECTED", "detail": "ok"}',
            201,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Other ways to connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add another number'));
      await tester.pumpAndSettle();

      expect(find.text('Add a WhatsApp number'), findsOneWidget);
      final phoneField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Phone number ID'),
      );
      expect(phoneField.enabled, isTrue);
      expect(find.text('WhatsApp Business Account ID'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number ID'),
        '999888777',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Access token'),
        'brand-new-token',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final connectReq = adapter.received.firstWhere(
        (r) =>
            r.method == 'POST' && r.path == '/integrations/whatsapp/connect/',
      );
      expect(connectReq.data, {
        'phone_number_id': '999888777',
        'access_token': 'brand-new-token',
      });
      expect(find.text('New line connected.'), findsOneWidget);
    });

    testWidgets('Add another number rejects a blank form locally', (
      tester,
    ) async {
      final adapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Other ways to connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add another number'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(
        adapter.received.any((r) => r.path.contains('/connect/')),
        isFalse,
      );
    });

    testWidgets(
      'Reconnect (Instagram) launches the same authorize() OAuth flow as the primary button',
      (tester) async {
        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path == '/integrations/instagram/authorize/') {
            return _json(
              '{"authorization_url": "https://instagram.com/oauth/authorize?x=1"}',
              200,
            );
          }
          return _json(_channelsPage([_instagramChannel]), 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final fakeLauncher = _FakeUrlLauncher();
        final previousLauncher = UrlLauncherPlatform.instance;
        UrlLauncherPlatform.instance = fakeLauncher;
        addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

        await _pumpChannelsTab(tester, apiClient: client);

        await tester.tap(find.text('Other ways to connect'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reconnect'));
        await tester.pumpAndSettle();

        expect(
          adapter.received.any(
            (r) =>
                r.method == 'POST' &&
                r.path == '/integrations/instagram/authorize/',
          ),
          isTrue,
        );
        expect(fakeLauncher.launchedUrls, [
          'https://instagram.com/oauth/authorize?x=1',
        ]);
      },
    );

    testWidgets('Use Instagram token opens a form and connects on submit', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/integrations/instagram/connect/') {
          return _json(
            '{"id": 30, "display_name": "Acme IG legacy", "status": "CONNECTED", "detail": "ok"}',
            201,
          );
        }
        return _json(_channelsPage([_instagramChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Other ways to connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Instagram token'));
      await tester.pumpAndSettle();

      expect(find.text('Connect with an Instagram token'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Instagram access token'),
        'ig-legacy-token',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final connectReq = adapter.received.firstWhere(
        (r) =>
            r.method == 'POST' && r.path == '/integrations/instagram/connect/',
      );
      expect(connectReq.data, {'access_token': 'ig-legacy-token'});
      expect(find.text('Acme IG legacy connected.'), findsOneWidget);
    });

    testWidgets('Use Instagram token rejects a blank form locally', (
      tester,
    ) async {
      final adapter = _StubAdapter(
        (_) => _json(_channelsPage([_instagramChannel]), 200),
      );
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Other ways to connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Instagram token'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(
        adapter.received.any((r) => r.path.contains('/connect/')),
        isFalse,
      );
    });

    testWidgets('a 400 from Instagram connect is shown verbatim', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/integrations/instagram/connect/') {
          return _json(
            '{"error": {"code": "invalid", "message": "Meta rejected it.", "details": {}}}',
            400,
          );
        }
        return _json(_channelsPage([_instagramChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);

      await tester.tap(find.text('Other ways to connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Instagram token'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Instagram access token'),
        'bad-token',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Meta rejected it.'), findsOneWidget);
    });

    testWidgets(
      'no "Manage Facebook Pages" placeholder is ever rendered — no such backend endpoint exists',
      (tester) async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter(
          (_) => _json(
            _channelsPage([
              _whatsappChannel,
              _instagramChannel,
              _facebookChannel1,
            ]),
            200,
          ),
        );

        await _pumpChannelsTab(tester, apiClient: client);

        // Expand every collapsible "Other ways to connect" section present.
        for (final finder in tester.widgetList(
          find.text('Other ways to connect'),
        )) {
          await tester.tap(find.byWidget(finder));
        }
        await tester.pumpAndSettle();

        expect(find.text('Manage Facebook Pages'), findsNothing);
      },
    );

    testWidgets('Facebook/Messenger has no "Other ways to connect" section', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_facebookChannel1]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Other ways to connect'), findsNothing);
    });
  });
}
