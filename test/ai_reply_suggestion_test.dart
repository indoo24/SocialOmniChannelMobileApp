/// AI reply suggestion in the conversation composer —
/// `POST /api/conversations/{id}/ai-suggestion/`, the outcome report
/// (`POST /api/ai/suggestions/{id}/outcome/`) and `Reply.suggestion_id`.
///
/// The one rule under every test here: a suggestion is never sent. It goes
/// into the reply box, and only the employee's Send sends anything.
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
import 'package:scenario_mobile/core/models/ai_suggestion.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/ai_suggestion_bar.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

const _draft = 'Hello! The blue bag is in stock and ships within 2 days.';
const _arDraft = 'أهلًا بك! الحقيبة الزرقاء متوفرة وتُشحن خلال يومين.';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
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

Map<String, dynamic> _suggestion({
  String status = 'ANSWERED',
  String draft = _draft,
  String id = '0b8d7f6e-1111-4c2a-9d3e-000000000001',
  int? through = 500,
  String errorCode = '',
  String errorDetail = '',
  String conflictReason = '',
  List<Map<String, dynamic>> citations = const [],
}) => {
  'suggestion_id': id,
  'status': status,
  'draft': draft,
  'citations': citations,
  'retrieved': <Object>[],
  'through_message_id': through,
  'attempt': 1,
  'context_messages': 4,
  'model': 'model',
  'provider': 'provider',
  'policy_version': '1',
  'duration_ms': 900,
  'retrieval_ms': 40,
  'input_tokens': 10,
  'output_tokens': 10,
  'cached_tokens': 0,
  'total_tokens': 20,
  'error_code': errorCode,
  'error_detail': errorDetail,
  'conflict_reason': conflictReason,
};

class _Server {
  _Server({this.mode = 'SUGGEST'});

  /// `ai_assist_mode` the detail answers with.
  String mode;

  final requests = <RequestOptions>[];

  /// Holds suggestion requests until completed.
  Completer<void>? hold;

  /// What the suggestion endpoint answers; the default is a draft.
  ResponseBody Function(RequestOptions options) answer = (_) =>
      _json(_suggestion());

  final messages = <int, List<Map<String, dynamic>>>{};

  List<Map<String, dynamic>> _thread(int id) => messages.putIfAbsent(
    id,
    () => [
      {
        'id': 500,
        'direction': 'INBOUND',
        'sender_type': 'CUSTOMER',
        'text': 'Is the blue bag in stock?',
        'delivery_status': 'DELIVERED',
        'sent_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      },
    ],
  );

  Map<String, dynamic> conversation(int id) => {
    'id': id,
    'customer': {'id': 7, 'display_name': 'Indoo'},
    'provider': 'INSTAGRAM',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': 0,
    'message_count': _thread(id).length,
    'ai_assist_mode': mode,
  };

  List<RequestOptions> suggestionRequests([int? id]) => requests
      .where(
        (r) =>
            r.method == 'POST' &&
            r.path.endsWith('/ai-suggestion/') &&
            (id == null || r.path == '/conversations/$id/ai-suggestion/'),
      )
      .toList();

  List<RequestOptions> get replies => requests
      .where((r) => r.method == 'POST' && r.path.endsWith('/reply/'))
      .toList();

  List<String> get outcomes => [
    for (final r in requests)
      if (r.method == 'POST' && r.path.startsWith('/ai/suggestions/'))
        (r.data as Map)['outcome'] as String,
  ];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _Adapter(_handle);
    return client;
  }

  Future<ResponseBody> _handle(RequestOptions o) async {
    requests.add(o);
    final path = o.path;
    if (o.method == 'POST' && path.endsWith('/ai-suggestion/')) {
      if (hold case final h?) await h.future;
      return answer(o);
    }
    if (o.method == 'POST' && path.startsWith('/ai/suggestions/')) {
      return _json({'outcome': (o.data as Map)['outcome']});
    }
    final reply = RegExp(r'^/conversations/(\d+)/reply/$').firstMatch(path);
    if (o.method == 'POST' && reply != null) {
      final thread = _thread(int.parse(reply.group(1)!));
      final sent = {
        'id': 900 + thread.length,
        'direction': 'OUTBOUND',
        'sender_type': 'AGENT',
        'sender_name': 'Sam Agent',
        'text': (o.data as Map)['text'],
        'delivery_status': 'SENT',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      };
      thread.add(sent);
      return _json(sent, 201);
    }
    final detail = RegExp(r'^/conversations/(\d+)/$').firstMatch(path);
    if (detail != null) {
      return _json(conversation(int.parse(detail.group(1)!)));
    }
    final list = RegExp(r'^/conversations/(\d+)/messages/').firstMatch(path);
    if (list != null) {
      final thread = _thread(int.parse(list.group(1)!));
      return _json({'count': thread.length, 'next': null, 'results': thread});
    }
    if (path.contains('/notes/')) return _json(<Object>[]);
    return _json(<String, dynamic>{});
  }
}

Employee _agent() => Employee(
  id: 1,
  email: 'sam@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply, Perm.conversationNote},
  visibilityScope: 'ALL',
  aiKnowledgeEnabled: true,
);

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  int conversationId = 42,
  Locale locale = const Locale('en'),
  Size size = const Size(430, 900),
  ApiClient? client,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client ?? server.client()),
        currentEmployeeProvider.overrideWithValue(_agent()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationScreen(
          key: ValueKey('conversation_$conversationId'),
          conversationId: conversationId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _button = find.byKey(const Key('aiSuggestionButton'));
final _input = find.byKey(const ValueKey('composer_reply_input'));
final _send = find.byIcon(Icons.send_rounded);

String _composerText(WidgetTester tester, [Finder? within]) => tester
    .widget<TextField>(
      within == null ? _input : find.descendant(of: within, matching: _input),
    )
    .controller!
    .text;

TextField _field(WidgetTester tester) => tester.widget<TextField>(_input);

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _button, matching: find.byType(Text)))
    .data!;

Future<void> _tapSuggest(WidgetTester tester) async {
  await tester.tap(_button);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Availability', () {
    for (final mode in ['OFF', 'AUTO', '']) {
      testWidgets('not offered when the channel is "$mode" — the server would '
          'answer 404', (tester) async {
        final server = _Server(mode: mode);
        await _pump(tester, server);
        expect(_button, findsNothing);
      });
    }

    testWidgets('offered when the channel is in SUGGEST mode', (tester) async {
      await _pump(tester, _Server());
      expect(_button, findsOneWidget);
      expect(_buttonLabel(tester), 'AI Suggest');
    });

    testWidgets('a 404 says it is unavailable, and once dismissed the button '
        'is no longer offered', (tester) async {
      final server = _Server()
        ..answer = (_) => _json({
          'error': {'code': 'not_found', 'message': 'Not found.'},
        }, 404);
      await _pump(tester, server);
      await _tapSuggest(tester);

      expect(
        find.text("AI suggestions aren't available for this conversation."),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('aiSuggestionDismiss')));
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
    });
  });

  group('Generating', () {
    testWidgets('loading shows progress and blocks repeated taps; the draft '
        'lands in the reply box, editable, and nothing is sent', (
      tester,
    ) async {
      final server = _Server()..hold = Completer<void>();
      await _pump(tester, server);

      await tester.tap(_button);
      await tester.pump();
      expect(find.byKey(const Key('aiSuggestionLoading')), findsOneWidget);
      expect(_buttonLabel(tester), 'Generating suggestion…');
      expect(tester.widget<OutlinedButton>(_button).onPressed, isNull);
      // Hammering it changes nothing.
      for (var i = 0; i < 4; i++) {
        await tester.tap(_button, warnIfMissed: false);
        await tester.pump();
      }
      // The rest of the conversation stays usable meanwhile.
      await tester.enterText(_input, 'typing while it thinks');
      await tester.enterText(_input, '');

      server.hold!.complete();
      await tester.pumpAndSettle();

      expect(server.suggestionRequests(), hasLength(1));
      expect(server.suggestionRequests().single.data, {'regenerate': false});
      expect(_composerText(tester), _draft);
      final selection = _field(tester).controller!.selection;
      expect(selection.isCollapsed, isTrue);
      expect(selection.baseOffset, _draft.length);
      expect(_field(tester).focusNode!.hasFocus, isTrue);
      expect(find.byKey(const Key('aiSuggestionNotSentHint')), findsOneWidget);
      expect(server.outcomes, ['USED']);
      // Not sent.
      expect(server.replies, isEmpty);
      expect(find.text(_draft), findsOneWidget); // only in the box
    });

    testWidgets('the edited draft is sent only on Send, with its '
        'suggestion_id', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _tapSuggest(tester);

      await tester.enterText(_input, '$_draft See you soon.');
      await tester.pump();
      expect(server.replies, isEmpty);

      await tester.tap(_send);
      await tester.pumpAndSettle();

      expect(server.replies, hasLength(1));
      final body = server.replies.single.data as Map;
      expect(body['text'], '$_draft See you soon.');
      expect(body['suggestion_id'], '0b8d7f6e-1111-4c2a-9d3e-000000000001');
      expect(_composerText(tester), isEmpty);
      // Spent: the strip is back to its button.
      expect(_buttonLabel(tester), 'AI Suggest');
    });

    testWidgets('a reply typed after the draft was cleared is not sent as the '
        'suggestion', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _tapSuggest(tester);

      await tester.enterText(_input, '');
      await tester.pump();
      await tester.enterText(_input, 'My own words');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();

      final body = server.replies.single.data as Map;
      expect(body['text'], 'My own words');
      expect(body.containsKey('suggestion_id'), isFalse);
    });

    testWidgets('regenerating an unedited draft replaces it without asking, '
        'and says so to the server', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _tapSuggest(tester);
      expect(_buttonLabel(tester), 'Regenerate');

      server.answer = (_) => _json(
        _suggestion(
          draft: 'A second take.',
          id: '0b8d7f6e-1111-4c2a-9d3e-000000000002',
        ),
      );
      await _tapSuggest(tester);

      expect(find.text('Replace what you have written?'), findsNothing);
      expect(_composerText(tester), 'A second take.');
      expect(server.suggestionRequests().last.data, {'regenerate': true});
    });

    testWidgets('a draft written against an older message says it is stale', (
      tester,
    ) async {
      final server = _Server()
        ..answer = (_) => _json(_suggestion(through: 499));
      await _pump(tester, server);
      await _tapSuggest(tester);
      expect(find.byKey(const Key('aiSuggestionStale')), findsOneWidget);
    });
  });

  group('An existing draft', () {
    testWidgets('is never overwritten silently: Keep mine leaves it exactly '
        'as it was', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await tester.enterText(_input, 'My half-written reply');
      await tester.pump();

      await _tapSuggest(tester);
      expect(find.text('Replace what you have written?'), findsOneWidget);
      // The suggestion is shown, so the choice is informed.
      expect(find.byKey(const Key('aiSuggestionPreview')), findsOneWidget);

      await tester.tap(find.byKey(const Key('aiSuggestionKeepMine')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'My half-written reply');
      expect(server.outcomes, ['DISCARDED']);
      expect(server.replies, isEmpty);
    });

    testWidgets('dismissing the question also keeps it', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await tester.enterText(_input, 'Mine');
      await tester.pump();
      await _tapSuggest(tester);

      await tester.tapAt(const Offset(5, 5)); // outside the dialog
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'Mine');
    });

    testWidgets('Replace swaps it for the draft', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await tester.enterText(_input, 'Mine');
      await tester.pump();
      await _tapSuggest(tester);
      await tester.tap(find.byKey(const Key('aiSuggestionReplace')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), _draft);
      expect(server.outcomes, ['USED']);
    });

    testWidgets('Add below keeps it and puts the draft after it', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server);
      await tester.enterText(_input, 'Hi Indoo,');
      await tester.pump();
      await _tapSuggest(tester);
      await tester.tap(find.byKey(const Key('aiSuggestionAddBelow')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'Hi Indoo,\n\n$_draft');
    });

    testWidgets('an edited draft is asked about before a regenerate replaces '
        'it', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _tapSuggest(tester);
      await tester.enterText(_input, '$_draft Edited.');
      await tester.pump();

      await _tapSuggest(tester);
      expect(find.text('Replace what you have written?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('aiSuggestionKeepMine')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), '$_draft Edited.');
    });
  });

  group('No draft', () {
    testWidgets('an empty draft is not placed, and the text stays', (
      tester,
    ) async {
      final server = _Server()..answer = (_) => _json(_suggestion(draft: '  '));
      await _pump(tester, server);
      await tester.enterText(_input, 'Mine');
      await tester.pump();
      await _tapSuggest(tester);

      expect(find.text('Replace what you have written?'), findsNothing);
      expect(
        find.text(
          "The AI didn't return a usable reply. Your text is unchanged.",
        ),
        findsOneWidget,
      );
      expect(_composerText(tester), 'Mine');
    });

    testWidgets('NOT_IN_KB says why, and nothing is placed', (tester) async {
      final server = _Server()
        ..answer = (_) => _json(
          _suggestion(
            status: 'NOT_IN_KB',
            draft: '',
            errorCode: 'no_knowledge_base',
          ),
        );
      await _pump(tester, server);
      await _tapSuggest(tester);
      expect(
        find.text('No knowledge base has been set up yet'),
        findsOneWidget,
      );
      expect(_composerText(tester), isEmpty);

      // Dismissing reports it as discarded.
      await tester.tap(find.byKey(const Key('aiSuggestionDismiss')));
      await tester.pumpAndSettle();
      expect(server.outcomes, ['DISCARDED']);
      expect(_buttonLabel(tester), 'AI Suggest');
    });

    testWidgets('conflicting knowledge names the sources that disagree', (
      tester,
    ) async {
      final server = _Server()
        ..answer = (_) => _json(
          _suggestion(
            status: 'CONFLICTING_KNOWLEDGE',
            draft: '',
            citations: [
              {
                'source_id': 'a',
                'source_title': 'Price list 2025',
                'source_type': 'DOCUMENT',
                'chunk_id': 'c1',
                'rank': 1,
                'score': 0.9,
              },
              {
                'source_id': 'b',
                'source_title': 'Price list 2026',
                'source_type': 'DOCUMENT',
                'chunk_id': 'c2',
                'rank': 2,
                'score': 0.8,
              },
            ],
          ),
        );
      await _pump(tester, server);
      await _tapSuggest(tester);
      expect(
        find.text('Conflicting information in the knowledge base'),
        findsOneWidget,
      );
      expect(find.textContaining('Price list 2025'), findsOneWidget);
      expect(_composerText(tester), isEmpty);
    });
  });

  group('Errors', () {
    testWidgets('a failure says so, keeps the text, and Retry works', (
      tester,
    ) async {
      var calls = 0;
      final server = _Server()
        ..answer = (_) => ++calls == 1
            ? _json({
                'error': {'code': 'error', 'message': 'Server error'},
              }, 500)
            : _json(_suggestion());
      await _pump(tester, server);
      await _tapSuggest(tester);

      expect(find.text("Couldn't create a suggestion"), findsOneWidget);
      expect(_composerText(tester), isEmpty);

      await tester.tap(find.byKey(const Key('aiSuggestionRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aiSuggestionError')), findsNothing);
      expect(_composerText(tester), _draft);
    });

    testWidgets('a rate limit shows the server reason', (tester) async {
      final server = _Server()
        ..answer = (_) => _json({
          'error': {
            'code': 'throttled',
            'message': 'Too many requests. Try again in a minute.',
          },
        }, 429);
      await _pump(tester, server);
      await _tapSuggest(tester);
      expect(find.text("Couldn't create a suggestion"), findsOneWidget);
      expect(
        find.text('Too many requests. Try again in a minute.'),
        findsOneWidget,
      );
    });

    testWidgets('an outcome report failing changes nothing for the employee', (
      tester,
    ) async {
      final server = _Server();
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _Adapter((o) async {
        if (o.path.startsWith('/ai/suggestions/')) {
          server.requests.add(o);
          return _json({
            'error': {'code': 'error', 'message': 'nope'},
          }, 500);
        }
        return server._handle(o);
      });
      await _pump(tester, server, client: client);
      await _tapSuggest(tester);
      expect(_composerText(tester), _draft);
      expect(tester.takeException(), isNull);
    });
  });

  group('Conversation safety', () {
    testWidgets('a draft that arrives after another conversation was opened '
        'goes only to its own conversation', (tester) async {
      final server = _Server()..hold = Completer<void>();
      await _pump(tester, server);
      await tester.tap(_button);
      await tester.pump();

      // Open conversation 43 on top while 42's request is out.
      unawaited(
        _navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const ConversationScreen(
              key: ValueKey('conversation_43'),
              conversationId: 43,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      server.hold!.complete();
      await tester.pumpAndSettle();

      final c43 = find.byKey(const ValueKey('conversation_43'));
      expect(_composerText(tester, c43), isEmpty);
      expect(server.suggestionRequests(43), isEmpty);

      // Back on 42, the draft is in 42's own reply box.
      _navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_composerText(tester), _draft);
      expect(server.replies, isEmpty);
    });

    testWidgets('leaving the conversation drops its pending draft; coming '
        'back starts clean', (tester) async {
      final server = _Server()..hold = Completer<void>();
      await _pump(tester, server);
      await tester.tap(_button);
      await tester.pump();

      // Replaced by another conversation: 42's screen is gone.
      await _pump(tester, server, conversationId: 43);
      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_composerText(tester), isEmpty);

      // Back to 42: an empty box and the plain button.
      server.hold = null;
      await _pump(tester, server);
      expect(_composerText(tester), isEmpty);
      expect(_buttonLabel(tester), 'AI Suggest');
      expect(server.outcomes, isEmpty);
      expect(server.replies, isEmpty);
    });

    testWidgets('a draft never goes into an internal note: it waits until the '
        'reply tab is back', (tester) async {
      final server = _Server()..hold = Completer<void>();
      await _pump(tester, server);
      await tester.tap(_button);
      await tester.pump();

      await tester.tap(find.text('Internal note'));
      await tester.pumpAndSettle();
      server.hold!.complete();
      await tester.pumpAndSettle();
      final note = tester.widget<TextField>(
        find.byKey(const ValueKey('composer_internal_note_input')),
      );
      expect(note.controller!.text, isEmpty);

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aiSuggestionReady')), findsOneWidget);
      await tester.tap(find.byKey(const Key('aiSuggestionUse')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), _draft);
      expect(server.replies, isEmpty);
    });
  });

  group('Layout', () {
    testWidgets('Arabic: right-to-left, with the Arabic wording', (
      tester,
    ) async {
      var calls = 0;
      final server = _Server()
        ..hold = Completer<void>()
        ..answer = (_) => ++calls == 1
            ? _json({
                'error': {'code': 'error', 'message': ''},
              }, 503)
            : _json(_suggestion(draft: _arDraft));
      await _pump(tester, server, locale: const Locale('ar'));

      expect(_buttonLabel(tester), 'اقتراح بالذكاء الاصطناعي');
      expect(Directionality.of(tester.element(_button)), TextDirection.rtl);
      await tester.tap(_button);
      await tester.pump();
      expect(_buttonLabel(tester), 'جاري إنشاء الاقتراح…');
      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('تعذر إنشاء اقتراح'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      server.hold = null;
      await tester.tap(find.byKey(const Key('aiSuggestionRetry')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), _arDraft);
      expect(find.text('لا يُرسل شيء حتى تضغط إرسال.'), findsOneWidget);
    });

    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label on a 320px phone: every state fits', (tester) async {
        var calls = 0;
        final server = _Server()
          ..hold = Completer<void>()
          ..answer = (_) => switch (++calls) {
            1 => _json({
              'error': {
                'code': 'error',
                'message': 'The AI provider did not answer in time.',
              },
            }, 500),
            _ => _json(_suggestion()),
          };
        await _pump(tester, server, locale: locale, size: const Size(320, 568));
        expect(tester.takeException(), isNull);

        await tester.tap(_button); // loading
        await tester.pump();
        expect(tester.takeException(), isNull);
        server.hold!.complete();
        await tester.pumpAndSettle(); // failed
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('aiSuggestionError')), findsOneWidget);

        server.hold = null;
        await tester.tap(find.byKey(const Key('aiSuggestionRetry')));
        await tester.pumpAndSettle(); // placed
        expect(tester.takeException(), isNull);
        expect(_composerText(tester), _draft);
        // The reply box and Send are still on screen.
        expect(tester.getRect(_send).bottom, lessThanOrEqualTo(568));
      });
    }
  });

  group('Fallback panel', () {
    const fallbackId = '0b8d7f6e-1111-4c2a-9d3e-00000000000f';
    // A fresh body per answer: a response body is a one-use stream.
    ResponseBody notInKb() =>
        _json(_suggestion(status: 'NOT_IN_KB', draft: '', id: fallbackId));
    final retry = find.byKey(const Key('aiSuggestionRetry'));
    final discard = find.byKey(const Key('aiSuggestionDismiss'));
    final panel = find.byKey(const Key('aiSuggestionNotice'));

    bool enabledButton(WidgetTester tester, Finder finder) =>
        tester.widget<ButtonStyleButton>(finder).onPressed != null;

    testWidgets('shows the header, the reason, and both actions — Regenerate '
        'first, Discard after it', (tester) async {
      final server = _Server()..answer = (_) => notInKb();
      await _pump(tester, server);
      await _tapSuggest(tester);

      expect(panel, findsOneWidget);
      expect(find.text('AI suggestion'), findsOneWidget);
      expect(
        find.text('No reliable answer in the knowledge base'),
        findsOneWidget,
      );
      expect(find.textContaining('Write the reply yourself'), findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text('Regenerate')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: retry,
          matching: find.byIcon(Icons.refresh_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: discard, matching: find.text('Discard')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: discard,
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsOneWidget,
      );
      // Primary and secondary: a filled button, then a text button.
      expect(tester.widget(retry), isA<FilledButton>());
      expect(tester.widget(discard), isA<TextButton>());
      final r = tester.getRect(retry);
      final d = tester.getRect(discard);
      expect(r.top < d.top || r.left < d.left, isTrue);
      // One set of actions: the pill is not shown beside the panel.
      expect(_button, findsNothing);
      expect(_composerText(tester), isEmpty);
    });

    testWidgets('Regenerate shows progress, takes one tap, asks again with '
        'regenerate, and places the new draft', (tester) async {
      var calls = 0;
      final server = _Server()
        ..answer = (_) => ++calls == 1 ? notInKb() : _json(_suggestion());
      await _pump(tester, server);
      await _tapSuggest(tester);

      server.hold = Completer<void>();
      await tester.tap(retry);
      await tester.pump();
      // The panel stays, busy.
      expect(panel, findsOneWidget);
      expect(find.byKey(const Key('aiSuggestionRetrying')), findsOneWidget);
      expect(enabledButton(tester, retry), isFalse);
      expect(enabledButton(tester, discard), isFalse);
      for (var i = 0; i < 4; i++) {
        await tester.tap(retry, warnIfMissed: false);
        await tester.tap(discard, warnIfMissed: false);
        await tester.pump();
      }
      server.hold!.complete();
      await tester.pumpAndSettle();

      expect(server.suggestionRequests(), hasLength(2));
      expect(server.suggestionRequests().last.data, {'regenerate': true});
      expect(panel, findsNothing);
      expect(_composerText(tester), _draft);
      expect(_buttonLabel(tester), 'Regenerate');
      expect(server.outcomes, ['USED']);
      expect(server.replies, isEmpty);
    });

    testWidgets('another fallback keeps the panel and its actions, with the '
        'new reason', (tester) async {
      var calls = 0;
      final server = _Server()
        ..answer = (_) => ++calls == 1
            ? notInKb()
            : _json(
                _suggestion(
                  status: 'NOT_IN_KB',
                  draft: '',
                  errorCode: 'no_customer_message',
                ),
              );
      await _pump(tester, server);
      await _tapSuggest(tester);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(server.suggestionRequests(), hasLength(2));
      expect(find.text('Nothing to reply to yet'), findsOneWidget);
      expect(retry, findsOneWidget);
      expect(discard, findsOneWidget);
      expect(enabledButton(tester, retry), isTrue);

      // And again: still available.
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(server.suggestionRequests(), hasLength(3));
      expect(retry, findsOneWidget);
    });

    testWidgets('a failed retry says so, keeps the text, and offers Retry and '
        'Discard', (tester) async {
      var calls = 0;
      final server = _Server()
        ..answer = (_) => ++calls == 1
            ? notInKb()
            : _json({
                'error': {'code': 'error', 'message': 'Server error'},
              }, 500);
      await _pump(tester, server);
      await tester.enterText(_input, 'My own words');
      await tester.pump();
      await _tapSuggest(tester);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aiSuggestionError')), findsOneWidget);
      expect(find.text("Couldn't create a suggestion"), findsOneWidget);
      expect(
        find.descendant(of: retry, matching: find.text('Retry')),
        findsOneWidget,
      );
      expect(discard, findsOneWidget);
      expect(_composerText(tester), 'My own words');

      await tester.tap(discard);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aiSuggestionError')), findsNothing);
      expect(_buttonLabel(tester), 'AI Suggest');
      expect(_composerText(tester), 'My own words');
    });

    testWidgets('Discard closes only the suggestion: nothing is sent and the '
        'conversation is untouched', (tester) async {
      final server = _Server()..answer = (_) => notInKb();
      await _pump(tester, server);
      await tester.enterText(_input, 'Draft in progress');
      await tester.pump();
      await _tapSuggest(tester);

      final before = server.requests.length;
      await tester.tap(discard);
      await tester.pumpAndSettle();

      expect(panel, findsNothing);
      expect(_buttonLabel(tester), 'AI Suggest');
      expect(_composerText(tester), 'Draft in progress');
      // The only write: the outcome report for that suggestion.
      final writes = server.requests
          .skip(before)
          .where((r) => r.method != 'GET')
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.path, '/ai/suggestions/$fallbackId/outcome/');
      expect(writes.single.data, {'outcome': 'DISCARDED'});
      expect(server.replies, isEmpty);
      // No status, assignment or message request at any point — the only
      // other write is the screen marking the thread read when it opened,
      // before any of this.
      expect(
        server.requests.where(
          (r) =>
              r.method != 'GET' &&
              !r.path.endsWith('/ai-suggestion/') &&
              !r.path.startsWith('/ai/suggestions/') &&
              r.path != '/conversations/42/read/',
        ),
        isEmpty,
      );
      expect(
        server.requests
            .skip(before)
            .where((r) => r.path == '/conversations/42/read/'),
        isEmpty,
      );
      // The thread is as it was.
      expect(find.text('Is the blue bag in stock?'), findsOneWidget);

      // The button works again afterwards.
      await _tapSuggest(tester);
      expect(panel, findsOneWidget);
    });

    testWidgets('a retry that finishes after another conversation was opened '
        'lands only in its own conversation', (tester) async {
      var calls = 0;
      final server = _Server()
        ..answer = (_) => ++calls == 1 ? notInKb() : _json(_suggestion());
      await _pump(tester, server);
      await _tapSuggest(tester);

      server.hold = Completer<void>();
      await tester.tap(retry);
      await tester.pump();
      unawaited(
        _navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const ConversationScreen(
              key: ValueKey('conversation_43'),
              conversationId: 43,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      server.hold!.complete();
      await tester.pumpAndSettle();

      final c43 = find.byKey(const ValueKey('conversation_43'));
      expect(_composerText(tester, c43), isEmpty);
      expect(find.descendant(of: c43, matching: panel), findsNothing);
      expect(server.suggestionRequests(43), isEmpty);

      _navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_composerText(tester), _draft);
      expect(server.replies, isEmpty);
    });

    testWidgets('a retry still out when the conversation is left is dropped; '
        'coming back starts clean', (tester) async {
      var calls = 0;
      final server = _Server()
        ..answer = (_) => ++calls == 1 ? notInKb() : _json(_suggestion());
      await _pump(tester, server);
      await _tapSuggest(tester);
      server.hold = Completer<void>();
      await tester.tap(retry);
      await tester.pump();

      await _pump(tester, server, conversationId: 43);
      server.hold!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_composerText(tester), isEmpty);

      server.hold = null;
      await _pump(tester, server);
      expect(panel, findsNothing);
      expect(_composerText(tester), isEmpty);
      expect(_buttonLabel(tester), 'AI Suggest');
    });

    testWidgets('Arabic: right-to-left, the web wording, Regenerate first', (
      tester,
    ) async {
      final server = _Server()..answer = (_) => notInKb();
      await _pump(tester, server, locale: const Locale('ar'));
      await _tapSuggest(tester);

      expect(Directionality.of(tester.element(panel)), TextDirection.rtl);
      expect(find.text('اقتراح الذكاء الاصطناعي'), findsOneWidget);
      expect(
        find.text('لم يتم العثور على إجابة موثوقة في قاعدة المعرفة'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: retry, matching: find.text('إعادة الاقتراح')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: discard, matching: find.text('تجاهل')),
        findsOneWidget,
      );
      // Reading order: the primary action comes first — on the right of
      // the same line, or on the line above when they wrap.
      final r = tester.getRect(retry);
      final d = tester.getRect(discard);
      expect(r.top < d.top || r.right > d.right, isTrue);
    });

    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label on a 320px phone: the panel and both buttons fit, '
          'idle and busy', (tester) async {
        const width = 320.0;
        final server = _Server()
          ..answer = (_) => _json(
            _suggestion(
              status: 'CONFLICTING_KNOWLEDGE',
              draft: '',
              conflictReason:
                  'The 2025 and 2026 price lists give different prices for '
                  'the blue bag, so no price can be quoted until one of them '
                  'is corrected.',
              citations: [
                {
                  'source_id': 'a',
                  'source_title': 'Price list 2025 — wholesale and retail',
                  'source_type': 'DOCUMENT',
                  'chunk_id': 'c1',
                  'rank': 1,
                  'score': 0.9,
                },
              ],
            ),
          );
        await _pump(
          tester,
          server,
          locale: locale,
          size: const Size(width, 568),
        );
        await _tapSuggest(tester);
        expect(tester.takeException(), isNull);
        for (final f in [retry, discard]) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width));
        }

        server.hold = Completer<void>();
        await tester.tap(retry);
        await tester.pump();
        expect(tester.takeException(), isNull);
        server.hold!.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(_send).bottom, lessThanOrEqualTo(568));
      });
    }
  });

  group('Placing a draft', () {
    test('replace, add below, keep', () {
      expect(
        placeAiDraft('mine', '  draft  ', AiDraftPlacement.replace).text,
        'draft',
      );
      expect(
        placeAiDraft('mine  ', 'draft', AiDraftPlacement.append).text,
        'mine\n\ndraft',
      );
      expect(placeAiDraft('', 'draft', AiDraftPlacement.append).text, 'draft');
      final kept = placeAiDraft('mine', 'draft', AiDraftPlacement.keep);
      expect(kept.text, 'mine');
      expect(kept.selection.baseOffset, 4);
    });

    test('the response is read status first; an empty draft is no draft', () {
      expect(AiSuggestion.fromJson(_suggestion()).hasDraft, isTrue);
      expect(AiSuggestion.fromJson(_suggestion(draft: ' ')).hasDraft, isFalse);
      expect(
        AiSuggestion.fromJson(
          _suggestion(status: 'ERROR', draft: 'leftover'),
        ).hasDraft,
        isFalse,
      );
      final s = AiSuggestion.fromJson(_suggestion(through: 500));
      expect(s.isStaleAgainst(500), isFalse);
      expect(s.isStaleAgainst(501), isTrue);
      expect(s.isStaleAgainst(null), isFalse);
    });
  });
}
