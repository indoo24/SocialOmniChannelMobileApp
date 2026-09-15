/// What happens to a reply's text when the server refuses to send it —
/// specifically `400 channel_not_allowed_for_employee` (an employee whose
/// `routing_channel_scope` excludes this conversation's provider), the
/// scenario the backend↔mobile sync doc names explicitly ("Show the message
/// and keep the draft").
///
/// The composer's input field clears immediately on every send attempt
/// (`_composerController.clear()` runs before the request, matching every
/// other outbound-message UI's optimistic-then-reconcile pattern) — but the
/// typed text is not lost: it becomes the failed bubble's own text, shown in
/// the timeline with Retry/Discard actions. This test pins that down as the
/// actual, already-correct behavior, since nothing server-specific needs
/// handling for it (the backend currently collapses this refusal into the
/// generic `message_send_error` code per K2 in the sync doc, so there is no
/// distinct code to branch on yet).
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
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

/// [Conversation.isMessagingWindowClosed] treats a WhatsApp conversation
/// with no `last_customer_message_at` as closed (routing the composer to
/// Template mode, which has no free-text field) — a recent timestamp keeps
/// this test in the ordinary Reply-mode composer it is actually about.
String _conversationJson() => '''
{
  "id": 42,
  "customer": {
    "id": 7,
    "display_name": "Sarah Connor",
    "avatar_url": "",
    "initials": "SC",
    "phone": "+201124868273"
  },
  "provider": "WHATSAPP",
  "channel_name": "Scenario Sales",
  "status": "OPEN",
  "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
}
''';

void main() {
  testWidgets(
    'a reply refused with channel_not_allowed_for_employee clears the input '
    'field but keeps the text visible and retryable as a failed bubble',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path == '/conversations/42/reply/') {
          return _json(
            '{"error": {"code": "channel_not_allowed_for_employee", '
            '"message": "You do not handle this channel.", "details": {}}}',
            400,
          );
        }
        if (options.path.contains('/conversations/42/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/conversations/42/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationJson(), 200);
        }
        if (options.path.contains('/facts')) return _json('[]', 200);
        if (options.path.contains('/orders')) return _json('[]', 200);
        if (options.path.contains('/channels/')) return _json('[]', 200);
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ConversationScreen(conversationId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const draft = 'Let me check that for you';
      await tester.enterText(find.byType(TextField).first, draft);
      await tester.tap(find.byIcon(Icons.send_rounded).first);
      await tester.pumpAndSettle();

      // The input field is cleared (same as every other send attempt)...
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, isEmpty);

      // ...but the typed text was not discarded: it is the failed bubble's
      // own text, still on screen with a way to act on it. The error message
      // legitimately appears twice — once on the failed bubble itself, once
      // in the snackbar for an agent who has scrolled away from it.
      expect(find.text(draft), findsOneWidget);
      expect(find.text('You do not handle this channel.'), findsWidgets);
      expect(find.text('Retry'), findsWidgets);
      expect(find.text('Discard'), findsOneWidget);
    },
  );
}
