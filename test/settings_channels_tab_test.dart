/// Tests for Settings > Channels tab:
/// - Channel list rendering (empty and populated states)
/// - Connected/degraded/disconnected status badges
/// - Test action (loading state, success/failure snackbars, no double-submit)
/// - Mute/unmute
/// - Disconnect: confirmation dialog, correct provider-specific endpoint,
///   channel list refresh after success, API error handling
/// - WhatsApp-only "Check status" action
/// - "Connect another number/account" opens the right authorize/connect
///   endpoint's URL
/// - Hide/Show: local-only, no API call, does not require channel.manage
/// - Permission gating (channel.manage hides every write action)
/// - No horizontal overflow
/// - Arabic locale (RTL) rendering
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

/// Fakes the plugin platform channel `url_launcher` normally talks to.
/// There is no such channel registered in a widget test, so the real
/// [MethodChannelUrlLauncher] would hang the test waiting for a response
/// that never arrives — this returns immediately instead, recording what was
/// asked for.
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

Widget _settingsHarness({
  required ApiClient apiClient,
  Employee? employee,
  Locale locale = const Locale('en'),
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
      theme: AppTheme.light,
      home: const SettingsScreen(),
    ),
  );
}

Future<void> _pumpChannelsTab(
  WidgetTester tester, {
  required ApiClient apiClient,
  Employee? employee,
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 1600);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    _settingsHarness(apiClient: apiClient, employee: employee, locale: locale),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen — Channels tab rendering', () {
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
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Degraded'), findsOneWidget);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.text('Muted by Mona'), findsOneWidget);
    });

    testWidgets('does not overflow horizontally on a narrow phone width', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel, _instagramChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      // A horizontal-overflow RenderFlex throws during layout, which
      // pumpAndSettle would have already surfaced as a test failure via
      // FlutterError.onError — reaching here with no exception is the
      // assertion.
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
        expect(find.byIcon(Icons.more_vert), findsNothing);
        // Hide remains available without channel.manage — it is
        // presentation-only, gated only by channel.view (which the tab
        // itself already requires to render at all).
        expect(find.text('Hide'), findsOneWidget);
      },
    );

    testWidgets('write actions are shown for a channel.manage role', (
      tester,
    ) async {
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter(
        (_) => _json(_channelsPage([_whatsappChannel]), 200),
      );

      await _pumpChannelsTab(tester, apiClient: client);

      expect(find.text('Test'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
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

      // Two rapid taps must not fire two requests: the button disables
      // itself the instant _busy flips true, before the pump that would
      // let a second tap land.
      await tester.tap(find.text('Test'));
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(testCallCount, 1);
      expect(find.text('Connection verified.'), findsOneWidget);
    });

    testWidgets('a false result is shown as a plain (non-error) message', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path.contains('/test/')) {
          return _json(
            '{"ok": false, "detail": "Adapter not reachable."}',
            200,
          );
        }
        return _json(_channelsPage([_whatsappChannel]), 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('Adapter not reachable.'), findsOneWidget);
    });
  });

  group('SettingsScreen — Channels tab: Mute/Unmute', () {
    testWidgets('mute POSTs to /channels/{id}/mute/ and refreshes the list', (
      tester,
    ) async {
      var muteCalls = 0;
      var muted = false;
      final mutedChannel = _whatsappChannel.replaceFirst(
        '"is_muted": false',
        '"is_muted": true',
      );
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' && options.path.contains('/mute/')) {
          muteCalls++;
          muted = true;
          return _json(mutedChannel, 200);
        }
        return _json(
          _channelsPage([muted ? mutedChannel : _whatsappChannel]),
          200,
        );
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpChannelsTab(tester, apiClient: client);
      await tester.tap(find.text('Mute'));
      await tester.pumpAndSettle();

      expect(muteCalls, 1);
      expect(
        adapter.received.any(
          (r) => r.method == 'POST' && r.path == '/channels/5/mute/',
        ),
        isTrue,
      );
      // Refresh re-fetched the list — mute is now reflected as "Unmute".
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

  group('SettingsScreen — Channels tab: Connect another', () {
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
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

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();

      // Expand the collapsed "Hidden" section, then use its card's overflow
      // menu — this employee has channel.manage, so the card's primary
      // second button is still "Mute"/"Unmute"; "Show" lives in the menu
      // next to Disconnect, matching "Hide" living there for a manager.
      await tester.tap(find.text('Hidden (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
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

      expect(find.text('متصل'), findsOneWidget);
      expect(find.text('اختبار'), findsOneWidget);
      expect(find.text('كتم'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
