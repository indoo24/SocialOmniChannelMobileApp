/// Conversation audit timeline: `ConversationEvent` model parsing and
/// `ConversationRepository.events()`.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation_event.dart';
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
  group('ConversationEvent.fromJson', () {
    test('parses the full backend shape', () {
      final event = ConversationEvent.fromJson({
        'id': 7,
        'event_type': 'ASSIGNED',
        'actor_name': 'Mona',
        'from_value': 'unassigned',
        'to_value': 'Sam',
        'metadata': {'note': 'Escalated'},
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(event.id, 7);
      expect(event.eventType, 'ASSIGNED');
      expect(event.actorName, 'Mona');
      expect(event.fromValue, 'unassigned');
      expect(event.toValue, 'Sam');
      expect(event.metadata['note'], 'Escalated');
      expect(event.createdAt, isNotNull);
    });

    test('an unrecognized event_type parses without throwing', () {
      final event = ConversationEvent.fromJson({
        'id': 1,
        'event_type': 'SOME_FUTURE_EVENT_TYPE',
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(event.eventType, 'SOME_FUTURE_EVENT_TYPE');
    });

    test('a system-authored event has an empty actor_name', () {
      final event = ConversationEvent.fromJson({
        'id': 2,
        'event_type': 'INTELLIGENCE_REFRESHED',
        'actor_name': '',
        'created_at': '2026-08-19T10:00:00Z',
      });

      expect(event.actorName, isEmpty);
    });

    test('malformed fields fall back rather than throwing', () {
      final event = ConversationEvent.fromJson(const {});

      expect(event.id, -1);
      expect(event.eventType, isEmpty);
      expect(event.actorName, isEmpty);
      expect(event.fromValue, isEmpty);
      expect(event.toValue, isEmpty);
      expect(event.metadata, isEmpty);
      expect(event.createdAt, isNull);
    });
  });

  group('ConversationRepository.events', () {
    test('parses a plain, oldest-first array', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '[{"id": 1, "event_type": "CONVERSATION_CREATED", "created_at": "2026-08-19T09:00:00Z"}, '
          '{"id": 2, "event_type": "STATUS_CHANGED", "from_value": "NEW", "to_value": "OPEN", '
          '"created_at": "2026-08-19T09:05:00Z"}]',
          200,
        );
      });

      final result = await repository.events(1);

      expect(captured!.path, '/conversations/1/events/');
      expect(result, hasLength(2));
      expect(result.first.eventType, 'CONVERSATION_CREATED');
      expect(result.last.eventType, 'STATUS_CHANGED');
      expect(result.last.toValue, 'OPEN');
    });

    test('a malformed row is dropped, not fatal to the page', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '[{"id": 1, "event_type": "ASSIGNED"}, "not-an-object", '
          '{"id": 3, "event_type": "NOTE_ADDED"}]',
          200,
        ),
      );

      final result = await repository.events(1);

      expect(result, hasLength(2));
      expect(result.map((e) => e.id), [1, 3]);
    });

    test('an empty list is handled cleanly', () async {
      final repository = _repositoryReturning((_) => _json('[]', 200));

      final result = await repository.events(1);

      expect(result, isEmpty);
    });
  });
}
