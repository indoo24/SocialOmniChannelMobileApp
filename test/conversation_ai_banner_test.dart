/// The conversation AI banner — `ConversationDetail.ai_state` rendered above
/// the thread, this conversation's automatic-reply policy
/// (`PATCH /conversations/{id}/ai-policy/`), and resuming the AI
/// (`POST /conversations/{id}/ai-resume/`, with `{"answer_latest": true}`
/// for resume-and-answer).
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
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

const _id = 42;

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) => handler(options);

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

Map<String, dynamic> _aiState({
  bool replied = true,
  bool paused = false,
  String reason = '',
  bool canAnswerLatest = false,
  String answerLatestReason = '',
  String resumeBehaviour = 'ASK',
  String policy = 'KNOWLEDGE_ONLY',
  String override = 'INHERIT',
  String sourceLabel = '',
}) => {
  'has_replied': replied,
  'last_replied_at': '2026-11-07T23:39:00Z',
  'is_paused': paused,
  'paused_at': paused ? '2026-11-07T23:40:00Z' : null,
  'paused_reason': reason,
  'can_answer_latest': canAnswerLatest,
  'answer_latest_reason': answerLatestReason,
  'answer_latest_message_id': canAnswerLatest ? 501 : null,
  'resume_behaviour': resumeBehaviour,
  'auto_reply_policy': policy,
  'auto_reply_policy_source': override == 'INHERIT'
      ? 'ORGANIZATION'
      : 'CONVERSATION',
  'auto_reply_policy_source_label': sourceLabel,
  'conversation_override': override,
  'has_conversation_override': override != 'INHERIT',
};

Map<String, dynamic> _paused({bool canAnswerLatest = true}) => _aiState(
  paused: true,
  reason: 'HUMAN_TAKEOVER',
  canAnswerLatest: canAnswerLatest,
);

class _Server {
  _Server({Map<String, dynamic>? ai}) : ai = {_id: ai ?? _aiState()};

  /// `ai_state` per conversation; a missing entry sends none.
  final Map<int, Map<String, dynamic>?> ai;
  final messages = <Map<String, dynamic>>[
    {
      'id': 500,
      'direction': 'INBOUND',
      'sender_type': 'CUSTOMER',
      'text': 'السلام عليكم',
      'delivery_status': 'DELIVERED',
      'sent_at': '2026-11-07T23:40:00Z',
    },
  ];

  final requests = <RequestOptions>[];
  Iterable<RequestOptions> get writes =>
      requests.where((r) => r.method != 'GET');
  int get detailReads => requests
      .where((r) => r.method == 'GET' && r.path == '/conversations/$_id/')
      .length;

  /// Holds AI actions until completed.
  Completer<void>? hold;

  /// Answers AI actions with this status and code instead.
  int? failStatus;
  String failCode = 'error';

  Map<String, dynamic> conversation(int id) => {
    'id': id,
    'customer': {'id': 7, 'display_name': 'Indoo'},
    'provider': 'WHATSAPP',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': 0,
    'message_count': messages.length,
    'ai_assist_mode': 'AUTO',
    if (ai.containsKey(id)) 'ai_state': ai[id],
  };

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Future<ResponseBody> _handle(RequestOptions o) async {
    requests.add(o);
    final path = o.path;
    final action = RegExp(
      r'^/conversations/(\d+)/(ai-policy|ai-resume)/$',
    ).firstMatch(path);
    if (action != null) {
      final id = int.parse(action.group(1)!);
      if (hold case final h?) await h.future;
      if (failStatus case final status?) {
        return _json({
          'error': {'code': failCode, 'message': 'Refused: $failCode'},
        }, status);
      }
      final state = Map<String, dynamic>.from(ai[id]!);
      if (action.group(2) == 'ai-policy') {
        final policy = (o.data as Map)['policy'] as String;
        state
          ..['conversation_override'] = policy
          ..['has_conversation_override'] = policy != 'INHERIT'
          ..['auto_reply_policy'] = policy == 'INHERIT'
              ? 'KNOWLEDGE_ONLY'
              : policy;
      } else {
        state
          ..['is_paused'] = false
          ..['paused_reason'] = ''
          ..['can_answer_latest'] = false;
        if ((o.data as Map)['answer_latest'] == true) {
          state['has_replied'] = true;
          messages.add({
            'id': 502,
            'direction': 'OUTBOUND',
            'sender_type': 'AI',
            'text': 'وعليكم السلام، كيف أساعدك؟',
            'delivery_status': 'SENT',
            'sent_at': '2026-11-07T23:42:00Z',
          });
        }
      }
      ai[id] = state;
      return _json(conversation(id));
    }
    final detail = RegExp(r'^/conversations/(\d+)/$').firstMatch(path);
    if (detail != null) {
      return _json(conversation(int.parse(detail.group(1)!)));
    }
    if (path.contains('/messages/')) {
      return _json({
        'count': messages.length,
        'next': null,
        'results': messages,
      });
    }
    if (path.contains('/notes/')) return _json([]);
    return _json({});
  }
}

Employee _employee({bool manager = true}) => Employee(
  id: 1,
  email: 'me@acme.test',
  fullName: 'Yousef Kandeel',
  initials: 'YK',
  role: manager ? 'ADMIN' : 'AGENT',
  roleDisplay: manager ? 'Admin' : 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, if (manager) Perm.aiKnowledgeManage},
  visibilityScope: 'ALL',
  aiKnowledgeEnabled: true,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  Employee? me,
  Locale locale = const Locale('en'),
  Size size = const Size(430, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(me ?? _employee()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: _id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ConversationScreen)),
  );
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).textSpan?.toPlainText() ??
    tester.widget<Text>(find.byKey(key)).data!;

final _active = find.byKey(const Key('conversationAiBanner'));
final _pausedBanner = find.byKey(const Key('conversationAiBannerPaused'));
final _resume = find.byKey(const Key('aiBannerResume'));
final _resumeAndAnswer = find.byKey(const Key('aiBannerResumeAndAnswer'));
final _dropdown = find.byKey(const Key('aiBannerPolicyDropdown'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ai_state', () {
    test('parses the schema, and a conversation without one has none', () {
      final convo = Conversation.fromJson(
        _Server(ai: _paused()).conversation(_id),
      );
      final ai = convo.aiState!;
      expect(ai.isPaused, isTrue);
      expect(ai.isHumanTakeover, isTrue);
      expect(ai.canAnswerLatest, isTrue);
      expect(ai.answerLatestMessageId, 501);
      expect(ai.autoReplyPolicy, 'KNOWLEDGE_ONLY');
      expect(ai.conversationOverride, 'INHERIT');
      expect(ai.hasConversationOverride, isFalse);
      expect(ai.offersAnswerLatest, isTrue);
      expect(convo.aiAssistMode, 'AUTO');

      expect(
        Conversation.fromJson(
          {..._Server().conversation(_id)}..remove('ai_state'),
        ).aiState,
        isNull,
      );
      // A patch (read state, a tick) does not lose it.
      expect(convo.copyWith(unreadCount: 0).aiState, same(ai));
    });

    test('a channel that waits for the next message offers no answer', () {
      final ai = AiConversationState.fromJson(
        _aiState(paused: true, canAnswerLatest: true, resumeBehaviour: 'WAIT'),
      )!;
      expect(ai.offersAnswerLatest, isFalse);
    });
  });

  group('active', () {
    testWidgets('shows that the AI answered and the inherited policy', (
      tester,
    ) async {
      await _pump(tester, _Server());

      expect(_active, findsOneWidget);
      expect(find.text('AI answered'), findsOneWidget);
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        'AI auto: Knowledge only — inherited from the organization default',
      );
      expect(find.text('Use default (Knowledge only)'), findsOneWidget);
      // It sits above the thread, not inside it.
      expect(
        tester.getBottomLeft(_active).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(Scrollable).first).dy),
      );
    });

    testWidgets("the server's own words for the source win", (tester) async {
      await _pump(
        tester,
        _Server(ai: _aiState(sourceLabel: 'the channel setting')),
      );
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        'AI auto: Knowledge only — inherited from the channel setting',
      );
    });

    testWidgets('an override says so, and "Use default" names no value', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(
          ai: _aiState(policy: 'ALWAYS_REPLY', override: 'ALWAYS_REPLY'),
        ),
      );
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        'AI auto: Always reply — set for this conversation',
      );
      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Use default'), findsWidgets);
    });

    testWidgets('nothing until the AI has replied or paused', (tester) async {
      await _pump(tester, _Server(ai: _aiState(replied: false)));
      expect(_active, findsNothing);
      expect(_pausedBanner, findsNothing);
    });

    testWidgets('nothing for a conversation without AI state', (tester) async {
      final server = _Server()..ai.remove(_id);
      await _pump(tester, server);
      expect(_active, findsNothing);
      expect(_pausedBanner, findsNothing);
    });
  });

  group('changing the policy', () {
    testWidgets('changes this conversation only, once the server confirms', (
      tester,
    ) async {
      final server = _Server()..hold = Completer<void>();
      await _pump(tester, server);

      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      // Through Dio's interceptors, to the held server.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Sent, not yet shown.
      expect(server.writes.single.path, '/conversations/$_id/ai-policy/');
      expect(server.writes.single.method, 'PATCH');
      expect(server.writes.single.data, {'policy': 'OFF'});
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        contains('inherited from'),
      );

      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        'AI auto: Off — set for this conversation',
      );
      expect(
        find.text('Automatic replies updated for this conversation.'),
        findsOneWidget,
      );
      // Nothing above the conversation was touched.
      expect(
        server.writes.where(
          (w) => w.path.startsWith('/ai/') || w.path.contains('agent-settings'),
        ),
        isEmpty,
      );
    });

    testWidgets('choosing default again clears the override', (tester) async {
      final server = _Server(
        ai: _aiState(policy: 'OFF', override: 'OFF'),
      );
      await _pump(tester, server);
      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use default').last);
      await tester.pumpAndSettle();
      expect(server.writes.single.data, {'policy': 'INHERIT'});
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        contains('inherited from'),
      );
    });

    testWidgets('a refusal says why and changes nothing', (tester) async {
      final server = _Server()
        ..failStatus = 403
        ..failCode = 'permission_denied';
      await _pump(tester, server);
      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always reply').last);
      await tester.pumpAndSettle();

      expect(
        find.text("You don't have permission to manage AI knowledge."),
        findsOneWidget,
      );
      expect(
        _text(tester, const Key('aiBannerPolicy')),
        contains('Knowledge only — inherited'),
      );
    });
  });

  group('paused', () {
    testWidgets('says why, and offers both resumes to a manager', (
      tester,
    ) async {
      await _pump(tester, _Server(ai: _paused()));
      expect(_pausedBanner, findsOneWidget);
      expect(find.text('AI is paused for this conversation'), findsOneWidget);
      expect(
        _text(tester, const Key('aiBannerPauseReason')),
        'AI paused — a colleague took over',
      );
      expect(_resume, findsOneWidget);
      expect(_resumeAndAnswer, findsOneWidget);
      expect(_dropdown, findsOneWidget);
    });

    testWidgets('Resume AI resumes, and the banner follows the server', (
      tester,
    ) async {
      final server = _Server(ai: _paused());
      await _pump(tester, server);

      await tester.tap(_resume);
      await tester.pumpAndSettle();
      expect(server.writes.single.path, '/conversations/$_id/ai-resume/');
      expect(server.writes.single.data, isEmpty);
      expect(_pausedBanner, findsNothing);
      expect(_active, findsOneWidget);
      expect(
        find.text('The AI may answer this conversation again'),
        findsOneWidget,
      );
    });

    testWidgets('Resume & answer asks the server to answer, once, and the '
        'reply appears', (tester) async {
      final server = _Server(ai: _paused())..hold = Completer<void>();
      await _pump(tester, server);

      await tester.tap(_resumeAndAnswer);
      await tester.pump();
      // Busy: both actions are off until the server answers.
      for (final button in [_resume, _resumeAndAnswer]) {
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.descendant(
                  of: button,
                  matching: find.byWidgetPredicate(
                    (w) => w is ButtonStyleButton,
                  ),
                ),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.tap(_resumeAndAnswer, warnIfMissed: false);
      await tester.pump();

      server.hold!.complete();
      await tester.pumpAndSettle();
      final resumes = server.writes.where((w) => w.path.endsWith('ai-resume/'));
      expect(resumes, hasLength(1));
      expect(resumes.single.data, {'answer_latest': true});
      expect(find.text('وعليكم السلام، كيف أساعدك؟'), findsOneWidget);
      expect(_active, findsOneWidget);
    });

    testWidgets('no answer on offer when the server says it may not', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(
          ai: _aiState(
            paused: true,
            reason: 'NOT_IN_KB',
            answerLatestReason: 'human_already_answered',
          ),
        ),
      );
      expect(_resume, findsOneWidget);
      expect(_resumeAndAnswer, findsNothing);
      expect(
        _text(tester, const Key('aiBannerPauseReason')),
        'AI paused — the knowledge base could not answer',
      );
      expect(
        find.byKey(const Key('aiBannerAnswerLatestReason')),
        findsOneWidget,
      );
    });

    testWidgets('no answer on offer when the channel waits for the next '
        'message', (tester) async {
      await _pump(
        tester,
        _Server(
          ai: _aiState(
            paused: true,
            reason: 'HUMAN_TAKEOVER',
            canAnswerLatest: true,
            resumeBehaviour: 'WAIT',
          ),
        ),
      );
      expect(_resume, findsOneWidget);
      expect(_resumeAndAnswer, findsNothing);
    });

    testWidgets('without ai_knowledge.manage: the state, no actions', (
      tester,
    ) async {
      await _pump(
        tester,
        _Server(ai: _paused()),
        me: _employee(manager: false),
      );
      expect(_pausedBanner, findsOneWidget);
      expect(find.byKey(const Key('aiBannerPauseReason')), findsOneWidget);
      expect(find.byKey(const Key('aiBannerPolicy')), findsOneWidget);
      expect(_resume, findsNothing);
      expect(_resumeAndAnswer, findsNothing);
      expect(_dropdown, findsNothing);
    });

    for (final (status, code, message) in [
      (
        403,
        'permission_denied',
        "You don't have permission to manage AI knowledge.",
      ),
      (404, 'not_found', "AI isn't available for this conversation."),
      (409, 'conflict', 'Refused: conflict'),
    ]) {
      testWidgets('HTTP $status: says so and keeps the paused state', (
        tester,
      ) async {
        final server = _Server(ai: _paused())
          ..failStatus = status
          ..failCode = code;
        await _pump(tester, server);
        final readsBefore = server.detailReads;

        await tester.tap(_resume);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(_pausedBanner, findsOneWidget);
        // A conflict means the screen is out of date: it is read again.
        expect(
          server.detailReads,
          status == 409 ? readsBefore + 1 : readsBefore,
        );
      });
    }
  });

  group('state', () {
    test('one action at a time, per conversation', () async {
      final server = _Server(ai: _paused())..hold = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
      );
      addTearDown(container.dispose);
      final provider = conversationControllerProvider(_id);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      final controller = container.read(provider.notifier);

      final first = controller.resumeAi(answerLatest: true);
      final second = controller.resumeAi(answerLatest: true);
      final third = controller.setAiPolicy('OFF');
      expect(controller.isAiActionPending, isTrue);
      server.hold!.complete();
      await Future.wait([first, second, third]);

      expect(server.writes, hasLength(1));
      expect(controller.isAiActionPending, isFalse);
    });

    test("one conversation's answer never lands on another", () async {
      final server = _Server(ai: _paused());
      server.ai[43] = _aiState();
      server.hold = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
      );
      addTearDown(container.dispose);
      final first = conversationControllerProvider(_id);
      final second = conversationControllerProvider(43);
      container.listen(first, (_, _) {});
      container.listen(second, (_, _) {});
      await container.read(first.future);
      await container.read(second.future);

      // Resume on 42, then "switch" to 43 while it is in flight.
      final resume = container.read(first.notifier).resumeAi();
      await container.read(second.notifier).refreshFromServer();
      server.hold!.complete();
      await resume;

      expect(
        container.read(first).value!.conversation.aiState!.isPaused,
        isFalse,
      );
      final other = container.read(second).value!.conversation;
      expect(other.id, 43);
      expect(other.aiState!.isPaused, isFalse);
      expect(other.aiState!.hasReplied, isTrue);
      expect(server.writes.single.path, '/conversations/$_id/ai-resume/');
    });

    test('a failed action throws and leaves the state as it was', () async {
      final server = _Server(ai: _paused())..failStatus = 500;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
      );
      addTearDown(container.dispose);
      final provider = conversationControllerProvider(_id);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);

      await expectLater(
        container.read(provider.notifier).resumeAi(),
        throwsA(isA<ApiException>()),
      );
      expect(
        container.read(provider).value!.conversation.aiState!.isPaused,
        isTrue,
      );
    });

    testWidgets('a refresh (as a realtime event triggers) updates the banner', (
      tester,
    ) async {
      final server = _Server();
      final container = await _pump(tester, server);
      expect(_active, findsOneWidget);

      server.ai[_id] = _paused();
      // Not awaited: the refresh runs on the test clock, which only moves
      // while pumping.
      unawaited(
        container
            .read(conversationControllerProvider(_id).notifier)
            .refreshFromServer(),
      );
      await tester.pumpAndSettle();
      expect(_pausedBanner, findsOneWidget);
    });
  });

  testWidgets('Arabic, on a narrow phone: right to left, nothing overflows', (
    tester,
  ) async {
    await _pump(
      tester,
      _Server(ai: _paused()),
      locale: const Locale('ar'),
      size: const Size(320, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('الذكاء الاصطناعي متوقف في هذه المحادثة'), findsOneWidget);
    expect(find.text('استئناف الذكاء الاصطناعي'), findsOneWidget);
    expect(find.text('استئناف والرد على آخر رسالة'), findsOneWidget);
    expect(
      _text(tester, const Key('aiBannerPauseReason')),
      'الذكاء الاصطناعي متوقف — تولى زميل المحادثة',
    );
    expect(
      _text(tester, const Key('aiBannerPolicy')),
      'الرد التلقائي: من قاعدة المعرفة فقط — موروث من الإعداد الافتراضي للمؤسسة',
    );
    expect(
      find.text('استخدام الافتراضي (من قاعدة المعرفة فقط)'),
      findsOneWidget,
    );
    expect(Directionality.of(tester.element(_pausedBanner)), TextDirection.rtl);
  });
}
