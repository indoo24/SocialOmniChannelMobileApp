/// `ConversationRepository.counts()`, still used by the app drawer's unread
/// badge even though the quick-filter pills themselves no longer show a
/// number.
///
/// `GET /conversations/counts/` was confirmed live against production to
/// disagree with `GET /conversations/` for the same account and the same
/// (absent) filter: it read 32 while the list — and the web client — both
/// agreed on 15. That is a server-side inconsistency between the two
/// endpoints' own queries, not a client-side scoping bug, so no client-side
/// fix to the *query* can close it. Instead `counts()` stops calling
/// `/conversations/counts/` altogether and asks `/conversations/` itself —
/// the same endpoint and the same [ConversationFilters] the list uses — for
/// each bucket's `count`, with `page_size=1` so the request stays cheap.
/// This makes the numbers correct by construction: they are answers from the
/// list's own query, not a second, independently implemented one, so they
/// cannot disagree with what the list shows.
library;

import 'dart:async';
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
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/conversations/platform_account_filter_bar.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
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

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final _testEmployee = Employee(
  id: 42,
  email: 'employee@test.com',
  fullName: 'Mohamed Gad',
  initials: 'MG',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.channelView},
  visibilityScope: 'ALL',
);

const _waAccount1 = ChannelConnection(
  id: 5,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Support',
  status: 'CONNECTED',
  isActive: true,
);

const _waAccount2 = ChannelConnection(
  id: 6,
  provider: 'WHATSAPP',
  providerDisplay: 'WhatsApp Business',
  displayName: 'WhatsApp Sales',
  status: 'CONNECTED',
  isActive: true,
);

String _page(int count) =>
    '{"count": $count, "next": null, "previous": null, "results": []}';

const _channelsJson =
    '{"count": 2, "next": null, "previous": null, "results": ['
    '{"id": 5, "provider": "WHATSAPP", "provider_display": "WhatsApp Business", "display_name": "WhatsApp Support", "status": "CONNECTED", "is_active": true},'
    '{"id": 6, "provider": "WHATSAPP", "provider_display": "WhatsApp Business", "display_name": "WhatsApp Sales", "status": "CONNECTED", "is_active": true}'
    ']}';

/// Requests the *real* first-page list issues — `page_size` absent — as
/// opposed to one of the five `page_size=1` probes `counts()` sends.
///
/// Dio's `RequestOptions.queryParameters` preserves each value's original
/// Dart type until the request is serialized onto the wire, so `page_size`,
/// `assigned_to` and `unread` come back here as an `int`/`int`/`bool` — not
/// the strings the actual HTTP query string would contain.
bool _isListRequest(RequestOptions r) =>
    r.path.contains('/conversations/') &&
    r.queryParameters['page_size'] == null;

bool _isCountsProbe(RequestOptions r) =>
    r.path.contains('/conversations/') && r.queryParameters['page_size'] == 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationRepository.counts() — derived from the list itself', () {
    late _StubAdapter adapter;
    late ApiClient client;

    setUp(() {
      adapter = _StubAdapter((options) {
        final q = options.queryParameters;
        int count;
        if (q['assigned_to'] == 42) {
          count = 3; // mine
        } else if (q['view'] == 'unassigned') {
          count = 1; // unassigned
        } else if (q['unread'] == true) {
          count = 2; // unread
        } else if (q['status'] == 'OPEN') {
          count = 10; // open
        } else {
          count = 15; // all
        }
        return _json(_page(count), 200);
      });
      client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;
    });

    test(
      'issues one page_size=1 probe per bucket, not /conversations/counts/',
      () async {
        await ConversationRepository(client).counts(currentEmployeeId: 42);

        expect(adapter.received, hasLength(5));
        for (final request in adapter.received) {
          expect(request.path, '/conversations/');
          expect(request.queryParameters['page_size'], 1);
        }
        expect(
          adapter.received.any((r) => r.path.contains('/counts/')),
          isFalse,
        );
      },
    );

    test(
      'each bucket reads its own filtered count, not the raw list length',
      () async {
        final counts = await ConversationRepository(
          client,
        ).counts(currentEmployeeId: 42);

        expect(counts, {
          'all': 15,
          'mine': 3,
          'unassigned': 1,
          'unread': 2,
          'open': 10,
        });
      },
    );

    test(
      'forwards the channel filter the same way the real list does',
      () async {
        await ConversationRepository(
          client,
        ).counts(channelConnections: [6], currentEmployeeId: 42);

        for (final request in adapter.received) {
          expect(request.queryParameters['channel_connections'], '6');
        }
      },
    );

    test(
      'a multi-channel selection is forwarded to every bucket too',
      () async {
        await ConversationRepository(
          client,
        ).counts(channelConnections: [5, 6], currentEmployeeId: 42);

        for (final request in adapter.received) {
          expect(request.queryParameters['channel_connections'], '5,6');
        }
      },
    );
  });

  group('Inbox screen — quick filter pills show no count badge', () {
    late _StubAdapter adapter;
    late ApiClient apiClient;

    setUp(() {
      adapter = _StubAdapter((options) {
        final path = options.uri.path;
        if (path.contains('/conversations/')) {
          final selected = options.uri.queryParameters['channel_connections'];
          // The scenario from the bug report: an org-wide /conversations/
          // total of 15, further narrowed to 7 for one specific channel —
          // never 32, because there is no second, disagreeing endpoint
          // anymore. The pills no longer render either number, but the
          // underlying request/count plumbing this exercises still backs
          // the app drawer's unread badge.
          if (selected == '6') return _json(_page(7), 200);
          return _json(_page(15), 200);
        }
        if (path.contains('/channels/')) return _json(_channelsJson, 200);
        return _json('{}', 200);
      });
      apiClient = ApiClient.create(cookieJar: CookieJar());
      apiClient.raw.httpClientAdapter = adapter;
    });

    Widget createInboxApp() => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        currentEmployeeProvider.overrideWith((ref) => _testEmployee),
        channelsProvider.overrideWith(
          (ref) async => const [_waAccount1, _waAccount2],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InboxScreen(),
      ),
    );

    testWidgets('the All pill shows only its label, never a number', (
      tester,
    ) async {
      await tester.pumpWidget(createInboxApp());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_all')),
          matching: find.text('All'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('quick_filter_all')),
          matching: find.text('15'),
        ),
        findsNothing,
      );

      final listRequest = adapter.received.firstWhere(_isListRequest);
      expect(listRequest.path, '/conversations/');
    });

    testWidgets(
      'still shows just the label after selecting one channel — no 7, no 32',
      (tester) async {
        await tester.pumpWidget(createInboxApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byType(PlatformAccountSelectorButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('WhatsApp Sales'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('quick_filter_all')),
            matching: find.text('All'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('quick_filter_all')),
            matching: find.text('7'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('quick_filter_all')),
            matching: find.text('32'),
          ),
          findsNothing,
        );

        // Only probes issued after the selection should carry the filter —
        // requests from the initial, unfiltered load are still in
        // `adapter.received` too. The underlying counts() plumbing this
        // proves out still backs the app drawer's unread badge even though
        // the pills themselves stopped displaying it.
        final latestProbes = adapter.received.reversed
            .where(_isCountsProbe)
            .take(5);
        expect(
          latestProbes.every(
            (r) => r.queryParameters['channel_connections'] == '6',
          ),
          isTrue,
        );
      },
    );
  });
}
