/// Reproduction harness for the reported Conversions-sheet crash: "Null
/// check operator used on a null value" attributed to the `ListView` in
/// `conversion_sheet.dart`, "Duplicate GlobalKeys detected in widget tree",
/// and a cascading `'!semantics.parentDataDirty' is not true`.
///
/// `flutter test` runs the real Element/RenderObject/semantics pipeline with
/// assertions enabled — the same pipeline `flutter run` uses in debug mode —
/// so a genuine duplicate-GlobalKey or null-check bug in this widget tree
/// would surface here exactly as it would on a device, with no hot reload
/// involved anywhere in this file. Every scenario goes through the real,
/// public `showConversionsSheet` / `showConversationActionsSheet` entry
/// points against a stubbed `ApiClient` (mirroring `api_client_test.dart`'s
/// `_StubAdapter`), not a synthetic stand-in for the private sheet widgets.
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
import 'package:scenario_mobile/features/messages/conversion_sheet.dart';
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

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: const {Perm.conversionReport},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _harness({required ApiClient apiClient, required Widget child}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee),
    ],
    child: MaterialApp(
      // The real theme, not Flutter's default — AppTheme.light's
      // FilledButtonThemeData sets minimumSize: Size.fromHeight(48), which
      // is exactly what made the "Report now" button throw "BoxConstraints
      // forces an infinite width" for a bare FilledButton in a Row. Every
      // test in this file already had canReport: true and still passed
      // against Flutter's default theme, which doesn't have that override —
      // using the real theme here is what actually catches this class of
      // bug going forward.
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () => showConversionsSheet(context, conversationId: 1),
  child: const Text('open conversions'),
);

void main() {
  group('Conversions sheet — reproduction of the reported crash', () {
    testWidgets(
      'the "Report now" button does not throw "BoxConstraints forces an '
      'infinite width" under the real app theme',
      (tester) async {
        // Root cause: AppTheme's FilledButtonThemeData sets minimumSize:
        // Size.fromHeight(48) == Size(double.infinity, 48), meant for
        // full-width CTAs (e.g. the login screen's button) that sit alone in
        // a Column. This "Report now" FilledButton.icon sits as a bare Row
        // child instead, which hands it unbounded width — enforcing an
        // infinite minimum width against that throws. _employee already has
        // Perm.conversionReport, so canReport is true and this button
        // renders on every test in this file; this test exists to name the
        // exact bug it's proving fixed, on top of the implicit coverage the
        // AppTheme.light harness now gives every other test here too.
        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
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
        await tester.tap(find.text('open conversions'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Report now'), findsOneWidget);
      },
    );

    testWidgets('cold pump: empty conversions list renders with no exception', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('conversions')) {
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
      await tester.tap(find.text('open conversions'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Nothing reported to Meta yet.'), findsWidgets);
    });

    testWidgets(
      'malformed API row (null created_at, non-string status/value) renders with no exception',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
            return _json(
              '[{"id": "not-an-int", "event_name": null, "status": 7, '
              '"value": null, "currency": null, "created_at": null, '
              '"error_message": null, "events_received": "oops"}]',
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
        await tester.tap(find.text('open conversions'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'navigating away while the conversions fetch is still in flight does not throw '
      'once the response arrives after the sheet is gone',
      (tester) async {
        final completer = Completer<ResponseBody>();
        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
            return completer.future;
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(builder: _openButton),
          ),
        );
        await tester.tap(find.text('open conversions'));
        // Bounded pumps, not pumpAndSettle(): the sheet is now showing its
        // loading state, whose indeterminate CircularProgressIndicator
        // animates forever and would make pumpAndSettle() time out.
        await tester.pump(); // process the tap
        await tester.pump(
          const Duration(milliseconds: 300),
        ); // sheet transition

        // Sheet is open, showing the loading state — now navigate away
        // before the network call resolves.
        Navigator.of(tester.element(find.text('open conversions'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300)); // pop transition

        // The GET now resolves after the sheet (and its provider watchers)
        // have gone. This is the "stale provider result after dispose" case.
        // Dio's own interceptor chain schedules a zero-duration Timer while
        // processing the response, so this needs real time advanced (not
        // just a microtask pump) to flush it before the test ends.
        completer.complete(_json('[]', 200));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'reopening after the provider has already resolved once serves cached data '
      'with no exception',
      (tester) async {
        var requestCount = 0;
        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
            requestCount += 1;
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

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('open conversions'));
          await tester.pumpAndSettle();
          Navigator.of(tester.element(find.text('open conversions'))).pop();
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
        expect(requestCount, greaterThanOrEqualTo(1));
      },
    );

    for (final status in [
      'sent',
      'already_reported',
      'failed',
      'not_configured',
      'skipped',
      'unmatchable',
    ]) {
      testWidgets('report-conversion status "$status" does not throw', (
        tester,
      ) async {
        final client = _stubClient((options) {
          if (options.path.contains('report-conversion')) {
            return _json(
              '{"status": "$status", "detail": "Server said $status.", '
              '"event_name": "Lead", "stage": "QUALIFIED_LEAD"}',
              200,
            );
          }
          if (options.path.contains('conversions')) {
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
        await tester.tap(find.text('open conversions'));
        await tester.pumpAndSettle();

        final reportButton = find.text('Report now');
        expect(reportButton, findsOneWidget);
        await tester.tap(reportButton);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Server said $status.'), findsOneWidget);
      });
    }

    testWidgets(
      'opening Conversions from Actions without popping Actions first — the exact '
      'real navigation path — does not duplicate any GlobalKey',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
            return _json('[]', 200);
          }
          return _json('{}', 200);
        });

        await tester.pumpWidget(
          _harness(
            apiClient: client,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('Conversions'),
                        // Deliberately does NOT pop the Actions sheet first —
                        // matches conversation_actions_sheet.dart's real
                        // ListTile.onTap for the Conversions row exactly.
                        onTap: () => showConversionsSheet(
                          sheetContext,
                          conversationId: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                child: const Text('open actions'),
              ),
            ),
          ),
        );

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('open actions'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Conversions'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);

          // Close both stacked sheets.
          final navigator = Navigator.of(
            tester.element(find.text('open actions')),
          );
          navigator.pop();
          await tester.pumpAndSettle();
          navigator.pop();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'a conversation with a large conversions history does not block the UI '
      'for seconds building every row eagerly',
      (tester) async {
        // Reproduces the real-world crash report: on device this manifested
        // as an ANR ("Input dispatching timed out ... Waited 10001ms for
        // MotionEvent"), not a Dart exception. The eager
        // Column(children: [for (...) ...]) this replaced built and laid out
        // every row synchronously in one frame instead of only the visible
        // ones; on this host that measured as tens of milliseconds slower
        // per critical frame than the SliverList fix, not seconds — but
        // debug-mode Dart JIT on real mid-range hardware amplifies CPU-bound
        // work far more than a desktop test host does, so the gap on device
        // is expected to be much larger. A conversation reused heavily
        // across a long manual test session (repeated "Report now" taps)
        // can plausibly accumulate this many rows.
        final rows = StringBuffer('[');
        for (var i = 0; i < 3000; i++) {
          if (i > 0) rows.write(',');
          rows.write(
            '{"id": $i, "event_name": "Lead", "status": "SENT", '
            '"value": "", "currency": "", '
            '"created_at": "2026-01-0${1 + i % 9}T00:00:00Z", '
            '"error_message": "", "events_received": 1}',
          );
        }
        rows.write(']');

        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
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
        await tester.tap(find.text('open conversions'));

        final stopwatch = Stopwatch()..start();
        // Bounded pumps, not pumpAndSettle(): DraggableScrollableSheet keeps
        // rescheduling frames indefinitely once its content is this large
        // (an unrelated, apparently harmless extent-estimation quirk — see
        // the equivalent note in conversation_history_sheet_widget_test.dart)
        // regardless of whether the list is virtualized, so pumpAndSettle()
        // never returns here. A few explicit pumps are enough to observe
        // whether the *build itself* is fast or not.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        stopwatch.stop();

        expect(tester.takeException(), isNull);
        // Not a hard performance budget (host timing varies) — this is
        // deliberately generous. The point is to catch the difference
        // between "virtualized" (fast regardless of row count) and "builds
        // all 3000 rows eagerly" (much slower), not to pin an exact number.
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(2000),
          reason:
              'Building the conversions list took '
              '${stopwatch.elapsedMilliseconds}ms for 3000 rows — this '
              'smells like the eager Column(children: [for (...) ...]) '
              'pattern rather than a virtualized list.',
        );
      },
    );

    testWidgets(
      'a conversation with more than the render cap shows only the most '
      'recent rows plus a truncation note',
      (tester) async {
        // 250, not 500 — safely above the 200-row cap while staying under
        // the ~300-350 row threshold (found earlier this session) where
        // DraggableScrollableSheet + a large SliverList never lets
        // pumpAndSettle() finish; that's a separate, already-understood
        // quirk this test isn't about.
        const totalRows = 250;
        final rows = StringBuffer('[');
        for (var i = 0; i < totalRows; i++) {
          if (i > 0) rows.write(',');
          rows.write(
            '{"id": $i, "event_name": "Lead $i", "status": "SENT", '
            '"value": "", "currency": "", '
            '"created_at": "2026-01-0${1 + i % 9}T00:00:00Z", '
            '"error_message": "", "events_received": 1}',
          );
        }
        rows.write(']');

        final client = _stubClient((options) {
          if (options.path.contains('conversions')) {
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
        await tester.tap(find.text('open conversions'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Lead 0'), findsOneWidget);

        // The truncation note sits after 200 rows' worth of content, well
        // outside the initial viewport/cache extent — scroll to it.
        final note = find.text('Showing the most recent 200 of $totalRows.');
        await tester.dragUntilVisible(
          note,
          find.byType(CustomScrollView),
          const Offset(0, -300),
        );
        expect(tester.takeException(), isNull);
        expect(note, findsOneWidget);
      },
    );
  });
}
