/// Meta conversions reporting: `ConversionEvent`/`ConversionReportResult`
/// model parsing and `ConversationRepository.conversions()`/
/// `.reportConversion()`.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversion_event.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
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

ConversationRepository _repositoryReturning(
  ResponseBody Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return ConversationRepository(client);
}

void main() {
  group('ConversionEvent.fromJson', () {
    test('parses the full backend shape', () {
      final event = ConversionEvent.fromJson({
        'id': 3,
        'event_name': 'Purchase',
        'source_stage': 'HOT_LEAD',
        'source_purchase_status': 'AGENT_CONFIRMED',
        'status': 'SENT',
        'events_received': 1,
        'error_message': '',
        'value': '49.99',
        'currency': 'USD',
        'created_at': '2026-08-20T09:00:00Z',
      });

      expect(event.id, 3);
      expect(event.eventName, 'Purchase');
      expect(event.status, 'SENT');
      expect(event.succeeded, isTrue);
      expect(event.value, '49.99');
      expect(event.currency, 'USD');
      expect(event.createdAt, isNotNull);
    });

    test('a failed send is never upgraded to succeeded', () {
      final event = ConversionEvent.fromJson({
        'id': 4,
        'event_name': 'Lead',
        'status': 'FAILED',
        'error_message': 'Meta rejected the event.',
      });

      expect(event.succeeded, isFalse);
      expect(event.errorMessage, 'Meta rejected the event.');
    });

    test('malformed fields fall back rather than throwing', () {
      final event = ConversionEvent.fromJson(const {});

      expect(event.id, -1);
      expect(event.eventName, isEmpty);
      expect(event.status, isEmpty);
      expect(event.succeeded, isFalse);
      expect(event.createdAt, isNull);
    });
  });

  group('ConversionReportResult.fromJson', () {
    test('sent is the only status that counts as succeeded', () {
      final result = ConversionReportResult.fromJson({
        'status': 'sent',
        'detail': 'Meta accepted Purchase.',
        'event_name': 'Purchase',
        'stage': 'HOT_LEAD',
      });

      expect(result.succeeded, isTrue);
      expect(result.detail, 'Meta accepted Purchase.');
    });

    for (final status in [
      'already_reported',
      'failed',
      'not_configured',
      'skipped',
      'unmatchable',
    ]) {
      test('"$status" parses without throwing and is not succeeded', () {
        final result = ConversionReportResult.fromJson({
          'status': status,
          'detail': 'Some server-authored explanation.',
          'event_name': '',
          'stage': 'LEAD',
        });

        expect(result.status, status);
        expect(result.succeeded, isFalse);
        expect(result.detail, 'Some server-authored explanation.');
      });
    }
  });

  group('ConversationRepository.conversions', () {
    test('parses a plain, newest-first array', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '[{"id": 1, "event_name": "Purchase", "status": "SENT", '
          '"created_at": "2026-08-20T09:00:00Z"}, '
          '{"id": 2, "event_name": "Lead", "status": "SKIPPED", '
          '"created_at": "2026-08-19T09:00:00Z"}]',
          200,
        );
      });

      final result = await repository.conversions(1);

      expect(captured!.path, '/conversations/1/conversions/');
      expect(result, hasLength(2));
      expect(result.first.status, 'SENT');
      expect(result.last.status, 'SKIPPED');
    });

    test('a malformed row is dropped, not fatal to the page', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '[{"id": 1, "status": "SENT"}, "not-an-object", {"id": 3, "status": "FAILED"}]',
          200,
        ),
      );

      final result = await repository.conversions(1);

      expect(result, hasLength(2));
      expect(result.map((e) => e.id), [1, 3]);
    });
  });

  group('ConversationRepository.reportConversion', () {
    // The endpoint always answers 200 — even a refused/skipped/duplicate
    // report is a normal response, not an ApiException. This is the one
    // behavior the guide explicitly warns is easy to get backwards.
    for (final status in [
      'sent',
      'already_reported',
      'failed',
      'not_configured',
      'skipped',
      'unmatchable',
    ]) {
      test(
        'a 200 with status "$status" does not throw an ApiException',
        () async {
          final repository = _repositoryReturning(
            (_) => _json(
              '{"status": "$status", "detail": "Server explanation.", '
              '"event_name": "Purchase", "stage": "HOT_LEAD"}',
              200,
            ),
          );

          final result = await repository.reportConversion(1);

          expect(result.status, status);
          expect(result.detail, 'Server explanation.');
        },
      );
    }

    test('POSTs with no body to the correct path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"status": "sent", "detail": "ok", "event_name": "Purchase", "stage": "HOT_LEAD"}',
          200,
        );
      });

      await repository.reportConversion(1);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/conversations/1/report-conversion/');
    });

    test('a real error status still throws ApiException', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
          403,
        ),
      );

      expect(() => repository.reportConversion(1), throwsA(isA<Exception>()));
    });
  });
}
