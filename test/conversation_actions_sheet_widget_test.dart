/// Reproduction harness for the reported crash: opening the real Actions
/// sheet (`conversation_actions_sheet.dart`'s `_ActionsSheet`, via the
/// public `showConversationActionsSheet`) and tapping its "Conversions" row.
///
/// `test/conversion_sheet_widget_test.dart` already proved the *navigation
/// pattern* (a stacked modal sheet opened without popping its parent) is
/// safe, but it drove that through a synthetic stand-in `ListTile`, not the
/// real `_ActionsSheet` widget — which reads `conversationControllerProvider`,
/// `currentEmployeeProvider` and several `Perm` gates before it ever renders
/// its rows. This file closes that gap: it pumps the actual `_ActionsSheet`
/// against a stubbed `ApiClient` so `ConversationController`'s real fetch
/// path runs, then taps the real "Conversions" `ListTile`.
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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_actions_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ignore: library_private_types_in_public_api
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

// No extra permissions: the "Conversation history" and "Conversions" rows
// are shown to every active employee (conversation_actions_sheet.dart's own
// comment: "Open to any active employee — no permission gate"), so an empty
// permission set is enough to reach the real row this bug report is about
// without needing to stub categoriesProvider/assign/status/priority too.
final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {},
  visibilityScope: 'ASSIGNED',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

/// Stubs exactly what `ConversationController._fetchAndMergeOnOpen()` calls
/// (`GET /conversations/{id}/` and `GET /conversations/{id}/messages/`), plus
/// whatever the tapped sheet needs, via [extra].
ApiClient _clientFor({
  FutureOr<ResponseBody>? Function(RequestOptions options)? extra,
}) {
  return _stubClient((options) {
    final fromExtra = extra?.call(options);
    if (fromExtra != null) return fromExtra;
    if (options.path.endsWith('/conversations/1/')) {
      return _json(
        '{"id": 1, "customer": {"id": 1, "display_name": "Test Customer"}, '
        '"provider": "WHATSAPP", "status": "OPEN", "priority": "NORMAL", '
        '"unread_count": 0, "message_count": 0}',
        200,
      );
    }
    if (options.path.contains('/messages/')) {
      return _json('{"results": [], "count": 0}', 200);
    }
    if (options.path.contains('/conversions/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/events/')) {
      return _json('[]', 200);
    }
    return _json('{}', 200);
  });
}

Widget _harness({required ApiClient apiClient, required Widget child}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () => showConversationActionsSheet(context, conversationId: 1),
  child: const Text('open actions'),
);

void main() {
  testWidgets(
    'opening the real Actions sheet and tapping Conversions does not throw',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open actions'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Conversions'), findsOneWidget);

      await tester.tap(find.text('Conversions'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Nothing reported to Meta yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'opening the real Actions sheet and tapping Conversation history does not throw',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open actions'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View history'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening and closing the real Actions sheet repeatedly does not throw',
    (tester) async {
      final client = _clientFor();

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('open actions'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        Navigator.of(tester.element(find.text('open actions'))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
