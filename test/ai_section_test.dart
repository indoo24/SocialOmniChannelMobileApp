/// The AI section's five tabs — Overview, Knowledge Base, AI Agent & Automatic
/// Replies, AI Playground, Activity & Usage — and the organization settings
/// screen, against a stubbed backend speaking the OpenAPI contract
/// (`/ai/policy/`, `/ai/agent-settings/`, `/ai/readiness/`, `/ai/conflicts/`,
/// `/ai/metrics/`, `/ai/usage/`, `/ai/history/`, `/knowledge-bases/`).
///
/// Knowledge, source and playground behaviour is in `ai_knowledge_test.dart`.
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

Json _metrics({int sent = 4, int fallbacks = 1, double fallbackRate = 0.25}) =>
    {
      'organization_id': 1,
      'window_hours': 24.0,
      'opportunities': 6,
      'sent': sent,
      'kb_answered': 3,
      'fallbacks': fallbacks,
      'fallback_rate': fallbackRate,
      'greetings': 2,
      'thanks': 1,
      'acknowledgements': 0,
      'goodbyes': 1,
      'handed_off': 1,
      'refused': 2,
      'duplicates_suppressed': 0,
      'coalesced_messages': 0,
      'handoff_rate': 0.125,
      'send_rate': 0.5,
      'verbatim_rate': 0.5,
      'not_in_kb': 1,
      'conflicts': 0,
      'restricted_topics': 0,
      'grounding_too_low': 0,
      'ungrounded_numbers': 0,
      'customer_requested_human': 0,
      'outside_service_window': 0,
      'attachment_required': 0,
      'budget_exhausted': 0,
      'provider_unavailable': 3,
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
      'connections_off': 16,
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

Json _policy({
  bool aiEnabled = true,
  String defaultPolicy = 'KNOWLEDGE_ONLY',
  String fallback = '',
}) => {
  'is_ai_enabled': aiEnabled,
  'is_auto_send_enabled': true,
  'daily_request_limit': 5000,
  'daily_token_limit': 2000000,
  'rollout_state': 'PILOT',
  'default_auto_reply_policy': defaultPolicy,
  'fallback_instructions': fallback,
};

Json _channel({
  int id = 12,
  String name = 'Gad',
  String mode = 'AUTO',
  String status = 'CONNECTED',
  String replyPolicy = 'INHERIT',
  bool assistSupported = true,
}) => {
  'connection_id': id,
  'connection_name': name,
  'provider': 'WHATSAPP',
  'status': status,
  'mode': mode,
  'assist_supported': assistSupported,
  'auto_supported': assistSupported,
  'auto_reply_policy': replyPolicy,
  'effective_auto_reply_policy': replyPolicy == 'INHERIT'
      ? 'KNOWLEDGE_ONLY'
      : replyPolicy,
  'effective_auto_reply_source': replyPolicy == 'INHERIT'
      ? 'ORGANIZATION'
      : 'CONNECTION',
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
};

Json _readiness({
  int id = 12,
  List<String> blocking = const [],
  List<String> warnings = const [],
}) => {
  'connection_id': id,
  'provider': 'WHATSAPP',
  'state': blocking.isEmpty ? 'READY_FOR_AUTO' : 'NOT_READY',
  'suggest_allowed': blocking.isEmpty,
  'auto_allowed': blocking.isEmpty,
  'blocking': blocking,
  'warnings': warnings,
  'detail': {'sources_ready': 6, 'embedded_chunks': 6, 'sources_failed': 0},
};

Json _base(String id, {int sources = 6, int ready = 6}) => {
  'id': id,
  'name': 'Stage 1 test',
  'description': '',
  'is_active': true,
  'source_count': sources,
  'ready_source_count': ready,
  'created_by_name': 'Admin',
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-01T10:00:00Z',
};

Json _change() => {
  'setting': 'mode',
  'previous_value': 'SUGGEST',
  'new_value': 'AUTO',
  'channel_connection_id': 12,
  'conversation_id': null,
  'actor': 'Admin User',
  'source': 'settings',
  'note': '',
  'at': '2026-11-06T09:30:00Z',
};

class _Server {
  _Server({
    List<Json>? channels,
    List<Json>? readiness,
    List<Json>? bases,
    Json? policy,
    Json? metrics,
    this.conflicts = const [],
    this.history = const [],
  }) : channels = channels ?? [_channel()],
       readiness = readiness ?? [_readiness()],
       bases = bases ?? [_base('kb-1')],
       policy = policy ?? _policy(),
       metrics = metrics ?? _metrics();

  List<Json> channels;
  List<Json> readiness;
  List<Json> bases;
  Json policy;
  Json metrics;
  List<Json> conflicts;
  List<Json> history;

  final overrides = <String, FutureOr<ResponseBody> Function(RequestOptions)>{};
  final requests = <RequestOptions>[];

  Iterable<RequestOptions> get writes =>
      requests.where((r) => r.method != 'GET');

  List<Object?> queriesOf(String path, String name) => [
    for (final r in requests)
      if (r.path == path) r.queryParameters[name],
  ];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Json _page(List<Json> rows) => {
    'count': rows.length,
    'page': 1,
    'page_size': 100,
    'total_pages': 1,
    'next': null,
    'previous': null,
    'results': rows,
  };

  FutureOr<ResponseBody> _handle(RequestOptions o) {
    requests.add(o);
    if (overrides[o.path] case final handler?) return handler(o);
    switch (o.path) {
      case '/ai/policy/':
        if (o.method == 'PUT') policy = {...policy, ...o.data as Map};
        return _json(policy);
      case '/ai/agent-settings/':
        if (o.method == 'PUT') {
          final body = Map<String, dynamic>.from(o.data as Map);
          final id = body.remove('connection_id');
          channels = [
            for (final row in channels)
              if (row['connection_id'] != id)
                row
              else
                {
                  ...row,
                  ...body..remove('handoff_on_restricted_topic'),
                  if (o.data['handoff_on_restricted_topic'] case final bool on)
                    'handoff_rules': [
                      for (final r in row['handoff_rules'] as List)
                        (r as Json)['locked'] == false
                            ? {...r, 'enabled': on}
                            : r,
                    ],
                },
          ];
        }
        return _json(channels);
      case '/ai/readiness/':
        return _json(readiness);
      case '/ai/conflicts/':
        return _json(conflicts);
      case '/ai/metrics/':
        return _json(metrics);
      case '/ai/usage/':
        return _json(_usage());
      case '/ai/history/':
        return _json(history);
      case '/knowledge-bases/':
        return _json(_page(bases));
      case '/knowledge-sources/':
        return _json(_page(const []));
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

/// The AI section under a router, so the organization settings screen can be
/// pushed and popped as it is in the app.
Future<GoRouter> _pumpSection(
  WidgetTester tester,
  _Server server, {
  Employee? employee,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 5000),
}) async {
  final router = GoRouter(
    initialLocation: Routes.settings,
    routes: [
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const Scaffold(body: AiKnowledgeSettingsTab()),
        routes: [
          GoRoute(path: 'ai-policy', builder: (_, _) => const AiPolicyScreen()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _open(WidgetTester tester, AiSection section) async {
  ProviderScope.containerOf(
    tester.element(find.byType(AiKnowledgeSettingsTab)),
  ).read(aiSectionProvider.notifier).select(section);
  await tester.pumpAndSettle();
}

AiSection _current(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(AiKnowledgeSettingsTab)),
).read(aiSectionProvider);

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
    test('metrics, with the reply breakdown and a missing field left out', () {
      final m = AiMetrics.fromJson(_metrics());
      expect(m.kbAnswered, 3);
      expect(m.fallbacks, 1);
      expect(m.fallbackRate, 0.25);
      expect(m.conversationalReplies, 4);
      expect(m.maxAutoTurns, isNull, reason: 'retired by the backend');

      final partial = AiMetrics.fromJson({..._metrics()}..remove('sent'));
      expect(partial.sent, isNull);
      expect(AiMetrics.fromJson(const {}).conversationalReplies, isNull);
      expect(AiMetrics.fromJson(_quietMetrics()).isQuiet, isTrue);
    });

    test('usage, with requests by model and its start', () {
      final u = AiUsageSummary.fromJson(_usage());
      expect(u.requests, 20);
      expect(u.byModel, {'model-small': 5, 'model-large': 15});
      expect(u.since, DateTime.utc(2026, 10, 6).toLocal());
    });

    test('policy, with the automatic-reply default and holding message', () {
      final p = AiOrganizationPolicy.fromJson(
        _policy(defaultPolicy: 'ALWAYS_REPLY', fallback: 'Sorry, one moment.'),
      );
      expect(p.defaultAutoReplyPolicy, AiAutoReplyPolicy.alwaysReply);
      expect(p.fallbackInstructions, 'Sorry, one moment.');

      final older = AiOrganizationPolicy.fromJson(
        {..._policy()}
          ..remove('default_auto_reply_policy')
          ..remove('fallback_instructions'),
      );
      expect(older.defaultAutoReplyPolicy, isEmpty);
      expect(
        () => AiOrganizationPolicy.fromJson(
          {..._policy()}..remove('is_ai_enabled'),
        ),
        throwsFormatException,
      );
      // The organization form never sends the two it does not edit.
      expect(p.changesTo(p), isEmpty);
    });

    test('a channel reads its reply policy and limits', () {
      final row = AiAgentSetting.fromJson(_channel());
      expect(row.autoReplyPolicy, AiAutoReplyPolicy.inherit);
      expect(row.effectiveAutoReplyPolicy, AiAutoReplyPolicy.knowledgeOnly);
      expect(row.autoSupported, isTrue);
      expect(row.hasChannelConfig, isTrue);
      expect(row.dailyAutoSendLimit, 500);
      expect(row.handoffOnRestrictedTopic, isTrue);

      final bare = AiAgentSetting.fromJson({
        'connection_id': 1,
        'connection_name': 'x',
        'provider': 'WHATSAPP',
        'mode': 'OFF',
        'assist_supported': false,
      });
      expect(bare.hasChannelConfig, isFalse);
      expect(bare.autoSupported, isFalse, reason: 'follows assist_supported');
    });

    test('history', () {
      final change = AiConfigurationChange.fromJson(_change());
      expect(change.setting, 'mode');
      expect(change.newValue, 'AUTO');
      expect(change.channelConnectionId, 12);
      expect(change.conversationId, isNull);
      expect(change.at, DateTime.utc(2026, 11, 6, 9, 30).toLocal());
    });

    test('history and usage ask for their windows', () async {
      final server = _Server();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(server.client())],
      );
      addTearDown(container.dispose);
      final repo = container.read(aiKnowledgeRepositoryProvider);
      await repo.history();
      await repo.usage(days: 7);
      await repo.metrics(hours: 1000);
      expect(server.queriesOf('/ai/history/', 'limit'), [50]);
      expect(server.queriesOf('/ai/usage/', 'days'), [7]);
      expect(server.queriesOf('/ai/metrics/', 'hours'), [720]);
    });

    test('formats rates, durations and missing values like the web', () {
      expect(aiPercent(0), '0%');
      expect(aiPercent(0.125), '12.5%');
      expect(aiPercent(null), '—');
      expect(aiDuration(40), '40 ms');
      expect(aiDuration(812), '0.8s');
      expect(aiCount(14539), '14539');
    });
  });

  // ------------------------------------------------------------------------ //
  group('navigation', () {
    testWidgets('five tabs, in the web order, each with its own page', (
      tester,
    ) async {
      await _pumpSection(tester, _Server());

      final tabs = [
        ('ai-tab-overview', 'Overview', 'ai-overview'),
        ('ai-tab-knowledge', 'Knowledge Base', 'ai-knowledge-tab'),
        ('ai-tab-agent', 'AI Agent & Automatic Replies', 'ai-agent'),
        ('ai-tab-playground', 'AI Playground', 'ai-playground'),
        ('ai-tab-activity', 'Activity & Usage', 'ai-activity'),
      ];
      // In order, before any tap scrolls the bar.
      final xs = [
        for (final (tabKey, _, _) in tabs)
          tester.getTopLeft(find.byKey(Key(tabKey))).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      for (final (tabKey, label, pageKey) in tabs) {
        final tab = find.byKey(Key(tabKey));
        expect(
          find.descendant(of: tab, matching: find.text(label)),
          findsOneWidget,
        );
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(find.byKey(Key(pageKey)), findsOneWidget, reason: label);
      }
    });

    testWidgets('what was typed on a tab survives visiting another', (
      tester,
    ) async {
      await _pumpSection(tester, _Server());
      await _open(tester, AiSection.playground);
      await tester.enterText(
        find.byKey(const Key('playground-question')),
        'Hours?',
      );
      await _open(tester, AiSection.activity);
      await _open(tester, AiSection.playground);
      expect(find.text('Hours?'), findsOneWidget);
    });

    testWidgets('tabs share their data rather than asking again', (
      tester,
    ) async {
      final server = _Server();
      await _pumpSection(tester, server);
      for (final section in AiSection.values) {
        await _open(tester, section);
      }
      // Overview and Activity both show the last 24 hours: one request.
      expect(server.queriesOf('/ai/metrics/', 'hours'), [24]);
      expect(
        server.requests.where((r) => r.path == '/ai/policy/'),
        hasLength(1),
      );
      expect(
        server.requests.where((r) => r.path == '/knowledge-bases/'),
        hasLength(1),
      );
    });

    testWidgets('without ai_knowledge.manage nothing is offered or fetched', (
      tester,
    ) async {
      final server = _Server();
      await _pumpSection(tester, server, employee: _employee(allowed: false));
      expect(
        find.byKey(const Key('ai-knowledge-not-available')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-section-tabs')), findsNothing);
      expect(server.requests, isEmpty);
    });
  });

  // ------------------------------------------------------------------------ //
  group('overview', () {
    testWidgets('status, channels, knowledge and the last 24 hours', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _Server(
          channels: [
            _channel(),
            _channel(id: 13, name: 'Page', mode: 'OFF'),
            _channel(id: 14, name: 'Shop', mode: 'OFF'),
          ],
          readiness: [_readiness(), _readiness(id: 13), _readiness(id: 14)],
        ),
      );

      expect(find.text('On'), findsOneWidget);
      expect(find.text('Rollout: Pilot'), findsOneWidget);
      expect(
        find.text('Default automatic reply: Knowledge only'),
        findsOneWidget,
      );
      expect(_tileValue(tester, 'overview-channels-auto'), '1');
      expect(_tileValue(tester, 'overview-channels-suggest'), '0');
      expect(_tileValue(tester, 'overview-channels-off'), '2');
      expect(
        find.text(
          '1 knowledge base  ·  6 of 6 sources ready  ·  6 indexed extracts',
        ),
        findsOneWidget,
      );
      expect(_tileValue(tester, 'overview-sent'), '4');
      expect(_tileValue(tester, 'overview-kb-answered'), '3');
      expect(_tileValue(tester, 'overview-fallbacks'), '1');
      expect(
        find.text('25% of what was sent answered nothing.'),
        findsOneWidget,
      );
    });

    testWidgets('each part opens the tab that changes it', (tester) async {
      await _pumpSection(tester, _Server());

      await tester.tap(find.byKey(const Key('overview-channels-auto')));
      await tester.pumpAndSettle();
      expect(_current(tester), AiSection.agent);

      await _open(tester, AiSection.overview);
      await tester.tap(find.byKey(const Key('overview-knowledge')));
      await tester.pumpAndSettle();
      expect(_current(tester), AiSection.knowledge);

      await _open(tester, AiSection.overview);
      await tester.tap(find.byKey(const Key('overview-sent')));
      await tester.pumpAndSettle();
      expect(_current(tester), AiSection.activity);
      expect(find.byKey(const Key('ai-activity')), findsOneWidget);
    });

    testWidgets('nothing to report when nothing needs attention', (
      tester,
    ) async {
      await _pumpSection(tester, _Server(metrics: _metrics(fallbackRate: 0.1)));
      expect(
        find.byKey(const Key('overview-nothing-to-report')),
        findsOneWidget,
      );
    });

    testWidgets('worth your attention: the web checks and channel readiness', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _Server(
          policy: _policy(aiEnabled: false, defaultPolicy: 'OFF'),
          metrics: _metrics(fallbackRate: 0.5),
          conflicts: [
            {
              'sources': ['Returns A', 'Returns B'],
              'reason': '14 vs 30 days',
            },
          ],
          readiness: [
            _readiness(warnings: ['NO_HANDOFF_ROUTE']),
          ],
        ),
      );

      for (final text in [
        'AI is switched off for this organization, so nothing below runs.',
        '1 pair of sources answers the same question differently.',
        'Automatic replies are off by default, so no channel sends unattended.',
        '50% of automatic replies answered nothing. That is a knowledge gap, not a setting.',
        'Gad: Nobody is available to receive a handed-off conversation',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }

      await tester.tap(find.text('Open Knowledge Base').first);
      await tester.pumpAndSettle();
      expect(_current(tester), AiSection.knowledge);
      expect(find.byKey(const Key('ai-conflicts')), findsOneWidget);
    });

    testWidgets('a quiet day says so', (tester) async {
      await _pumpSection(tester, _Server(metrics: _quietMetrics()));
      expect(find.byKey(const Key('overview-quiet')), findsOneWidget);
    });

    testWidgets('change history loads only when opened', (tester) async {
      final server = _Server(history: [_change()]);
      await _pumpSection(tester, server);
      expect(server.requests.where((r) => r.path == '/ai/history/'), isEmpty);

      await tester.tap(find.byKey(const Key('ai-history')));
      await tester.pumpAndSettle();
      expect(server.queriesOf('/ai/history/', 'limit'), [50]);
      expect(find.byKey(const Key('ai-history-row')), findsOneWidget);
      expect(find.text('SUGGEST → AUTO'), findsOneWidget);
      expect(find.textContaining('by Admin User'), findsOneWidget);
      expect(find.textContaining('Gad'), findsWidgets);
    });

    testWidgets('an empty history says so', (tester) async {
      await _pumpSection(tester, _Server());
      await tester.tap(find.byKey(const Key('ai-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-history-empty')), findsOneWidget);
    });

    testWidgets('a failed policy read offers retry', (tester) async {
      final server = _Server();
      var fail = true;
      server.overrides['/ai/policy/'] = (_) =>
          fail ? _error(500, 'server_error') : _json(_policy());
      await _pumpSection(tester, server);
      expect(find.text('Try again'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Rollout: Pilot'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  group('AI Agent & Automatic Replies', () {
    testWidgets('the default is saved as it is chosen', (tester) async {
      final server = _Server();
      await _pumpSection(tester, server);
      await _open(tester, AiSection.agent);

      expect(find.byKey(const Key('ai-fallback-instructions')), findsNothing);
      await tester.tap(find.byKey(const Key('ai-default-policy-ALWAYS_REPLY')));
      await tester.pumpAndSettle();
      expect(server.writes.single.path, '/ai/policy/');
      expect(server.writes.single.data, {
        'default_auto_reply_policy': 'ALWAYS_REPLY',
      });

      // Always reply brings the holding message with it.
      final field = find.byKey(const Key('ai-fallback-instructions'));
      expect(field, findsOneWidget);
      final save = find.byKey(const Key('ai-fallback-instructions-save'));
      expect(tester.widget<TextButton>(save).onPressed, isNull);
      await tester.enterText(field, '  Sorry — the team will reply soon.  ');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(server.writes.last.data, {
        'fallback_instructions': 'Sorry — the team will reply soon.',
      });
    });

    testWidgets('a channel: status, readiness, and what it replies with', (
      tester,
    ) async {
      final server = _Server();
      await _pumpSection(tester, server);
      await _open(tester, AiSection.agent);

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Ready for automatic replies'), findsOneWidget);
      expect(find.text('In effect: Knowledge only'), findsOneWidget);
      expect(
        find.text('Using the organization default: Knowledge only.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('assist-12-reply-policy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always reply').last);
      await tester.pumpAndSettle();
      expect(server.writes.single.data, {
        'auto_reply_policy': 'ALWAYS_REPLY',
        'connection_id': 12,
      });
      expect(find.text('Overridden for this channel.'), findsOneWidget);
    });

    testWidgets('what it replies with is fixed unless the channel is automatic', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _Server(channels: [_channel(mode: 'SUGGEST')]),
      );
      await _open(tester, AiSection.agent);

      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('assist-12-reply-policy')),
      );
      expect(dropdown.onChanged, isNull);
      expect(
        find.text(
          'Automatic replies are inactive because this channel is in Suggest mode.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('limits & safety save one field at a time', (tester) async {
      final server = _Server();
      await _pumpSection(tester, server);
      await _open(tester, AiSection.agent);

      expect(find.byKey(const Key('assist-12-limits')), findsNothing);
      await tester.tap(find.byKey(const Key('assist-12-limits-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assist-12-limits')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ai-channel-daily-cap')),
        '300',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-channel-daily-cap-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-grounding-STRICT')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-resume-WAIT')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-channel-new-topic')),
        'warranty',
      );
      await tester.tap(find.byKey(const Key('ai-channel-add-topic')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('ai-handoff-RESTRICTED_TOPIC-toggle')),
      );
      await tester.pumpAndSettle();

      expect(
        [for (final w in server.writes) w.data],
        [
          {'daily_auto_send_limit': 300, 'connection_id': 12},
          {'grounding_profile': 'STRICT', 'connection_id': 12},
          {'resume_behaviour': 'WAIT', 'connection_id': 12},
          {
            'extra_restricted_topics': ['shipping', 'warranty'],
            'connection_id': 12,
          },
          {'handoff_on_restricted_topic': false, 'connection_id': 12},
        ],
      );
      expect(find.byKey(const Key('ai-topic-warranty')), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
    });

    testWidgets('limits are checked against the API bounds before saving', (
      tester,
    ) async {
      final server = _Server();
      await _pumpSection(tester, server);
      await _open(tester, AiSection.agent);
      await tester.tap(find.byKey(const Key('assist-12-limits-toggle')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('ai-channel-daily-cap')),
        '1001',
      );
      await tester.pump();
      expect(find.text('Enter a whole number from 1 to 1000.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('ai-channel-daily-cap-save')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('ai-channel-new-topic')),
        'Legal',
      );
      await tester.tap(find.byKey(const Key('ai-channel-add-topic')));
      await tester.pumpAndSettle();
      expect(find.text('That topic is already listed.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('a channel that is off has no limits to set', (tester) async {
      await _pumpSection(tester, _Server(channels: [_channel(mode: 'OFF')]));
      await _open(tester, AiSection.agent);
      expect(find.byKey(const Key('assist-12-limits-toggle')), findsNothing);
    });

    testWidgets('a refused change keeps the server state and says why', (
      tester,
    ) async {
      final server = _Server();
      server.overrides['/ai/agent-settings/'] = (o) => o.method == 'PUT'
          ? _error(400, 'validation_error')
          : _json([_channel()]);
      await _pumpSection(tester, server);
      await _open(tester, AiSection.agent);

      await tester.tap(find.byKey(const Key('assist-12-reply-policy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();
      expect(find.text('Refused: validation_error'), findsOneWidget);
      expect(
        find.text('Using the organization default: Knowledge only.'),
        findsOneWidget,
      );
    });

    testWidgets('conflicts appear here too and open the knowledge base', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        _Server(
          conflicts: [
            {
              'sources': ['A', 'B'],
              'reason': 'differs',
            },
          ],
        ),
      );
      await _open(tester, AiSection.agent);
      await tester.tap(find.byKey(const Key('ai-conflicts-open-knowledge')));
      await tester.pumpAndSettle();
      expect(_current(tester), AiSection.knowledge);
    });

    testWidgets('opens the organization settings', (tester) async {
      final router = await _pumpSection(tester, _Server());
      await _open(tester, AiSection.agent);
      await tester.tap(find.byKey(const Key('ai-agent-organization-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(AiPolicyScreen), findsOneWidget);
      expect(router.state.uri.path, Routes.aiPolicy);
    });
  });

  // ------------------------------------------------------------------------ //
  group('Activity & Usage', () {
    testWidgets(
      'groups the server numbers and leaves out what it did not send',
      (tester) async {
        await _pumpSection(
          tester,
          _Server(metrics: {..._metrics()}..remove('coalesced_messages')),
        );
        await _open(tester, AiSection.activity);

        expect(_tileValue(tester, 'metric-opportunities'), '6');
        expect(_tileValue(tester, 'metric-sent'), '4');
        expect(_tileValue(tester, 'metric-kb-answered'), '3');
        expect(_tileValue(tester, 'metric-conversational'), '4');
        expect(_tileValue(tester, 'metric-fallbacks'), '1');
        expect(_tileValue(tester, 'metric-send-rate'), '50%');
        expect(_tileValue(tester, 'metric-average-retrieval'), '40 ms');
        expect(_tileValue(tester, 'metric-tokens'), '14539');
        expect(_tileValue(tester, 'metric-connections-off'), '16');
        expect(find.byKey(const Key('metric-coalesced')), findsNothing);
        // The retired reason is not invented as a row.
        expect(find.byKey(const Key('reason-max-auto-turns')), findsNothing);

        final provider = tester
            .getTopLeft(find.byKey(const Key('reason-provider-unavailable')))
            .dy;
        final notInKb = tester
            .getTopLeft(find.byKey(const Key('reason-not-in-kb')))
            .dy;
        expect(provider, lessThan(notInKb));
      },
    );

    testWidgets('each window asks for its own hours', (tester) async {
      final server = _Server();
      await _pumpSection(tester, server);
      await _open(tester, AiSection.activity);

      await tester.tap(find.byKey(const Key('ai-window-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-window-168')));
      await tester.pumpAndSettle();
      expect(server.queriesOf('/ai/metrics/', 'hours'), [24, 1, 168]);
    });

    testWidgets('usage: its period, start, numbers and models', (tester) async {
      final server = _Server();
      await _pumpSection(tester, server);
      await _open(tester, AiSection.activity);

      expect(find.text('This organization, last 30 days.'), findsOneWidget);
      expect(find.byKey(const Key('usage-since')), findsOneWidget);
      expect(_tileValue(tester, 'usage-requests'), '20');
      expect(_tileValue(tester, 'usage-output-tokens'), '2539');
      final large = tester
          .getTopLeft(find.byKey(const Key('usage-model-model-large')))
          .dy;
      final small = tester
          .getTopLeft(find.byKey(const Key('usage-model-model-small')))
          .dy;
      expect(large, lessThan(small));

      await tester.tap(find.byKey(const Key('ai-usage-days-7')));
      await tester.pumpAndSettle();
      expect(server.queriesOf('/ai/usage/', 'days'), [30, 7]);
      expect(find.text('This organization, last 7 days.'), findsOneWidget);
    });

    testWidgets('a quiet window says so', (tester) async {
      await _pumpSection(tester, _Server(metrics: _quietMetrics()));
      await _open(tester, AiSection.activity);
      expect(find.byKey(const Key('ai-activity-quiet')), findsOneWidget);
      expect(find.byKey(const Key('ai-no-declines')), findsOneWidget);
    });

    testWidgets('a failed read shows at once, with retry', (tester) async {
      final server = _Server();
      var fail = true;
      server.overrides['/ai/metrics/'] = (_) =>
          fail ? _error(500, 'server_error') : _json(_metrics());
      await _pumpSection(tester, server);
      await _open(tester, AiSection.activity);
      expect(find.text('Try again'), findsWidgets);

      fail = false;
      await tester.tap(find.text('Try again').last);
      await tester.pumpAndSettle();
      expect(_tileValue(tester, 'metric-opportunities'), '6');
    });
  });

  // ------------------------------------------------------------------------ //
  group('organization settings', () {
    Future<void> openPolicy(WidgetTester tester, _Server server) async {
      final router = await _pumpSection(tester, server);
      router.push(Routes.aiPolicy);
      await tester.pumpAndSettle();
    }

    testWidgets('Save sends only what changed', (tester) async {
      final server = _Server();
      await openPolicy(tester, server);

      final save = find.byKey(const Key('ai-policy-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('ai-policy-request-limit')),
        '7000',
      );
      await tester.tap(find.byKey(const Key('ai-policy-auto-send')));
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(server.writes.single.data, {
        'is_auto_send_enabled': false,
        'daily_request_limit': 7000,
      });
      expect(find.text('AI policy saved.'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });

    testWidgets('an out-of-range limit is caught before sending', (
      tester,
    ) async {
      final server = _Server();
      await openPolicy(tester, server);
      await tester.enterText(
        find.byKey(const Key('ai-policy-request-limit')),
        '2000000',
      );
      await tester.pump();
      expect(
        find.text('Enter a whole number from 0 to 1000000.'),
        findsOneWidget,
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
      await openPolicy(tester, server);
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
      await openPolicy(tester, _Server());
      await tester.tap(find.byKey(const Key('ai-policy-ai-enabled')));
      await tester.pump();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
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
      expect(find.byType(AiKnowledgeSettingsTab), findsOneWidget);
    });

    testWidgets('a save shows on the overview at once', (tester) async {
      final server = _Server();
      await openPolicy(tester, server);
      await tester.tap(find.byKey(const Key('ai-policy-ai-enabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-policy-save')));
      await tester.pumpAndSettle();
      await tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsWidgets);
      expect(
        find.text(
          'AI is switched off for this organization, so nothing below runs.',
        ),
        findsOneWidget,
      );
    });
  });

  // ------------------------------------------------------------------------ //
  testWidgets('Arabic, on a narrow phone: every tab lays out right to left', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      _Server(
        policy: _policy(defaultPolicy: 'ALWAYS_REPLY'),
        readiness: [
          _readiness(warnings: ['NO_HANDOFF_ROUTE']),
        ],
        history: [_change()],
      ),
      locale: const Locale('ar'),
      size: const Size(320, 8000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('الحالة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byKey(const Key('ai-overview')))),
      TextDirection.rtl,
    );
    await tester.tap(find.byKey(const Key('ai-history')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _open(tester, AiSection.agent);
    await tester.tap(find.byKey(const Key('assist-12-limits-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('الردود التلقائية للذكاء الاصطناعي'), findsOneWidget);
    expect(find.text('مرن'), findsOneWidget);

    for (final section in [
      AiSection.knowledge,
      AiSection.playground,
      AiSection.activity,
    ]) {
      await _open(tester, section);
      expect(tester.takeException(), isNull, reason: '$section');
    }
    expect(find.text('النشاط والاستخدام'), findsOneWidget);
  });
}
