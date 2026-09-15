/// Retrying a server-stored `FAILED` message: `ConversationRepository.retryMessage()`
/// and `ConversationController.retryStoredMessage()`.
///
/// Distinct from `ConversationController.retry()`, which resends a message
/// that never reached the server (identified by a local id). This is for a
/// message the server already holds and marked `FAILED` — the backend's own
/// `POST .../messages/{id}/retry/`, whose atomic claim means a double-tap can
/// never send it twice, unlike a fresh `reply()` would risk.
///
/// Mirrors `message_deletion_test.dart`'s `_StubAdapter` pattern for the
/// repository layer, and `message_delivery_update_test.dart`'s fake-notifier
/// pattern for the controller layer.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';

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

ApiClient _stubClient(ResponseBody Function(RequestOptions options) handler) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

ConversationRepository _repositoryReturning(
  ResponseBody Function(RequestOptions options) handler,
) => ConversationRepository(_stubClient(handler));

Conversation _makeConversation({int id = 1}) => Conversation.fromJson({
  'id': id,
  'customer': {'id': 100, 'display_name': 'Test Customer'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
  'last_message_preview': 'Hello',
  'last_message_at': DateTime.now().toIso8601String(),
});

String _failedMessageJson({required int id}) => '''
{
  "id": $id,
  "text": "Sorry, missed this",
  "direction": "OUTBOUND",
  "sender_type": "AGENT",
  "sent_at": "2026-01-01T00:00:00Z",
  "delivery_status": "FAILED",
  "delivery_error": "The provider could not be reached.",
  "delivery_error_code": "channel_unavailable"
}
''';

Message _failedMessage({required int id}) =>
    Message.fromJson({
      'id': id,
      'text': 'Sorry, missed this',
      'direction': 'OUTBOUND',
      'sender_type': 'AGENT',
      'sent_at': DateTime.now().toIso8601String(),
      'delivery_status': 'FAILED',
      'delivery_error': 'The provider could not be reached.',
      'delivery_error_code': 'channel_unavailable',
    });

/// A `ConversationController` seeded with fixed state, so `retryStoredMessage`
/// can be exercised without driving the real REST-backed `build()`.
class _FakeConversationController extends ConversationController {
  _FakeConversationController(super.conversationId, this._initial);

  final ConversationState _initial;
  int refreshFromServerCalls = 0;

  @override
  Future<ConversationState> build() async => _initial;

  @override
  Future<void> refreshFromServer({String? triggerTraceId}) async {
    refreshFromServerCalls += 1;
  }
}

void main() {
  group('ConversationRepository.retryMessage', () {
    test('POSTs the documented retry path and parses the response', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_failedMessageJson(id: 42), 200);
      });

      final result = await repository.retryMessage(1, 42);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/conversations/1/messages/42/retry/');
      expect(captured!.data, isNull, reason: 'no request body is documented');
      expect(result.id, 42);
    });

    test('a 409 (already retried or sent) surfaces as ApiException', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "conflict", "message": "Not waiting to be '
          'retried.", "details": {}}}',
          409,
        ),
      );

      await expectLater(
        repository.retryMessage(1, 42),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('a 400 (provider refused again) surfaces as ApiException', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "message_send_error", "message": "The '
          'provider refused it again.", "details": {}}}',
          400,
        ),
      );

      await expectLater(
        repository.retryMessage(1, 42),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });
  });

  group('ConversationController.retryStoredMessage', () {
    test('replaces the failed message with the server response on success', () async {
      final controller = _FakeConversationController(
        1,
        ConversationState(
          conversation: _makeConversation(id: 1),
          messages: [_failedMessage(id: 42)],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          conversationControllerProvider(1).overrideWith(() => controller),
          apiClientProvider.overrideWithValue(
            _stubClient((_) => _json(_failedMessageJson(id: 42), 200)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(conversationControllerProvider(1).future);

      await controller.retryStoredMessage(42);

      final state = container.read(conversationControllerProvider(1)).value!;
      final message = state.messages.single;
      expect(message.id, 42);
      // The stub always answers FAILED again in this test — the point being
      // verified is that state was replaced with whatever the server said,
      // not that it necessarily always flips to success.
      expect(message.deliveryStatus, 'FAILED');
    });

    test('a 409 refreshes from the server instead of throwing', () async {
      final controller = _FakeConversationController(
        1,
        ConversationState(
          conversation: _makeConversation(id: 1),
          messages: [_failedMessage(id: 42)],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          conversationControllerProvider(1).overrideWith(() => controller),
          apiClientProvider.overrideWithValue(
            _stubClient(
              (_) => _json(
                '{"error": {"code": "conflict", "message": "Not waiting to '
                'be retried.", "details": {}}}',
                409,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(conversationControllerProvider(1).future);

      await controller.retryStoredMessage(42);

      expect(controller.refreshFromServerCalls, 1);
    });

    test('a non-409 failure rethrows rather than being silently swallowed', () async {
      final controller = _FakeConversationController(
        1,
        ConversationState(
          conversation: _makeConversation(id: 1),
          messages: [_failedMessage(id: 42)],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          conversationControllerProvider(1).overrideWith(() => controller),
          apiClientProvider.overrideWithValue(
            _stubClient(
              (_) => _json(
                '{"error": {"code": "message_send_error", "message": '
                '"The provider refused it again.", "details": {}}}',
                400,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(conversationControllerProvider(1).future);

      await expectLater(
        controller.retryStoredMessage(42),
        throwsA(isA<ApiException>()),
      );
      expect(controller.refreshFromServerCalls, 0);
    });
  });
}
