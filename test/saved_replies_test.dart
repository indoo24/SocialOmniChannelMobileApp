/// Saved replies on mobile: the text rules, and a picker that only ever reads.
///
/// A saved reply is inserted into the composer and sent through the ordinary
/// reply path. The picker tests record every request, so "nothing was sent" is
/// an assertion about the network rather than about the screen.
library;

import 'dart:async';
import 'dart:io';
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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply_picker.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _page = '''
{"count": 2, "next": null, "previous": null, "results": [
  {"id": 1, "title": "Thanks", "shortcut": "thanks", "body": "Thanks {{customer_name}}, we will reply shortly.", "scope": "personal", "team": null},
  {"id": 2, "title": "Phone number", "shortcut": "phone", "body": "Please send your phone number.", "scope": "team", "team": {"id": 5, "name": "Support"}}
]}
''';

void main() {
  group('renderSavedReply', () {
    test('fills known names', () {
      expect(
        renderSavedReply(
          'Hello {{customer_name}}, I am {{ agent_name }}.',
          customerName: 'Sarah',
          agentName: 'Aya',
        ),
        'Hello Sarah, I am Aya.',
      );
    });

    test('removes an unknown name and tidies the sentence', () {
      expect(
        renderSavedReply('Hello {{customer_name}}, thanks', customerName: ''),
        'Hello, thanks',
      );
    });

    test('never shows the backend placeholder as a name', () {
      expect(
        renderSavedReply(
          'Hello {{customer_name}}, thanks',
          customerName: 'Unknown customer',
        ),
        'Hello, thanks',
      );
    });

    test('tidies Arabic punctuation', () {
      expect(
        renderSavedReply('أهلاً {{customer_name}}، شكراً', customerName: null),
        'أهلاً، شكراً',
      );
    });

    test('leaves other placeholders exactly as written', () {
      expect(
        renderSavedReply(
          'Order {{1}} for {{customer_name}}',
          customerName: 'Sam',
        ),
        'Order {{1}} for Sam',
      );
    });
  });

  group('insertAtSelection', () {
    test('inserts at the caret and reports the caret after it', () {
      final result = insertAtSelection('Hi  there', 3, 3, 'Sam');
      expect(result.text, 'Hi Sam there');
      expect(result.caret, 6);
    });

    test('replaces a selection', () {
      final result = insertAtSelection('Hi XX there', 3, 5, 'Sam');
      expect(result.text, 'Hi Sam there');
    });

    test('appends when the field was never focused', () {
      final result = insertAtSelection('Hi ', -1, -1, 'Sam');
      expect(result.text, 'Hi Sam');
      expect(result.caret, 6);
    });
  });

  group('SavedReply.fromJson', () {
    test('reads the team name and tolerates odd types', () {
      final reply = SavedReply.fromJson({
        'id': '7',
        'title': 'T',
        'body': 'B',
        'shortcut': null,
        'scope': 'team',
        'team': {'id': 5, 'name': 'Support'},
      });
      expect(reply.id, 7);
      expect(reply.shortcut, '');
      expect(reply.teamName, 'Support');
    });
  });

  group('the picker', () {
    late List<RequestOptions> requests;
    late ApiClient client;

    setUp(() {
      requests = [];
      client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        requests.add(options);
        if (options.path.contains('/saved-replies/') &&
            options.method == 'GET') {
          return _json(_page, 200);
        }
        return _json('{}', 404);
      });
    });

    Future<SavedReply?> openAndPick(WidgetTester tester, String title) async {
      SavedReply? chosen;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async =>
                      chosen = await showSavedReplyPicker(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('lists usable replies and returns the one tapped', (
      tester,
    ) async {
      final chosen = await openAndPick(tester, 'Phone number');

      expect(tester.takeException(), isNull);
      expect(chosen?.id, 2);
      expect(chosen?.body, 'Please send your phone number.');
    });

    testWidgets('only ever reads — choosing a reply sends nothing', (
      tester,
    ) async {
      await openAndPick(tester, 'Thanks');

      expect(requests, isNotEmpty);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(requests.every((r) => r.path.contains('/saved-replies/')), isTrue);
      expect(requests.any((r) => r.path.contains('/reply/')), isFalse);
      expect(requests.any((r) => r.path.contains('template')), isFalse);
    });

    testWidgets('searching asks the server with the term', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SavedReplyPickerSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('savedReplySearch')),
        'phone',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        requests.any((r) => r.queryParameters['search'] == 'phone'),
        isTrue,
      );
    });
  });

  group('the conversation composer', () {
    Employee agent() => const Employee(
      id: 1,
      email: 'agent@scenario.test',
      fullName: 'Agent Smith',
      initials: 'AS',
      role: 'AGENT',
      roleDisplay: 'Agent',
      availability: 'ONLINE',
      permissions: {
        Perm.conversationReply,
        Perm.conversationNote,
        Perm.channelView,
      },
      visibilityScope: 'ALL',
      organization: Organization(id: 1, name: 'Scenario Corp'),
    );

    const channel = ChannelConnection(
      id: 10,
      provider: 'WHATSAPP',
      displayName: 'Scenario WhatsApp',
      status: 'CONNECTED',
      isActive: true,
      externalAccountId: '1189064717633052',
    );

    late List<RequestOptions> requests;

    ApiClient serverWith({required Duration sinceCustomerWrote}) {
      requests = [];
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((options) {
        requests.add(options);
        final path = options.path;
        if (path.contains('/saved-replies/')) return _json(_page, 200);
        if (path.contains('/conversations/10/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (path.contains('/conversations/10/notes/')) return _json('[]', 200);
        if (path.contains('/conversations/10/reply/')) {
          final text = (options.data as Map<String, dynamic>)['text'];
          return _json(
            '{"id": 101, "text": "$text", "sender_name": "Agent Smith", '
            '"is_outbound": true, "sent_at": "2026-09-13T12:00:00Z", '
            '"delivery_status": "SENT"}',
            201,
          );
        }
        if (path.contains('/conversations/10/')) {
          final wrote = DateTime.now()
              .subtract(sinceCustomerWrote)
              .toUtc()
              .toIso8601String();
          return _json(
            '{"id": 10, "customer": {"id": 1, "display_name": "Sarah"}, '
            '"provider": "WHATSAPP", "channel_id": 10, "status": "OPEN", '
            '"priority": "NORMAL", "unread_count": 0, "message_count": 1, '
            '"last_customer_message_at": "$wrote"}',
            200,
          );
        }
        if (path.contains('/templates/')) {
          return _json('{"templates": []}', 200);
        }
        return _json('{}', 200);
      });
      return client;
    }

    Future<void> pumpScreen(WidgetTester tester, ApiClient client) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(agent()),
            channelsProvider.overrideWith((ref) async => [channel]),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationScreen(conversationId: 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'inserts a saved reply without sending, then Send uses the ordinary reply path',
      (tester) async {
        final client = serverWith(sinceCustomerWrote: const Duration(hours: 1));
        await pumpScreen(tester, client);

        await tester.tap(find.byKey(const Key('savedRepliesButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Thanks'));
        await tester.pumpAndSettle();

        final input = find.byKey(const ValueKey('composer_reply_input'));
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Thanks Sarah, we will reply shortly.',
        );
        // Opening a conversation marks it read — the screen's own behaviour,
        // unrelated to saved replies. Everything else must be a read.
        bool isSend(RequestOptions r) =>
            r.method != 'GET' && !r.path.endsWith('/read/');
        expect(
          requests.where(isSend),
          isEmpty,
          reason: 'choosing a saved reply must not send anything',
        );

        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final writes = requests.where(isSend).toList();
        expect(writes, hasLength(1));
        expect(writes.single.path, contains('/conversations/10/reply/'));
        expect(
          (writes.single.data as Map<String, dynamic>)['text'],
          'Thanks Sarah, we will reply shortly.',
        );
        expect(requests.any((r) => r.path.contains('template')), isFalse);
      },
    );

    testWidgets('is not offered past WhatsApp\'s 24-hour window', (
      tester,
    ) async {
      final client = serverWith(sinceCustomerWrote: const Duration(hours: 48));
      await pumpScreen(tester, client);

      expect(find.byKey(const Key('savedRepliesButton')), findsNothing);
      expect(requests.any((r) => r.path.contains('/saved-replies/')), isFalse);
    });
  });

  test('the saved replies feature never reaches a customer except through '
      'the ordinary reply path', () {
    // Structural: the only way a saved reply's text reaches a customer is
    // through the composer and ConversationRepository.reply() — nothing in
    // this feature calls that, or any endpoint under /conversations/,
    // itself. `saved_replies_providers.dart` is the one file allowed to
    // write, and only ever to /saved-replies/ — managing the reply
    // definitions themselves, never sending on a customer's behalf.
    final dir = Directory('lib/features/saved_replies');
    for (final file in dir.listSync().whereType<File>()) {
      // Code only: doc comments explaining the rule must not trip it.
      final source = file
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(source.contains('.reply('), isFalse, reason: file.path);
      expect(source.contains('/conversations/'), isFalse, reason: file.path);
      if (file.path.endsWith('saved_replies_providers.dart')) continue;
      expect(source.contains('.post<'), isFalse, reason: file.path);
      expect(source.contains('.patch<'), isFalse, reason: file.path);
      expect(source.contains('.delete<'), isFalse, reason: file.path);
    }
  });
}
