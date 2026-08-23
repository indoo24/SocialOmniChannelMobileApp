/// UI flows for the internal-notes sheet: loading/empty/error states, the
/// composer's disabled-when-blank behavior, successful submit updating the
/// list without a full reload, and preserving the draft on failure.
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
import 'package:scenario_mobile/features/messages/notes_sheet.dart';
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

Employee _employee({bool canWrite = true}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: canWrite ? const {Perm.conversationNote} : const {},
  visibilityScope: 'ASSIGNED',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _harness({
  required ApiClient apiClient,
  required Widget child,
  bool canWrite = true,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee(canWrite: canWrite)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () => showInternalNotesSheet(context, conversationId: 1),
  child: const Text('open notes'),
);

void main() {
  testWidgets('empty notes list shows the empty state', (tester) async {
    final client = _stubClient((options) {
      if (options.path.contains('/notes/') && options.method == 'GET') {
        return _json('[]', 200);
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open notes'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No internal notes yet.'), findsOneWidget);
  });

  testWidgets('existing notes render with author and body', (tester) async {
    final client = _stubClient((options) {
      if (options.path.contains('/notes/') && options.method == 'GET') {
        return _json(
          '[{"id": 1, "body": "Called back, no answer.", '
          '"author_name": "Mohamed Gad", "author_initials": "MG", '
          '"created_at": "2026-08-21T04:52:00Z"}]',
          200,
        );
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open notes'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Called back, no answer.'), findsOneWidget);
    expect(find.text('Mohamed Gad'), findsOneWidget);
  });

  testWidgets('the send button is disabled for empty/whitespace-only input and '
      'enables once real text is typed', (tester) async {
    final client = _stubClient((options) {
      if (options.path.contains('/notes/') && options.method == 'GET') {
        return _json('[]', 200);
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open notes'));
    await tester.pumpAndSettle();

    IconButton sendButton() =>
        tester.widget<IconButton>(find.byType(IconButton));

    expect(sendButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(sendButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  hello  ');
    await tester.pump();
    expect(sendButton().onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(sendButton().onPressed, isNull);
  });

  testWidgets(
    'submitting a note appends it to the list (no full reload) and clears '
    'the input',
    (tester) async {
      var getCount = 0;
      final client = _stubClient((options) {
        if (options.path.contains('/notes/') && options.method == 'GET') {
          getCount += 1;
          return _json('[]', 200);
        }
        if (options.path.contains('/notes/') && options.method == 'POST') {
          return _json(
            '{"id": 2, "body": "New note", "author_name": "Sam Agent", '
            '"author_initials": "SA", "created_at": "2026-08-21T05:00:00Z"}',
            201,
          );
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open notes'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New note');
      await tester.pump();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('New note'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      // Exactly one GET (the initial load) — the successful POST updates
      // the list in place rather than triggering a second fetch.
      expect(getCount, 1);
    },
  );

  testWidgets('a failed submit preserves the typed text and shows the error', (
    tester,
  ) async {
    final client = _stubClient((options) {
      if (options.path.contains('/notes/') && options.method == 'GET') {
        return _json('[]', 200);
      }
      if (options.path.contains('/notes/') && options.method == 'POST') {
        return _json(
          '{"error": {"code": "forbidden", "message": '
          '"You cannot add notes here.", "details": {}}}',
          403,
        );
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open notes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Will fail');
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Will fail',
    );
    expect(find.text('You cannot add notes here.'), findsOneWidget);
  });

  testWidgets(
    'an employee without conversation.note sees notes but no composer',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('/notes/') && options.method == 'GET') {
          return _json(
            '[{"id": 1, "body": "Read-only view", "author_name": "Someone", '
            '"author_initials": "S", "created_at": "2026-08-21T04:00:00Z"}]',
            200,
          );
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          canWrite: false,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open notes'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Read-only view'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );
}
