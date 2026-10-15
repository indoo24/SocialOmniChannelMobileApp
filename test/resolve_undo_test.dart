/// Undo after resolving: it goes back to the status the conversation had,
/// through the real status endpoint, only says "reopened" once the server
/// accepted that, and leaves the conversation resolved when it refused.
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
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, [int status = 200]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// A server holding one conversation, starting at [initialStatus]. Every
/// status change it is asked for is recorded; [refuse] makes it answer 400
/// to any change back out of RESOLVED.
class _Server {
  _Server({this.initialStatus = 'WAITING_CUSTOMER', this.refuse = false})
    : status = initialStatus;

  final String initialStatus;
  final bool refuse;
  String status;
  final requested = <String>[];

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter((options) {
      final path = options.path;
      if (path.contains('/conversations/42/status/')) {
        final raw = options.data;
        final body = raw is String
            ? jsonDecode(raw) as Map<String, dynamic>
            : (raw as Map).cast<String, dynamic>();
        final next = body['status'] as String;
        requested.add(next);
        if (refuse && status == 'RESOLVED') {
          return _json('{"detail": "This transition is not allowed."}', 400);
        }
        status = next;
        return _json('{"id": 42, "status": "$status"}');
      }
      if (path.contains('/conversations/42/messages/')) {
        return _json('{"results": []}');
      }
      if (path.contains('/conversations/42/notes/')) return _json('[]');
      if (path.contains('/conversations/42/')) {
        return _json('''{
          "id": 42,
          "customer": {"id": 7, "display_name": "Sarah Connor", "initials": "SC"},
          "provider": "WHATSAPP",
          "status": "$status",
          "is_follow_up": false
        }''');
      }
      if (path.contains('/read/')) return _json('{"success": true}');
      if (path.contains('/conversations/')) {
        return _json(
          '{"count": 0, "next": null, "previous": null, "results": []}',
        );
      }
      return _json('{}');
    });
    return client;
  }
}

Employee _employee() => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationChangeStatus},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Future<void> _openAndResolve(WidgetTester tester, _Server server) async {
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
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation_resolve_button')));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('Undo puts back the status the conversation had', (tester) async {
    final server = _Server();
    await _openAndResolve(tester, server);

    expect(server.requested, ['RESOLVED']);
    expect(find.text('Conversation resolved'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('resolveUndoAction')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Back to what it was — not a blanket OPEN.
    expect(server.requested, ['RESOLVED', 'WAITING_CUSTOMER']);
    expect(server.status, 'WAITING_CUSTOMER');
    expect(find.text('Conversation reopened'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('a refused Undo says so and the conversation stays resolved', (
    tester,
  ) async {
    final server = _Server(refuse: true);
    await _openAndResolve(tester, server);

    await tester.tap(find.byKey(const Key('resolveUndoAction')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(server.requested, ['RESOLVED', 'WAITING_CUSTOMER']);
    expect(server.status, 'RESOLVED');
    expect(find.text('Conversation reopened'), findsNothing);
    expect(find.text('This transition is not allowed.'), findsOneWidget);
    // Still shown as resolved: nothing was changed on the screen's own say-so.
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });

  testWidgets('Undo is offered for five seconds, then goes away unused', (
    tester,
  ) async {
    final server = _Server();
    await _openAndResolve(tester, server);
    expect(find.byKey(const Key('resolveUndoAction')), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('resolveUndoAction')), findsNothing);
    expect(server.requested, ['RESOLVED']);
    expect(server.status, 'RESOLVED');
  });

  testWidgets('Undo can only be used once', (tester) async {
    final server = _Server();
    await _openAndResolve(tester, server);

    await tester.tap(find.byKey(const Key('resolveUndoAction')));
    await tester.pump();
    // The action is gone with its snack bar; a second tap finds nothing.
    await tester.tap(
      find.byKey(const Key('resolveUndoAction')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(server.requested, ['RESOLVED', 'WAITING_CUSTOMER']);
  });

  testWidgets('Undo still works after leaving the conversation', (
    tester,
  ) async {
    final server = _Server();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(server.client()),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('inbox')),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const ConversationScreen(conversationId: 42),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_resolve_button')));
    await tester.pump(const Duration(milliseconds: 600));

    navigatorKey.currentState!.pop();
    // Until the page transition ends both pages show the snack bar.
    await tester.pumpAndSettle();
    expect(find.text('inbox'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resolveUndoAction')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(server.status, 'WAITING_CUSTOMER');
    expect(find.text('Conversation reopened'), findsOneWidget);
  });

  testWidgets('tapping the button again reopens the conversation', (
    tester,
  ) async {
    final server = _Server();
    await _openAndResolve(tester, server);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('conversation_resolve_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(server.requested, ['RESOLVED', 'OPEN']);
    expect(server.status, 'OPEN');
    expect(find.text('Conversation reopened'), findsOneWidget);
    // The resolve's Undo is gone: it would now undo the wrong thing.
    expect(find.byKey(const Key('resolveUndoAction')), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);

    // And it can be resolved again.
    await tester.tap(find.byKey(const Key('conversation_resolve_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(server.requested, ['RESOLVED', 'OPEN', 'RESOLVED']);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });

  testWidgets('a refused reopen leaves it resolved and says why', (
    tester,
  ) async {
    final server = _Server(refuse: true);
    await _openAndResolve(tester, server);

    await tester.tap(find.byKey(const Key('conversation_resolve_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(server.requested, ['RESOLVED', 'OPEN']);
    expect(server.status, 'RESOLVED');
    expect(find.text('This transition is not allowed.'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });
}
