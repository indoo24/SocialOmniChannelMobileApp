/// Same shape of proof as `conversion_sheet_widget_test.dart`'s large-list
/// test: `_HistorySheet` (conversation_history_sheet.dart) had the identical
/// eager-`Column(children: [for (...) ...])` pattern conversion_sheet.dart's
/// real, device-confirmed ANR came from — every status/priority/category/
/// assignment/note/intelligence change logs an event, so a heavily-reused
/// conversation can accumulate a large history the same way it can
/// accumulate many conversion rows.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/messages/conversation_history_sheet.dart';
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

Widget _harness({required ApiClient apiClient, required Widget child}) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(apiClient)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () => showConversationHistorySheet(context, conversationId: 1),
  child: const Text('open history'),
);

void main() {
  testWidgets('cold pump: empty history renders with no exception', (
    tester,
  ) async {
    final client = _stubClient((options) {
      if (options.path.contains('events')) return _json('[]', 200);
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open history'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'malformed API row (null created_at, non-string event_type) renders with no exception',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('events')) {
          return _json(
            '[{"id": "bad", "event_type": 7, "actor_name": null, '
            '"from_value": null, "to_value": null, "metadata": null, '
            '"created_at": null}]',
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
      await tester.tap(find.text('open history'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a conversation with a large event history does not block the UI '
      'building every row eagerly', (tester) async {
    final rows = StringBuffer('[');
    for (var i = 0; i < 3000; i++) {
      if (i > 0) rows.write(',');
      rows.write(
        '{"id": $i, "event_type": "STATUS_CHANGED", "actor_name": "Agent", '
        '"from_value": "OPEN", "to_value": "RESOLVED", "metadata": {}, '
        '"created_at": "2026-01-0${1 + i % 9}T00:00:00Z"}',
      );
    }
    rows.write(']');

    final client = _stubClient((options) {
      if (options.path.contains('events')) {
        return _json(rows.toString(), 200);
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open history'));

    final stopwatch = Stopwatch()..start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    stopwatch.stop();

    expect(tester.takeException(), isNull);
    // Same deliberately generous budget as conversion_sheet_widget_test's
    // equivalent — this catches "builds all rows eagerly" (would still be
    // rendering after 300ms for 3000 complex rows), not a precise number.
    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(2000),
      reason:
          'Building the history list took '
          '${stopwatch.elapsedMilliseconds}ms for 3000 rows — this smells '
          'like the eager Column(children: [for (...) ...]) pattern rather '
          'than a virtualized list.',
    );
  });
}
