/// A claim reads as a person's reply, not as routing, and shows once.
///
/// Production conversation 6146 carried a placement row and a claim record
/// for one reply. The history sheet keeps the audit rows but shows the change
/// once, worded as what happened.
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
import 'package:scenario_mobile/core/models/conversation_event.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/messages/conversation_history_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => ResponseBody.fromString(
    jsonEncode(options.path.contains('events') ? body : {}),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row(
  int id, {
  String type = 'ASSIGNED',
  String actor = '',
  int? target = 3,
  String from = 'unassigned',
  String to = 'Mohamed Gad',
  Map<String, dynamic> metadata = const {},
  String at = '2026-09-14T12:35:33.744Z',
}) => {
  'id': id,
  'event_type': type,
  'actor_name': actor,
  'target_employee_id': target,
  'target_employee_name': 'Mohamed Gad',
  'from_value': from,
  'to_value': to,
  'metadata': metadata,
  'created_at': at,
};

final _placement = _row(
  23464,
  metadata: {'automatic': true, 'mode': 'claim', 'note': 'Claimed by replying'},
);
final _record = _row(
  23465,
  from: '',
  to: '',
  metadata: {'mode': 'claim', 'message_id': 39595},
  at: '2026-09-14T12:35:34.575Z',
);

List<ConversationEvent> _parse(List<Map<String, dynamic>> rows) =>
    rows.map(ConversationEvent.fromJson).toList();

Future<void> _open(
  WidgetTester tester,
  List<Map<String, dynamic>> rows, {
  Locale locale = const Locale('en'),
}) async {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(rows);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showConversationHistorySheet(context, conversationId: 1),
              child: const Text('open history'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open history'));
  await tester.pumpAndSettle();
}

void main() {
  group('redundant historical claim', () {
    test('the pair shows once', () {
      final kept = ConversationEvent.withoutRedundantClaims(
        _parse([_placement, _record]),
      );
      expect(kept.map((e) => e.id), [23464]);
    });

    test('a claim after a transfer keeps its row', () {
      final transfer = _row(
        50,
        type: 'TRANSFERRED',
        actor: 'Sara Supervisor',
        at: '2026-09-14T12:35:34.000Z',
      );
      final kept = ConversationEvent.withoutRedundantClaims(
        _parse([_placement, transfer, _record]),
      );
      expect(kept.map((e) => e.id), [23464, 50, 23465]);
    });

    test('a claim for another employee or much later keeps its row', () {
      final other = {..._record, 'target_employee_id': 55};
      final later = {..._record, 'created_at': '2026-09-14T13:40:00Z'};
      expect(
        ConversationEvent.withoutRedundantClaims(_parse([_placement, other])),
        hasLength(2),
      );
      expect(
        ConversationEvent.withoutRedundantClaims(_parse([_placement, later])),
        hasLength(2),
      );
    });
  });

  group('history sheet', () {
    testWidgets('a claim says the person took it by replying, once', (
      tester,
    ) async {
      await _open(tester, [_placement, _record]);

      expect(
        find.text('Mohamed Gad took this conversation by replying'),
        findsOneWidget,
      );
    });

    testWidgets('in Arabic', (tester) async {
      await _open(tester, [_placement], locale: const Locale('ar'));

      expect(find.text('استلم Mohamed Gad المحادثة بعد الرد عليها'), findsOneWidget);
    });

    testWidgets('a restored claim is distinct from routing', (tester) async {
      await _open(tester, [
        _row(
          7,
          from: '',
          to: '',
          metadata: {'automatic': true, 'mode': 'claimed_owner_restored'},
        ),
      ]);

      expect(
        find.text(
          'Returned to Mohamed Gad, who had already taken this conversation',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a router assignment keeps its ordinary title', (
      tester,
    ) async {
      await _open(tester, [
        _row(8, metadata: {'automatic': true}),
      ]);

      expect(find.textContaining('took this conversation'), findsNothing);
      expect(find.text('Assigned'), findsOneWidget);
    });

    testWidgets(
      'a fallback placement says so and shows its reasons',
      (tester) async {
        await _open(tester, [
          _row(
            9,
            metadata: {
              'automatic': true,
              'mode': 'fallback',
              'reasons': [
                'no one on the responsible team was available',
                'strict responsibility disabled',
              ],
            },
          ),
        ]);

        expect(find.text('Assigned to Mohamed Gad (fallback)'), findsOneWidget);
        expect(
          find.text(
            'Reason: no one on the responsible team was available, '
            'strict responsibility disabled',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a fallback placement with no reasons shows no reasons row',
      (tester) async {
        await _open(tester, [
          _row(10, metadata: {'automatic': true, 'mode': 'fallback'}),
        ]);

        expect(find.text('Assigned to Mohamed Gad (fallback)'), findsOneWidget);
        expect(find.textContaining('Reason:'), findsNothing);
      },
    );

    testWidgets(
      'a reassignment to another employee reads as rerouted',
      (tester) async {
        await _open(tester, [
          _row(
            11,
            type: 'TRANSFERRED',
            metadata: {
              'automatic': true,
              'mode': 'reassignment',
              'previous_employee_name': 'Ali Tarek',
            },
          ),
        ]);

        expect(
          find.text('Rerouted from Ali Tarek to Mohamed Gad'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a reassignment with no one to reroute to reads as released',
      (tester) async {
        await _open(tester, [
          _row(
            12,
            type: 'UNASSIGNED',
            from: 'Ali Tarek',
            to: '',
            target: null,
            metadata: {
              'automatic': true,
              'mode': 'reassignment',
              'previous_employee_name': 'Ali Tarek',
            },
          ),
        ]);

        expect(
          find.text('Released from Ali Tarek back to the queue'),
          findsOneWidget,
        );
      },
    );
  });
}
