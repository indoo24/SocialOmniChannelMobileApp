/// AI activity (`GET /ai/metrics/`, `GET /ai/usage/`), AI policy
/// (`GET/PUT /ai/policy/`) and each channel's limits (`GET/PUT
/// /ai/agent-settings/`) — parsing, the screens' states, what a save sends,
/// and how the AI tab reaches them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scenario_mobile/app/router.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/ai_operations.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/knowledge.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_activity_screen.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_channel_settings_screen.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_knowledge_labels.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_knowledge_providers.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_knowledge_settings_tab.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_policy_screen.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// --------------------------------------------------------------------------- //
// Stub backend
// --------------------------------------------------------------------------- //

typedef Json = Map<String, dynamic>;

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

ResponseBody _error(int status, String code, {Json details = const {}}) =>
    _json({
      'error': {'code': code, 'message': 'Refused: $code', 'details': details},
    }, status);

Json _metrics({
  int opportunities = 2,
  int refused = 2,
  int notInKb = 1,
  int conflicts = 0,
  int providerUnavailable = 3,
  double sendRate = 0.125,
}) => {
  'organization_id': 1,
  'window_hours': 24.0,
  'opportunities': opportunities,
  'sent': 0,
  'handed_off': 0,
  'refused': refused,
  'duplicates_suppressed': 0,
  'coalesced_messages': 0,
  'handoff_rate': 0.0,
  'send_rate': sendRate,
  'verbatim_rate': 0.5,
  'not_in_kb': notInKb,
  'conflicts': conflicts,
  'restricted_topics': 0,
  'grounding_too_low': 0,
  'ungrounded_numbers': 0,
  'customer_requested_human': 0,
  'outside_service_window': 0,
  'attachment_required': 0,
  'max_auto_turns': 0,
  'budget_exhausted': 0,
  'provider_unavailable': providerUnavailable,
  'send_failed': 0,
  'suggestions': 4,
  'suggestions_used': 2,
  'suggestions_discarded': 1,
  'suggestions_regenerated': 1,
  'sent_unchanged': 1,
  'sent_edited': 1,
  'tokens': 14539,
  'requests': 2,
  'average_duration_ms': 812,
  'average_retrieval_ms': 40,
  'slowest_duration_ms': 2300,
  'human_takeovers': 0,
  'delivery_failures': 0,
  'conversations_paused': 3,
  'connections_off': 5,
  'connections_suggest': 0,
  'connections_auto': 1,
  'by_operation': <String, Object>{},
};

Json _quietMetrics() => {
  for (final e in _metrics().entries)
    e.key: e.value is int
        ? 0
        : e.value is double
        ? 0.0
        : e.value,
};

Json _usage() => {
  'requests': 20,
  'total_tokens': 14539,
  'input_tokens': 12000,
  'output_tokens': 2539,
  'answered': 11,
  'not_in_kb': 9,
  'errors': 0,
  'by_model': {'model-small': 5, 'model-large': 15},
  'since': '2026-10-06T00:00:00Z',
};

Json _policy() => {
  'is_ai_enabled': true,
  'is_auto_send_enabled': false,
  'daily_request_limit': 5000,
  'daily_token_limit': 2000000,
  'rollout_state': 'PILOT',
};

Json _channel({String mode = 'AUTO', bool withConfig = true}) => {
  'connection_id': 12,
  'connection_name': 'Gad',
  'provider': 'WHATSAPP',
  'status': 'ACTIVE',
  'mode': mode,
  'assist_supported': true,
  if (withConfig) ...{
    'max_auto_turns': 50,
    'auto_session_idle_hours': 24,
    'daily_auto_send_limit': 500,
    'grounding_profile': 'FLEXIBLE',
    'grounding_floor': 0.42,
    'resume_behaviour': 'ASK',
    'extra_restricted_topics': ['shipping'],
    'locked_restricted_topics': ['legal', 'medical'],
    'handoff_rules': [
      {
        'reason': 'CUSTOMER_REQUESTED_HUMAN',
        'why': 'A customer who asks for a person gets one.',
        'locked': true,
        'enabled': true,
      },
      {
        'reason': 'RESTRICTED_TOPIC',
        'why': 'Topics this business does not want answered automatically.',
        'locked': false,
        'enabled': true,
      },
    ],
  },
};

class _Server {
  _Server({this.channel, this.metricsBody});

  Json? channel;
  Json? metricsBody;
  Json? policyBody;

  /// Overrides a path's answer, by path.
  final overrides = <String, FutureOr<ResponseBody> Function(RequestOptions)>{};
  final requests = <RequestOptions>[];

  Iterable<RequestOptions> get writes =>
      requests.where((r) => r.method != 'GET');

  List<int> get metricHours => [
    for (final r in requests)
      if (r.path == '/ai/metrics/') r.queryParameters['hours'] as int,
  ];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  FutureOr<ResponseBody> _handle(RequestOptions o) {
    requests.add(o);
    if (overrides[o.path] case final handler?) return handler(o);
    switch (o.path) {
      case '/ai/metrics/':
        return _json(metricsBody ?? _metrics());
      case '/ai/usage/':
        return _json(_usage());
      case '/ai/policy/':
        if (o.method == 'PUT') {
          policyBody = {...policyBody ?? _policy(), ...o.data as Map};
        }
        return _json(policyBody ?? _policy());
      case '/ai/agent-settings/':
        final row = channel ?? _channel();
        if (o.method == 'PUT') {
          final body = Map<String, dynamic>.from(o.data as Map);
          final rules = [
            for (final r in row['handoff_rules'] as List? ?? const [])
              (r as Json)['locked'] == false &&
                      body.containsKey('handoff_on_restricted_topic')
                  ? {...r, 'enabled': body['handoff_on_restricted_topic']}
                  : r,
          ];
          channel = {
            ...row,
            ...body..remove('handoff_on_restricted_topic'),
            'handoff_rules': rules,
          };
          return _json([channel]);
        }
        return _json([row]);
      case '/ai/readiness/':
        return _json([
          {
            'connection_id': 12,
            'provider': 'WHATSAPP',
            'state': 'READY_FOR_AUTO',
            'suggest_allowed': true,
            'auto_allowed': true,
            'blocking': <String>[],
            'warnings': <String>[],
            'detail': <String, Object>{},
          },
        ]);
      case '/ai/conflicts/':
        return _json(<Object>[]);
      case '/knowledge-bases/':
        return _json({
          'count': 0,
          'page': 1,
          'page_size': 100,
          'total_pages': 1,
          'next': null,
          'previous': null,
          'results': <Object>[],
        });
    }
    return _error(404, 'not_found');
  }
}

Employee _employee({bool allowed = true}) => Employee(
  id: 1,
  email: 'admin@acme.test',
  fullName: 'Admin',
  initials: 'AD',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {if (allowed) Perm.aiKnowledgeManage},
  visibilityScope: 'ALL',
  aiKnowledgeEnabled: true,
);

/// [screen] pushed over a blank page, so leaving it can be tested.
Future<void> _pump(
  WidgetTester tester,
  _Server server,
  Widget screen, {
  Employee? employee,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 5000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _tileValue(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .toList();
  return texts[1]!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------------ //
  group('parsing', () {
    test('metrics: every field, and a missing one stays missing', () {
      final m = AiMetrics.fromJson(_metrics());
      expect(m.opportunities, 2);
      expect(m.sendRate, 0.125);
      expect(m.averageDurationMs, 812);
      expect(m.connectionsAuto, 1);
      expect(m.isQuiet, isFalse);

      final partial = AiMetrics.fromJson({..._metrics()}..remove('sent'));
      expect(partial.sent, isNull);
      expect(AiMetrics.fromJson(_quietMetrics()).isQuiet, isTrue);
    });

    test('usage, with requests by model', () {
      final u = AiUsageSummary.fromJson(_usage());
      expect(u.requests, 20);
      expect(u.inputTokens, 12000);
      expect(u.byModel, {'model-small': 5, 'model-large': 15});
    });

    test('policy parses, and refuses a body missing a field', () {
      final p = AiOrganizationPolicy.fromJson(_policy());
      expect(p.isAiEnabled, isTrue);
      expect(p.dailyTokenLimit, 2000000);
      expect(p.rolloutState, 'PILOT');
      expect(
        () => AiOrganizationPolicy.fromJson(
          {..._policy()}..remove('is_ai_enabled'),
        ),
        throwsFormatException,
      );
    });

    test('policy changes name only what differs', () {
      final p = AiOrganizationPolicy.fromJson(_policy());
      expect(p.changesTo(p), isEmpty);
      final edited = AiOrganizationPolicy.fromJson({
        ..._policy(),
        'is_auto_send_enabled': true,
        'rollout_state': 'LIMITED',
      });
      expect(p.changesTo(edited), {
        'is_auto_send_enabled': true,
        'rollout_state': 'LIMITED',
      });
    });

    test('a channel reads its limits, or has none to show', () {
      final row = AiAgentSetting.fromJson(_channel());
      expect(row.hasChannelConfig, isTrue);
      expect(row.maxAutoTurns, 50);
      expect(row.groundingFloor, 0.42);
      expect(row.lockedRestrictedTopics, ['legal', 'medical']);
      expect(row.handoffRules, hasLength(2));
      expect(row.handoffOnRestrictedTopic, isTrue);

      final bare = AiAgentSetting.fromJson(_channel(withConfig: false));
      expect(bare.hasChannelConfig, isFalse);
      expect(bare.handoffOnRestrictedTopic, isNull);
    });

    test('formats rates, durations and missing values like the web', () {
      expect(aiPercent(0), '0%');
      expect(aiPercent(0.125), '12.5%');
      expect(aiPercent(1), '100%');
      expect(aiPercent(null), '—');
      expect(aiDuration(40), '40 ms');
      expect(aiDuration(812), '0.8s');
      expect(aiDuration(null), '—');
      expect(aiCount(14539), '14539');
      expect(aiCount(null), '—');
    });

    test('the metrics window is clamped to the server range', () async {
      final server = _Server();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(server.client())],
      );
      addTearDown(container.dispose);
      final repo = container.read(aiKnowledgeRepositoryProvider);
      await repo.metrics(hours: 1000);
      await repo.metrics(hours: 168, connectionId: 12);
      expect(server.metricHours, [720, 168]);
      expect(server.requests.last.queryParameters['connection_id'], 12);
    });
  });

  // ------------------------------------------------------------------------ //
  group('activity', () {
    testWidgets('shows the server numbers, grouped and formatted', (
      tester,
    ) async {
      await _pump(tester, _Server(), const AiActivityScreen());

      expect(_tileValue(tester, 'metric-opportunities'), '2');
      expect(_tileValue(tester, 'metric-send-rate'), '12.5%');
      expect(_tileValue(tester, 'metric-verbatim-rate'), '50%');
      expect(find.text('1 of 2 drafts'), findsOneWidget);
      expect(_tileValue(tester, 'metric-average-duration'), '0.8s');
      expect(_tileValue(tester, 'metric-average-retrieval'), '40 ms');
      expect(_tileValue(tester, 'metric-tokens'), '14539');
      expect(_tileValue(tester, 'metric-connections-auto'), '1');
      expect(_tileValue(tester, 'metric-conversations-paused'), '3');

      // Reasons: only those that happened, largest first.
      expect(find.byKey(const Key('reason-conflicts')), findsNothing);
      final providerTop = tester
          .getTopLeft(find.byKey(const Key('reason-provider-unavailable')))
          .dy;
      final notInKbTop = tester
          .getTopLeft(find.byKey(const Key('reason-not-in-kb')))
          .dy;
      expect(providerTop, lessThan(notInKbTop));

      expect(_tileValue(tester, 'usage-requests'), '20');
      expect(_tileValue(tester, 'usage-output-tokens'), '2539');
      expect(_tileValue(tester, 'usage-errors'), '0');
      final large = tester.getTopLeft(
        find.byKey(const Key('usage-model-model-large')),
      );
      final small = tester.getTopLeft(
        find.byKey(const Key('usage-model-model-small')),
      );
      expect(large.dy, lessThan(small.dy));
    });

    testWidgets('a value the server did not send shows a dash, not 0', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(metricsBody: {..._metrics()}..remove('sent')),
        const AiActivityScreen(),
      );
      expect(_tileValue(tester, 'metric-sent'), '—');
    });

    testWidgets('starts at 24 hours; each window asks for its own hours', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, const AiActivityScreen());
      expect(server.metricHours, [24]);

      await tester.tap(find.byKey(const Key('ai-window-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-window-168')));
      await tester.pumpAndSettle();
      expect(server.metricHours, [24, 1, 168]);
      expect(find.text('Last 168 hours'), findsOneWidget);
    });

    testWidgets('a quiet window says so', (tester) async {
      await _pump(
        tester,
        _Server(metricsBody: _quietMetrics()),
        const AiActivityScreen(),
      );
      expect(find.byKey(const Key('ai-activity-quiet')), findsOneWidget);
      expect(find.byKey(const Key('ai-no-declines')), findsOneWidget);
    });

    testWidgets('loading, then a failure with retry that recovers', (
      tester,
    ) async {
      final gate = Completer<void>();
      var fail = true;
      final server = _Server();
      server.overrides['/ai/metrics/'] = (o) async {
        await gate.future;
        return fail ? _error(500, 'server_error') : _json(_metrics());
      };
      await tester.binding.setSurfaceSize(const Size(800, 5000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(server.client()),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AiActivityScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete();
      // Riverpod retries a failed build with backoff before it shows.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Try again'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(_tileValue(tester, 'metric-opportunities'), '2');
    });

    testWidgets('outside the pilot (404) it is "not available"', (
      tester,
    ) async {
      final server = _Server();
      server.overrides['/ai/metrics/'] = (_) => _error(404, 'not_found');
      await _pump(tester, server, const AiActivityScreen());
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byKey(const Key('ai-not-available')), findsOneWidget);
    });

    testWidgets('without ai_knowledge.manage nothing is fetched', (
      tester,
    ) async {
      final server = _Server();
      await _pump(
        tester,
        server,
        const AiActivityScreen(),
        employee: _employee(allowed: false),
      );
      expect(find.byKey(const Key('ai-not-available')), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('Arabic, on a narrow phone, without overflow', (tester) async {
      await _pump(
        tester,
        _Server(),
        const AiActivityScreen(),
        locale: const Locale('ar'),
        size: const Size(320, 6000),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('نشاط الذكاء الاصطناعي'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  group('policy', () {
    testWidgets('loads the policy; Save sends only what changed', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, const AiPolicyScreen());

      final save = find.byKey(const Key('ai-policy-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('5000'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ai-policy-request-limit')),
        '7000',
      );
      await tester.tap(find.byKey(const Key('ai-policy-auto-send')));
      await tester.pump();
      expect(find.byKey(const Key('ai-policy-unsaved')), findsOneWidget);

      await tester.tap(save);
      await tester.pumpAndSettle();
      final put = server.writes.single;
      expect(put.method, 'PUT');
      expect(put.path, '/ai/policy/');
      expect(put.data, {
        'is_auto_send_enabled': true,
        'daily_request_limit': 7000,
      });
      expect(find.text('AI policy saved.'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.byKey(const Key('ai-policy-unsaved')), findsNothing);
    });

    testWidgets('an out-of-range limit is caught before sending', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, const AiPolicyScreen());

      await tester.enterText(
        find.byKey(const Key('ai-policy-request-limit')),
        '2000000',
      );
      await tester.pump();
      expect(
        find.text('Enter a whole number from 0 to 1000000.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-policy-save')))
            .onPressed,
        isNull,
      );
      expect(server.writes, isEmpty);
    });

    testWidgets('a server refusal shows beside its field', (tester) async {
      final server = _Server();
      server.overrides['/ai/policy/'] = (o) => o.method == 'PUT'
          ? _error(
              400,
              'validation_error',
              details: {
                'daily_token_limit': ['Ensure this value is less than…'],
              },
            )
          : _json(_policy());
      await _pump(tester, server, const AiPolicyScreen());

      await tester.enterText(
        find.byKey(const Key('ai-policy-token-limit')),
        '3000000',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-policy-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ensure this value is less than…'), findsOneWidget);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      await _pump(tester, _Server(), const AiPolicyScreen());
      await tester.tap(find.byKey(const Key('ai-policy-ai-enabled')));
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(AiPolicyScreen), findsOneWidget);

      await navigator.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-discard-changes')));
      await tester.pumpAndSettle();
      expect(find.byType(AiPolicyScreen), findsNothing);
    });

    testWidgets('lists each AI channel with its mode', (tester) async {
      await _pump(tester, _Server(), const AiPolicyScreen());
      expect(find.byKey(const Key('ai-policy-channel-12')), findsOneWidget);
      expect(find.text('Gad'), findsOneWidget);
      expect(find.text('Automatic'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  group('channel settings', () {
    testWidgets('shows the channel limits as the server has them', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(),
        const AiChannelSettingsScreen(connectionId: 12),
      );
      expect(find.text('50'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('legal'), findsOneWidget);
      expect(find.byKey(const Key('ai-topic-shipping')), findsOneWidget);
      expect(find.text('Customer asked for a person'), findsOneWidget);
      expect(find.text('Always on'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<String>>(
              find.ancestor(
                of: find.byKey(const Key('ai-grounding-FLEXIBLE')),
                matching: find.byType(RadioGroup<String>),
              ),
            )
            .groupValue,
        'FLEXIBLE',
      );

      await tester.tap(find.byKey(const Key('ai-channel-floor-toggle')));
      await tester.pump();
      expect(find.byKey(const Key('ai-channel-floor')), findsOneWidget);
    });

    testWidgets('Save sends only what changed, keyed as the API takes it', (
      tester,
    ) async {
      final server = _Server();
      await _pump(
        tester,
        server,
        const AiChannelSettingsScreen(connectionId: 12),
      );

      await tester.enterText(
        find.byKey(const Key('ai-channel-max-turns')),
        '10',
      );
      await tester.tap(find.byKey(const Key('ai-grounding-STRICT')));
      await tester.tap(find.byKey(const Key('ai-resume-WAIT')));
      await tester.enterText(
        find.byKey(const Key('ai-channel-new-topic')),
        'warranty',
      );
      await tester.tap(find.byKey(const Key('ai-channel-add-topic')));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('ai-topic-shipping')),
          matching: find.byIcon(Icons.clear),
        ),
      );
      await tester.tap(
        find.byKey(const Key('ai-handoff-RESTRICTED_TOPIC-switch')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('ai-channel-save')));
      await tester.pumpAndSettle();

      final put = server.writes.single;
      expect(put.path, '/ai/agent-settings/');
      expect(put.data, {
        'max_auto_turns': 10,
        'resume_behaviour': 'WAIT',
        'grounding_profile': 'STRICT',
        'extra_restricted_topics': ['warranty'],
        'handoff_on_restricted_topic': false,
        'connection_id': 12,
      });
      expect(find.text('Channel settings saved.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-channel-save')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('limits are checked against the API bounds', (tester) async {
      final server = _Server();
      await _pump(
        tester,
        server,
        const AiChannelSettingsScreen(connectionId: 12),
      );

      await tester.enterText(
        find.byKey(const Key('ai-channel-max-turns')),
        '51',
      );
      await tester.pump();
      expect(find.text('Enter a whole number from 1 to 50.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-channel-save')))
            .onPressed,
        isNull,
      );
      expect(server.writes, isEmpty);
    });

    testWidgets(
      'topics: no duplicates (built-in ones included), no long ones',
      (tester) async {
        await _pump(
          tester,
          _Server(),
          const AiChannelSettingsScreen(connectionId: 12),
        );
        final field = find.byKey(const Key('ai-channel-new-topic'));
        final add = find.byKey(const Key('ai-channel-add-topic'));

        await tester.enterText(field, 'Legal');
        await tester.tap(add);
        await tester.pump();
        expect(find.text('That topic is already listed.'), findsOneWidget);

        await tester.enterText(field, 'x' * 61);
        await tester.tap(add);
        await tester.pump();
        expect(find.text('Keep a topic under 60 characters.'), findsOneWidget);
      },
    );

    testWidgets('a channel the server sends no limits for says so', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(channel: _channel(withConfig: false)),
        const AiChannelSettingsScreen(connectionId: 12),
      );
      expect(
        find.byKey(const Key('ai-channel-config-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-channel-save')), findsNothing);
    });

    testWidgets('Arabic, on a narrow phone, without overflow', (tester) async {
      await _pump(
        tester,
        _Server(),
        const AiChannelSettingsScreen(connectionId: 12),
        locale: const Locale('ar'),
        size: const Size(320, 6000),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('مرن'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  testWidgets('the AI tab opens activity, policy and a channel', (
    tester,
  ) async {
    final server = _Server();
    final router = GoRouter(
      initialLocation: Routes.settings,
      routes: [
        GoRoute(
          path: Routes.settings,
          builder: (_, _) => const Scaffold(body: AiKnowledgeSettingsTab()),
          routes: [
            GoRoute(
              path: 'ai-activity',
              builder: (_, _) => const AiActivityScreen(),
            ),
            GoRoute(
              path: 'ai-policy',
              builder: (_, _) => const AiPolicyScreen(),
              routes: [
                GoRoute(
                  path: 'channels/:id',
                  builder: (_, state) => AiChannelSettingsScreen(
                    connectionId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-link-activity')));
    await tester.pumpAndSettle();
    expect(find.byType(AiActivityScreen), findsOneWidget);
    expect(router.state.uri.path, Routes.aiActivity);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-link-policy')));
    await tester.pumpAndSettle();
    expect(find.byType(AiPolicyScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-policy-channel-12')));
    await tester.pumpAndSettle();
    expect(find.byType(AiChannelSettingsScreen), findsOneWidget);
    expect(router.state.uri.path, Routes.aiChannelSettings(12));
  });
}
