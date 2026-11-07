/// AI & Knowledge settings: knowledge bases, sources, the answer
/// playground, Agent Assist and usage — against a stubbed backend speaking
/// the OpenAPI contract (`/knowledge-bases/`, `/knowledge-sources/`,
/// `/ai/playground/ask/`, `/ai/agent-settings/`, `/ai/readiness/`,
/// `/ai/conflicts/`, `/ai/usage/`).
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
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/config/environment.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/knowledge.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_knowledge_labels.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_knowledge_providers.dart';
import 'package:scenario_mobile/features/ai_knowledge/ai_knowledge_settings_tab.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// --------------------------------------------------------------------------- //
// Stub backend
// --------------------------------------------------------------------------- //

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

ResponseBody _noContent() => ResponseBody.fromString('', 204);

ResponseBody _error(int status, String code, [String message = 'Refused.']) =>
    _json({
      'error': {'code': code, 'message': message, 'details': {}},
    }, status);

Map<String, Object?> _page(List<Map<String, Object?>> rows) => {
  'count': rows.length,
  'page': 1,
  'page_size': 100,
  'total_pages': 1,
  'next': null,
  'previous': null,
  'results': rows,
};

Map<String, Object?> _base(
  String id, {
  String name = 'Store policies',
  bool isActive = true,
  int sources = 0,
  int ready = 0,
}) => {
  'id': id,
  'name': name,
  'description': '',
  'is_active': isActive,
  'source_count': sources,
  'ready_source_count': ready,
  'created_by_name': 'Admin',
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-01T10:00:00Z',
};

Map<String, Object?> _source(
  String id, {
  String kb = 'kb-1',
  String type = 'PLAIN_TEXT',
  String status = 'READY',
  String title = 'Delivery',
  String question = '',
  String answer = '',
  String body = 'Cairo delivery takes 1–2 days.',
  int chunks = 1,
  String errorDetail = '',
}) => {
  'id': id,
  'knowledge_base_id': kb,
  'source_type': type,
  'title': title,
  'display_title': title.isNotEmpty ? title : question,
  'question': question,
  'answer': answer,
  'body': body,
  'status': status,
  'attempts': 1,
  'error_code': '',
  'error_detail': errorDetail,
  'chunk_count': chunks,
  'created_by_name': 'Admin',
  'indexed_at': status == 'READY' ? '2026-11-01T20:04:00Z' : null,
  'created_at': '2026-11-01T20:00:00Z',
  'updated_at': '2026-11-01T20:00:00Z',
};

Map<String, Object?> _answered() => {
  'status': 'ANSWERED',
  'answer': 'Returns are accepted within 14 days.',
  'citations': [
    {
      'source_id': 's-1',
      'source_title': 'Returns policy',
      'source_type': 'PLAIN_TEXT',
      'chunk_id': 'c-1',
      'rank': 1,
      'score': 0.91,
    },
  ],
  'retrieved': [
    {
      'rank': 1,
      'score': 0.912,
      'chunk_id': 'c-1',
      'chunk_index': 0,
      'text': 'Returns within 14 days with a receipt.',
      'source_id': 's-1',
      'source_title': 'Returns policy',
      'source_type': 'PLAIN_TEXT',
    },
  ],
  'model': 'model-x',
  'provider': 'provider-x',
  'policy_version': 'v1',
  'duration_ms': 812,
  'retrieval_ms': 34,
  'input_tokens': 300,
  'output_tokens': 40,
  'cached_tokens': 0,
  'total_tokens': 340,
  'error_code': '',
  'error_detail': '',
  'conflict_reason': '',
};

Map<String, Object?> _notInKb() => {
  ..._answered(),
  'status': 'NOT_IN_KB',
  'answer': '',
  'citations': <Object>[],
};

Map<String, Object?> _providerError() => {
  ..._answered(),
  'status': 'ERROR',
  'answer': '',
  'citations': <Object>[],
  'retrieved': <Object>[],
  'error_code': 'provider_timeout',
  'error_detail': 'The provider did not answer in time.',
};

class _Server {
  _Server({
    List<Map<String, Object?>>? bases,
    Map<String, List<Map<String, Object?>>>? sources,
    List<Map<String, Object?>>? agentSettings,
    List<Map<String, Object?>>? readiness,
    this.conflicts = const [],
    this.basesStatus,
    this.playground,
  }) : bases = bases ?? [_base('kb-1')],
       sources = sources ?? {'kb-1': []},
       agentSettings = agentSettings ?? [],
       readiness = readiness ?? [];

  List<Map<String, Object?>> bases;
  Map<String, List<Map<String, Object?>>> sources;
  List<Map<String, Object?>> agentSettings;
  List<Map<String, Object?>> readiness;
  List<Map<String, Object?>> conflicts;

  /// Overrides the knowledge-base list's answer with this status.
  int? basesStatus;

  FutureOr<ResponseBody> Function(RequestOptions options)? playground;

  final requests = <RequestOptions>[];
  final expired = <int?>[];

  Iterable<RequestOptions> get writes =>
      requests.where((r) => r.method != 'GET');

  ApiClient client({CookieJar? jar}) {
    final client = ApiClient.create(
      cookieJar: jar ?? CookieJar(),
      onSessionExpired: expired.add,
    );
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Map<String, dynamic> _body(RequestOptions o) =>
      Map<String, dynamic>.from(o.data as Map);

  FutureOr<ResponseBody> _handle(RequestOptions o) {
    requests.add(o);
    final path = o.path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();

    if (path == '/knowledge-bases/') {
      if (o.method == 'GET') {
        if (basesStatus case final status?) {
          return _error(status, status == 404 ? 'not_found' : 'error');
        }
        return _json(_page(bases));
      }
      final created = {
        ..._base('kb-new', name: _body(o)['name'] as String),
        'description': _body(o)['description'] ?? '',
      };
      bases = [...bases, created];
      sources['kb-new'] = [];
      return _json(created, 201);
    }
    if (segments.length == 2 && segments[0] == 'knowledge-bases') {
      final id = segments[1];
      if (o.method == 'DELETE') {
        bases = [...bases.where((b) => b['id'] != id)];
        return _noContent();
      }
      final index = bases.indexWhere((b) => b['id'] == id);
      final updated = {...bases[index], ..._body(o)};
      bases = [...bases]..[index] = updated;
      return _json(updated);
    }
    if (path == '/knowledge-sources/') {
      if (o.method == 'GET') {
        final kb = o.queryParameters['knowledge_base'] as String;
        return _json(_page(sources[kb] ?? []));
      }
      final body = _body(o);
      final kb = body['knowledge_base_id'] as String;
      final created = _source(
        'src-new',
        kb: kb,
        type: body['source_type'] as String,
        status: 'PENDING',
        title: body['title'] as String? ?? '',
        question: body['question'] as String? ?? '',
        answer: body['answer'] as String? ?? '',
        body: body['body'] as String? ?? '',
        chunks: 0,
      );
      sources[kb] = [...?sources[kb], created];
      return _json(created, 201);
    }
    if (segments.length >= 2 && segments[0] == 'knowledge-sources') {
      final id = segments[1];
      final kb = sources.entries
          .firstWhere((e) => e.value.any((s) => s['id'] == id))
          .key;
      final list = sources[kb]!;
      final index = list.indexWhere((s) => s['id'] == id);
      if (o.method == 'DELETE') {
        sources[kb] = [...list]..removeAt(index);
        return _noContent();
      }
      final updated = {
        ...list[index],
        if (segments.length == 2) ..._body(o),
        'status': 'PENDING',
      };
      sources[kb] = [...list]..[index] = updated;
      return _json(updated, segments.length == 3 ? 202 : 200);
    }
    if (path == '/ai/playground/ask/') {
      return playground?.call(o) ?? _json(_answered());
    }
    if (path == '/ai/agent-settings/') {
      if (o.method == 'PUT') {
        final body = _body(o);
        agentSettings = [
          for (final row in agentSettings)
            row['connection_id'] == body['connection_id']
                ? {...row, 'mode': body['mode']}
                : row,
        ];
      }
      return _json(agentSettings);
    }
    if (path == '/ai/readiness/') return _json(readiness);
    if (path == '/ai/conflicts/') return _json(conflicts);
    if (path == '/ai/usage/') {
      return _json({
        'requests': 19,
        'total_tokens': 13391,
        'input_tokens': 12000,
        'output_tokens': 1391,
        'answered': 10,
        'not_in_kb': 9,
        'errors': 0,
        'by_model': {'model-x': 19},
        'since': '2026-10-03T00:00:00Z',
      });
    }
    return _error(404, 'not_found');
  }
}

Employee _employee({
  Set<String> permissions = const {Perm.aiKnowledgeManage},
  bool aiKnowledgeEnabled = true,
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
  aiKnowledgeEnabled: aiKnowledgeEnabled,
);

Widget _harness(
  ApiClient client, {
  Employee? employee,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: AiKnowledgeSettingsTab()),
  ),
);

/// Pumps the AI section and, with [section], opens that tab.
Future<void> _pumpTab(
  WidgetTester tester,
  _Server server, {
  Employee? employee,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 5000),
  AiSection? section,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _harness(server.client(), employee: employee, locale: locale),
  );
  await tester.pumpAndSettle();
  if (section != null) await _open(tester, section);
}

/// Opens one of the AI section's tabs.
Future<void> _open(WidgetTester tester, AiSection section) async {
  ProviderScope.containerOf(
    tester.element(find.byType(AiKnowledgeSettingsTab)),
  ).read(aiSectionProvider.notifier).select(section);
  await tester.pumpAndSettle();
}

/// Lets a write travel through Dio's interceptors and its answer land,
/// without `pumpAndSettle` — which never settles while a source is still
/// being polled. Stays well under one poll interval.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(
    find.byKey(const Key('playground-question')),
    question,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('playground-ask')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------------ //
  group('playground request and validation', () {
    test('sends exactly knowledge_base_id and question to the ask endpoint, '
        'with the CSRF header', () async {
      final jar = CookieJar();
      await jar.saveFromResponse(Uri.parse(Environment.current.apiBaseUrl), [
        Cookie('scenario_csrftoken', 'tok-123'),
      ]);
      final server = _Server();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(server.client(jar: jar)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(playgroundControllerProvider, (_, _) {});

      final sent = await container
          .read(playgroundControllerProvider.notifier)
          .ask(knowledgeBaseId: 'kb-1', question: '  ايه مواعيد العمل؟  ');

      expect(sent, isTrue);
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/ai/playground/ask/');
      expect(request.data, {
        'knowledge_base_id': 'kb-1',
        'question': 'ايه مواعيد العمل؟',
      });
      expect(request.headers['X-CSRFToken'], 'tok-123');
    });

    test('validates the question by code points, like the server', () {
      expect(PlaygroundController.validate(''), PlaygroundQuestionError.empty);
      expect(
        PlaygroundController.validate('   \n '),
        PlaygroundQuestionError.empty,
      );
      expect(PlaygroundController.validate('a' * 1000), isNull);
      expect(
        PlaygroundController.validate('a' * 1001),
        PlaygroundQuestionError.tooLong,
      );
      // 600 emoji: 1200 UTF-16 units but 600 characters — allowed.
      expect(PlaygroundController.validate('😀' * 600), isNull);
    });

    test(
      'refuses to send without a knowledge base or a valid question',
      () async {
        final server = _Server();
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(server.client())],
        );
        addTearDown(container.dispose);
        container.listen(playgroundControllerProvider, (_, _) {});
        final controller = container.read(
          playgroundControllerProvider.notifier,
        );

        expect(
          await controller.ask(knowledgeBaseId: '', question: 'hi'),
          isFalse,
        );
        expect(
          await controller.ask(knowledgeBaseId: 'kb-1', question: ' '),
          isFalse,
        );
        expect(
          await controller.ask(knowledgeBaseId: 'kb-1', question: 'x' * 1001),
          isFalse,
        );
        expect(server.requests, isEmpty);
      },
    );

    test('a second ask while one is in flight is not sent', () async {
      final gate = Completer<void>();
      final server = _Server(
        playground: (_) async {
          await gate.future;
          return _json(_answered());
        },
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(server.client())],
      );
      addTearDown(container.dispose);
      container.listen(playgroundControllerProvider, (_, _) {});
      final controller = container.read(playgroundControllerProvider.notifier);

      final first = controller.ask(knowledgeBaseId: 'kb-1', question: 'one');
      expect(container.read(playgroundControllerProvider).asking, isTrue);
      expect(
        await controller.ask(knowledgeBaseId: 'kb-1', question: 'two'),
        isFalse,
      );
      gate.complete();
      expect(await first, isTrue);

      expect(
        server.requests.where((r) => r.path == '/ai/playground/ask/'),
        hasLength(1),
      );
      expect(container.read(playgroundControllerProvider).asking, isFalse);
    });

    test('parses ANSWERED, NOT_IN_KB and ERROR by status', () {
      final answered = PlaygroundAnswer.fromJson(_answered());
      expect(answered.status, PlaygroundStatus.answered);
      expect(answered.citations.single.sourceTitle, 'Returns policy');
      expect(answered.citations.single.score, 0.91);
      expect(answered.retrieved.single.text, contains('14 days'));
      expect(answered.totalTokens, 340);

      final notInKb = PlaygroundAnswer.fromJson(_notInKb());
      expect(notInKb.status, PlaygroundStatus.notInKb);
      expect(notInKb.answer, isEmpty);

      final error = PlaygroundAnswer.fromJson(_providerError());
      expect(error.status, PlaygroundStatus.error);
      expect(error.errorCode, 'provider_timeout');
    });

    test('a 401 ends the session and reaches the state as an error', () async {
      final server = _Server(
        playground: (_) => _error(401, 'not_authenticated'),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(server.client())],
      );
      addTearDown(container.dispose);
      container.listen(playgroundControllerProvider, (_, _) {});

      await container
          .read(playgroundControllerProvider.notifier)
          .ask(knowledgeBaseId: 'kb-1', question: 'hi');

      expect(
        container.read(playgroundControllerProvider).error,
        isA<SessionExpiredException>(),
      );
      expect(server.expired, hasLength(1));
    });

    test('never touches conversations or messages', () async {
      final server = _Server();
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(server.client())],
      );
      addTearDown(container.dispose);
      container.listen(playgroundControllerProvider, (_, _) {});
      final controller = container.read(playgroundControllerProvider.notifier);

      await controller.ask(knowledgeBaseId: 'kb-1', question: 'one');
      await controller.ask(knowledgeBaseId: 'kb-1', question: 'two');

      for (final request in server.requests) {
        expect(request.path, isNot(contains('conversation')));
        expect(request.path, isNot(contains('message')));
      }
      expect(server.writes.map((r) => r.path).toSet(), {'/ai/playground/ask/'});
    });
  });

  // ------------------------------------------------------------------------ //
  group('playground screen', () {
    testWidgets('ANSWERED shows the answer, its citations and diagnostics', (
      tester,
    ) async {
      final server = _Server();
      await _pumpTab(tester, server, section: AiSection.playground);

      await _ask(tester, 'What is the return period?');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-answered')), findsOneWidget);
      expect(find.text('Returns are accepted within 14 days.'), findsOneWidget);
      expect(find.byKey(const Key('playground-citation-c-1')), findsOneWidget);
      expect(find.text('Returns policy'), findsOneWidget);
      expect(find.text('0.91'), findsOneWidget);

      await tester.tap(find.byKey(const Key('playground-diagnostics')));
      await tester.pumpAndSettle();
      expect(
        find.text('Returns within 14 days with a receipt.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('812 ms · 340 tokens · model-x'),
        findsOneWidget,
      );
    });

    testWidgets('NOT_IN_KB says so and shows no answer', (tester) async {
      final server = _Server(playground: (_) => _json(_notInKb()));
      await _pumpTab(tester, server, section: AiSection.playground);

      await _ask(tester, 'Do you sell cars?');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-not-in-kb')), findsOneWidget);
      expect(find.text('Not in the knowledge base'), findsOneWidget);
      expect(find.byKey(const Key('playground-answer-text')), findsNothing);
    });

    testWidgets('ERROR shows the server detail, not an answer', (tester) async {
      final server = _Server(playground: (_) => _json(_providerError()));
      await _pumpTab(tester, server, section: AiSection.playground);

      await _ask(tester, 'Hours?');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-status-error')), findsOneWidget);
      expect(find.text('The provider did not answer in time.'), findsOneWidget);
      expect(find.text('provider_timeout'), findsOneWidget);
      expect(find.byKey(const Key('playground-answer-text')), findsNothing);
    });

    testWidgets('an unknown status is never rendered as an answer', (
      tester,
    ) async {
      final server = _Server(
        playground: (_) => _json({..._answered(), 'status': 'SOMETHING_NEW'}),
      );
      await _pumpTab(tester, server, section: AiSection.playground);

      await _ask(tester, 'Hours?');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playground-unknown')), findsOneWidget);
      expect(find.text('Returns are accepted within 14 days.'), findsNothing);
    });

    for (final (status, code, expected) in [
      (400, 'validation_error', 'question: Too long.'),
      (
        403,
        'permission_denied',
        "You don't have permission to manage AI knowledge.",
      ),
      (
        404,
        'not_found',
        "This knowledge base no longer exists, or AI isn't enabled for your organization.",
      ),
      (
        429,
        'throttled',
        "You've asked 30 questions in the last minute, the limit. Wait a moment and try again.",
      ),
    ]) {
      testWidgets('HTTP $status is explained', (tester) async {
        final server = _Server(
          playground: (_) => _error(status, code, 'question: Too long.'),
        );
        await _pumpTab(tester, server, section: AiSection.playground);

        await _ask(tester, 'Hours?');
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('playground-error')), findsOneWidget);
        expect(find.text(expected), findsOneWidget);
        expect(find.byKey(const Key('playground-answer-text')), findsNothing);
      });
    }

    testWidgets('loading disables Ask so a double tap sends one question', (
      tester,
    ) async {
      final gate = Completer<void>();
      final server = _Server(
        playground: (_) async {
          await gate.future;
          return _json(_answered());
        },
      );
      await _pumpTab(tester, server, section: AiSection.playground);

      await _ask(tester, 'Hours?');
      await tester.pump();
      expect(find.text('Asking…'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('playground-ask')),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byKey(const Key('playground-ask')));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();
      expect(
        server.requests.where((r) => r.path == '/ai/playground/ask/'),
        hasLength(1),
      );
      expect(find.text('Returns are accepted within 14 days.'), findsOneWidget);
    });

    testWidgets('with no knowledge base there is nothing to ask', (
      tester,
    ) async {
      final server = _Server(bases: []);
      await _pumpTab(tester, server, section: AiSection.playground);

      expect(
        find.text('Create a knowledge base before testing it.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('playground-question')),
      );
      expect(field.enabled, isFalse);
    });

    testWidgets('the answer belongs to the base it was asked of', (
      tester,
    ) async {
      final server = _Server(
        bases: [
          _base('kb-1'),
          _base('kb-2', name: 'Shipping'),
        ],
        sources: {'kb-1': [], 'kb-2': []},
      );
      await _pumpTab(tester, server, section: AiSection.playground);

      await _ask(tester, 'Hours?');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playground-answered')), findsOneWidget);
      expect(
        server.requests
            .lastWhere((r) => r.path == '/ai/playground/ask/')
            .data['knowledge_base_id'],
        'kb-1',
      );

      await _open(tester, AiSection.knowledge);
      await tester.tap(find.byKey(const Key('kb-kb-2-select')));
      await tester.pumpAndSettle();
      await _open(tester, AiSection.playground);
      expect(find.byKey(const Key('playground-answered')), findsNothing);

      await _ask(tester, 'Hours?');
      await tester.pumpAndSettle();
      expect(
        server.requests.lastWhere((r) => r.path == '/ai/playground/ask/').data,
        {'knowledge_base_id': 'kb-2', 'question': 'Hours?'},
      );
    });
  });

  // ------------------------------------------------------------------------ //
  group('knowledge bases', () {
    testWidgets('lists bases with their ready counts', (tester) async {
      final server = _Server(
        bases: [
          _base('kb-1', name: 'Stage 1 test', sources: 5, ready: 5),
          _base('kb-2', name: 'Old', isActive: false, sources: 2, ready: 1),
        ],
        sources: {'kb-1': [], 'kb-2': []},
      );
      await _pumpTab(tester, server, section: AiSection.knowledge);

      expect(find.text('Stage 1 test'), findsWidgets);
      expect(find.text('5 of 5 ready'), findsOneWidget);
      expect(find.text('1 of 2 ready'), findsOneWidget);
      expect(find.byKey(const Key('kb-kb-2-inactive')), findsOneWidget);
      expect(find.byKey(const Key('kb-kb-1-inactive')), findsNothing);
    });

    testWidgets('creates a base and selects it', (tester) async {
      final server = _Server();
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('ai-new-knowledge-base')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kb-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(server.writes, isEmpty);

      await tester.enterText(find.byKey(const Key('kb-form-name')), 'FAQ');
      await tester.tap(find.byKey(const Key('kb-form-save')));
      await tester.pumpAndSettle();

      final post = server.writes.single;
      expect(post.method, 'POST');
      expect(post.path, '/knowledge-bases/');
      expect(post.data, {'name': 'FAQ'});
      expect(find.byKey(const Key('kb-kb-new')), findsOneWidget);
      // The new base is the one the playground asks.
      await _open(tester, AiSection.playground);
      expect(
        find.byKey(const ValueKey('ai-playground-base-kb-new')),
        findsOneWidget,
      );
    });

    testWidgets('deactivates with PATCH is_active and shows the server state', (
      tester,
    ) async {
      final server = _Server();
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('kb-kb-1-toggle')));
      await tester.pumpAndSettle();

      final patch = server.writes.single;
      expect(patch.method, 'PATCH');
      expect(patch.path, '/knowledge-bases/kb-1/');
      expect(patch.data, {'is_active': false});
      expect(find.byKey(const Key('kb-kb-1-inactive')), findsOneWidget);
      expect(find.text('Activate'), findsOneWidget);
    });

    testWidgets('delete asks first, then DELETEs', (tester) async {
      final server = _Server();
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('kb-kb-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);

      await tester.tap(find.byKey(const Key('kb-kb-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-confirm-delete')));
      await tester.pumpAndSettle();

      expect(server.writes.single.method, 'DELETE');
      expect(server.writes.single.path, '/knowledge-bases/kb-1/');
      expect(find.byKey(const Key('kb-kb-1')), findsNothing);
      expect(find.byKey(const Key('ai-no-knowledge-bases')), findsOneWidget);
    });

    testWidgets('a failed load offers retry, which recovers', (tester) async {
      final server = _Server(basesStatus: 500);
      await _pumpTab(tester, server, section: AiSection.knowledge);

      expect(find.text('Try again'), findsOneWidget);
      server.basesStatus = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kb-kb-1')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  group('sources', () {
    testWidgets('lists sources with type, status and chunk count', (
      tester,
    ) async {
      final server = _Server(
        sources: {
          'kb-1': [
            _source('s-1', title: 'Delivery', chunks: 3),
            _source(
              's-2',
              type: 'MANUAL_QA',
              title: '',
              question: 'Return period?',
              answer: '14 days',
              status: 'FAILED',
              errorDetail: 'Embedding failed.',
            ),
          ],
        },
      );
      await _pumpTab(tester, server, section: AiSection.knowledge);

      expect(find.text('Delivery'), findsOneWidget);
      expect(find.text('3 parts'), findsOneWidget);
      expect(find.text('Return period?'), findsOneWidget);
      expect(find.text('Q&A'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.textContaining('Embedding failed.'), findsOneWidget);
      expect(
        server.requests
            .firstWhere((r) => r.path == '/knowledge-sources/')
            .queryParameters['knowledge_base'],
        'kb-1',
      );
    });

    testWidgets('empty state when the base has no sources', (tester) async {
      await _pumpTab(tester, _Server(), section: AiSection.knowledge);
      expect(find.byKey(const Key('ai-no-sources')), findsOneWidget);
    });

    testWidgets('adding Q&A posts it to the selected base and follows '
        'indexing until the server says READY', (tester) async {
      final server = _Server();
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('ai-add-qa')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the question.'), findsOneWidget);
      expect(find.text('Enter the answer.'), findsOneWidget);
      expect(server.writes, isEmpty);

      await tester.enterText(
        find.byKey(const Key('source-form-question')),
        'Return period?',
      );
      await tester.enterText(
        find.byKey(const Key('source-form-answer')),
        '14 days with a receipt.',
      );
      await tester.tap(find.byKey(const Key('source-form-save')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final post = server.writes.single;
      expect(post.path, '/knowledge-sources/');
      expect(post.data, {
        'knowledge_base_id': 'kb-1',
        'source_type': 'MANUAL_QA',
        'question': 'Return period?',
        'answer': '14 days with a receipt.',
        'title': '',
      });
      // Accepted is not ready: the row shows the server's PENDING.
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);

      server.sources['kb-1'] = [
        {...server.sources['kb-1']!.single, 'status': 'INDEXING'},
      ];
      await tester.pump(KnowledgeSourcesController.pollInterval);
      await tester.pump();
      expect(find.text('Indexing…'), findsOneWidget);

      server.sources['kb-1'] = [
        {
          ...server.sources['kb-1']!.single,
          'status': 'READY',
          'chunk_count': 1,
        },
      ];
      await tester.pump(KnowledgeSourcesController.pollInterval);
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('1 part'), findsOneWidget);

      // Settled: no more polling.
      final reads = server.requests
          .where((r) => r.path == '/knowledge-sources/')
          .length;
      await tester.pump(KnowledgeSourcesController.pollInterval * 3);
      expect(
        server.requests.where((r) => r.path == '/knowledge-sources/').length,
        reads,
      );
    });

    testWidgets('adding text sends title and body', (tester) async {
      final server = _Server();
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('ai-add-text')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('source-form-title')),
        'Shipping',
      );
      await tester.enterText(
        find.byKey(const Key('source-form-body')),
        'Cairo in 1–2 days.',
      );
      await tester.tap(find.byKey(const Key('source-form-save')));
      await _flush(tester);

      expect(server.writes.single.data, {
        'knowledge_base_id': 'kb-1',
        'source_type': 'PLAIN_TEXT',
        'title': 'Shipping',
        'body': 'Cairo in 1–2 days.',
      });
    });

    testWidgets(
      'a server validation error stays in the form beside its field',
      (tester) async {
        final server = _Server();
        final client = server.client();
        client.raw.httpClientAdapter = _StubAdapter((o) {
          if (o.method == 'POST' && o.path == '/knowledge-sources/') {
            return _json({
              'error': {
                'code': 'validation_error',
                'message': 'The submitted data was invalid.',
                'details': {
                  'title': [
                    'Ensure this field has no more than 200 characters.',
                  ],
                },
              },
            }, 400);
          }
          return server._handle(o);
        });
        await tester.binding.setSurfaceSize(const Size(800, 5000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();
        await _open(tester, AiSection.knowledge);

        await tester.tap(find.byKey(const Key('ai-add-text')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('source-form-title')), 'T');
        await tester.enterText(find.byKey(const Key('source-form-body')), 'B');
        await tester.tap(find.byKey(const Key('source-form-save')));
        await tester.pumpAndSettle();

        expect(
          find.text('Ensure this field has no more than 200 characters.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('source-form-save')), findsOneWidget);
      },
    );

    testWidgets('edit PATCHes only the content fields', (tester) async {
      final server = _Server(
        sources: {
          'kb-1': [_source('s-1')],
        },
      );
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('source-s-1-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('source-form-body')),
        'Updated body',
      );
      await tester.tap(find.byKey(const Key('source-form-save')));
      await _flush(tester);

      final patch = server.writes.single;
      expect(patch.method, 'PATCH');
      expect(patch.path, '/knowledge-sources/s-1/');
      expect(patch.data, {'title': 'Delivery', 'body': 'Updated body'});
    });

    testWidgets('re-index POSTs reindex/ and shows the queued status', (
      tester,
    ) async {
      final server = _Server(
        sources: {
          'kb-1': [_source('s-1')],
        },
      );
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('source-s-1-reindex')));
      await _flush(tester);

      expect(server.writes.single.method, 'POST');
      expect(server.writes.single.path, '/knowledge-sources/s-1/reindex/');
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
    });

    testWidgets('delete asks first, then DELETEs and re-reads', (tester) async {
      final server = _Server(
        sources: {
          'kb-1': [_source('s-1')],
        },
      );
      await _pumpTab(tester, server, section: AiSection.knowledge);

      await tester.tap(find.byKey(const Key('source-s-1-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-confirm-delete')));
      await tester.pumpAndSettle();

      expect(server.writes.single.method, 'DELETE');
      expect(server.writes.single.path, '/knowledge-sources/s-1/');
      expect(find.byKey(const Key('source-s-1')), findsNothing);
      expect(find.byKey(const Key('ai-no-sources')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  group('Agent Assist', () {
    Map<String, Object?> setting(
      int id, {
      String name = 'WhatsApp Main',
      String provider = 'WHATSAPP',
      String mode = 'OFF',
      bool supported = true,
    }) => {
      'connection_id': id,
      'connection_name': name,
      'provider': provider,
      'status': 'ACTIVE',
      'mode': mode,
      'assist_supported': supported,
    };

    Map<String, Object?> readiness(
      int id, {
      bool suggest = true,
      bool auto = false,
      List<String> blocking = const [],
      List<String> warnings = const [],
    }) => {
      'connection_id': id,
      'provider': 'WHATSAPP',
      'state': suggest ? 'READY_FOR_SUGGEST' : 'NOT_READY',
      'suggest_allowed': suggest,
      'auto_allowed': auto,
      'blocking': blocking,
      'warnings': warnings,
      'detail': {'sources_ready': 5, 'embedded_chunks': 7},
    };

    test('offers only the modes readiness allows, plus the current one', () {
      AiAgentSetting row(String mode, {bool s = false, bool a = false}) =>
          AiAgentSetting.fromJson(setting(1, mode: mode)).withReadiness(
            AiReadiness.fromJson(readiness(1, suggest: s, auto: a)),
          );

      expect(row('OFF').offeredModes, ['OFF']);
      expect(row('OFF', s: true).offeredModes, ['OFF', 'SUGGEST']);
      expect(row('OFF', s: true, a: true).offeredModes, [
        'OFF',
        'SUGGEST',
        'AUTO',
      ]);
      expect(row('AUTO').offeredModes, ['OFF', 'AUTO']);
      expect(
        AiAgentSetting.fromJson(setting(1)).offeredModes,
        ['OFF'],
        reason: 'no readiness known: nothing beyond OFF is offered',
      );
    });

    testWidgets('joins readiness, explains blocks, and PUTs a mode', (
      tester,
    ) async {
      final server = _Server(
        agentSettings: [
          setting(12),
          setting(13, name: 'Page', provider: 'FACEBOOK', supported: false),
        ],
        readiness: [
          readiness(12, warnings: ['INDEXING_INCOMPLETE']),
          readiness(13, suggest: false, blocking: ['UNSUPPORTED_CHANNEL']),
        ],
      );
      await _pumpTab(tester, server, section: AiSection.agent);

      expect(find.byKey(const Key('assist-13-unsupported')), findsOneWidget);
      expect(find.byKey(const Key('assist-12-AUTO')), findsNothing);
      expect(
        find.textContaining('Some sources are still being indexed'),
        findsOneWidget,
      );
      expect(
        find.text('5 source(s) indexed, 7 searchable extract(s)'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('assist-12-SUGGEST')));
      await tester.pumpAndSettle();

      final put = server.writes.single;
      expect(put.method, 'PUT');
      expect(put.path, '/ai/agent-settings/');
      expect(put.data, {'connection_id': 12, 'mode': 'SUGGEST'});
      final segmented = tester.widget<SegmentedButton<String>>(
        find.byKey(const Key('assist-12-modes')),
      );
      expect(segmented.selected, {'SUGGEST'});
    });

    testWidgets('AUTO needs confirmation before anything is sent', (
      tester,
    ) async {
      final server = _Server(
        agentSettings: [setting(12)],
        readiness: [readiness(12, auto: true)],
      );
      await _pumpTab(tester, server, section: AiSection.agent);

      await tester.tap(find.byKey(const Key('assist-12-AUTO')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-confirm-auto')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);

      await tester.tap(find.byKey(const Key('assist-12-AUTO')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-confirm-auto')));
      await tester.pumpAndSettle();
      expect(server.writes.single.data, {'connection_id': 12, 'mode': 'AUTO'});
    });

    testWidgets('a refused mode keeps the server state and says why', (
      tester,
    ) async {
      final server = _Server(
        agentSettings: [setting(12)],
        readiness: [readiness(12)],
      );
      final client = server.client();
      client.raw.httpClientAdapter = _StubAdapter((o) {
        if (o.method == 'PUT') {
          return _error(400, 'validation_error', 'Not cleared for the pilot.');
        }
        return server._handle(o);
      });
      await tester.binding.setSurfaceSize(const Size(800, 5000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();
      await _open(tester, AiSection.agent);

      await tester.tap(find.byKey(const Key('assist-12-SUGGEST')));
      await tester.pumpAndSettle();

      expect(find.text('Not cleared for the pilot.'), findsOneWidget);
      final segmented = tester.widget<SegmentedButton<String>>(
        find.byKey(const Key('assist-12-modes')),
      );
      expect(segmented.selected, {'OFF'});
    });
  });

  // ------------------------------------------------------------------------ //
  group('usage, conflicts', () {
    testWidgets('shows the 30-day usage numbers', (tester) async {
      await _pumpTab(tester, _Server(), section: AiSection.activity);
      expect(find.byKey(const Key('ai-section-usage')), findsOneWidget);
      expect(find.text('19'), findsWidgets);
      expect(find.text('13391'), findsOneWidget);
    });

    testWidgets('lists knowledge conflicts when there are any', (tester) async {
      await _pumpTab(
        tester,
        _Server(
          conflicts: [
            {
              'sources': ['Returns A', 'Returns B'],
              'reason': '14 days vs 30 days',
            },
          ],
        ),
        section: AiSection.knowledge,
      );
      expect(find.byKey(const Key('ai-conflicts')), findsOneWidget);
      expect(find.text('Returns A  ↔  Returns B'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------ //
  group('permissions', () {
    test('ai_knowledge_enabled is read from /auth/me/', () {
      final base = {
        'id': 1,
        'email': 'a@b.c',
        'full_name': 'A B',
        'permissions': ['ai_knowledge.manage'],
      };
      expect(Employee.fromJson(base).aiKnowledgeEnabled, isFalse);
      expect(
        Employee.fromJson({
          ...base,
          'ai_knowledge_enabled': true,
        }).aiKnowledgeEnabled,
        isTrue,
      );
    });

    for (final (label, employee) in [
      ('without ai_knowledge.manage', _employee(permissions: {})),
      ('outside the pilot', _employee(aiKnowledgeEnabled: false)),
    ]) {
      testWidgets('$label nothing is offered and nothing is fetched', (
        tester,
      ) async {
        final server = _Server();
        await _pumpTab(tester, server, employee: employee);

        expect(
          find.byKey(const Key('ai-knowledge-not-available')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('ai-new-knowledge-base')), findsNothing);
        expect(server.requests, isEmpty);
      });
    }

    testWidgets('a 404 from the server (outside the pilot) is not an error '
        'page', (tester) async {
      await _pumpTab(tester, _Server(basesStatus: 404));
      expect(
        find.byKey(const Key('ai-knowledge-not-available')),
        findsOneWidget,
      );
    });

    testWidgets('error codes map to their own words', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        aiReadinessReason(context, 'NO_PROVIDER'),
        'No AI provider is configured',
      );
      expect(aiReadinessReason(context, 'BRAND_NEW_CODE'), 'BRAND_NEW_CODE');
      expect(
        aiErrorMessage(
          context,
          ApiException(statusCode: 429, message: 'x', code: 'throttled'),
        ),
        contains('30 questions'),
      );
    });
  });

  // ------------------------------------------------------------------------ //
  group('Arabic', () {
    testWidgets('lays out right-to-left on a narrow phone without overflow', (
      tester,
    ) async {
      final server = _Server(
        bases: [_base('kb-1', name: 'سياسات المتجر', sources: 1, ready: 1)],
        sources: {
          'kb-1': [_source('s-1', title: 'التوصيل', body: 'التوصيل للقاهرة')],
        },
        agentSettings: [
          {
            'connection_id': 12,
            'connection_name': 'واتساب',
            'provider': 'WHATSAPP',
            'status': 'ACTIVE',
            'mode': 'OFF',
            'assist_supported': true,
          },
        ],
        readiness: [
          {
            'connection_id': 12,
            'provider': 'WHATSAPP',
            'state': 'READY_FOR_SUGGEST',
            'suggest_allowed': true,
            'auto_allowed': false,
            'blocking': <String>[],
            'warnings': ['NO_HANDOFF_ROUTE'],
            'detail': <String, Object>{},
          },
        ],
        playground: (_) =>
            _json({..._answered(), 'answer': 'يمكن الاسترجاع خلال 14 يومًا.'}),
      );
      await _pumpTab(
        tester,
        server,
        locale: const Locale('ar'),
        size: const Size(320, 6000),
        section: AiSection.knowledge,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('قواعد المعرفة'), findsOneWidget);
      expect(find.text('1 من 1 جاهز'), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('ai-knowledge-tab'))),
        ),
        TextDirection.rtl,
      );

      await _open(tester, AiSection.agent);
      expect(tester.takeException(), isNull);
      expect(find.text('مساعد الوكيل بالذكاء الاصطناعي'), findsOneWidget);

      await _open(tester, AiSection.playground);
      expect(tester.takeException(), isNull);
      expect(find.text('اختبر قاعدة المعرفة'), findsOneWidget);

      await _ask(tester, 'ما هي مدة الاسترجاع؟');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final answer = tester.widget<SelectableText>(
        find.byKey(const Key('playground-answer-text')),
      );
      expect(answer.textDirection, TextDirection.rtl);
    });

    testWidgets('English content inside the Arabic app runs left-to-right', (
      tester,
    ) async {
      await _pumpTab(
        tester,
        _Server(),
        locale: const Locale('ar'),
        size: const Size(320, 6000),
        section: AiSection.playground,
      );
      await _ask(tester, 'Return period?');
      await tester.pumpAndSettle();
      final answer = tester.widget<SelectableText>(
        find.byKey(const Key('playground-answer-text')),
      );
      expect(answer.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  });

  test('the knowledge-base list walks every page', () async {
    final pages = <int>[];
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((o) {
      final page = o.queryParameters['page'] as int;
      pages.add(page);
      return _json({
        'count': 2,
        'page': page,
        'page_size': 100,
        'total_pages': 2,
        'next': page == 1 ? 'https://x/api/knowledge-bases/?page=2' : null,
        'previous': null,
        'results': [_base('kb-$page')],
      });
    });
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final bases = await container
        .read(aiKnowledgeRepositoryProvider)
        .knowledgeBases();
    expect(bases.map((b) => b.id), ['kb-1', 'kb-2']);
    expect(pages, [1, 2]);
  });
}
