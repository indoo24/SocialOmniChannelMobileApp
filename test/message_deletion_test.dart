/// Message deletion: `ConversationRepository.deleteMessage()` and the
/// `ConversationState` filtering `ConversationController.removeMessage()`
/// performs.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
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

ConversationRepository _repositoryReturning(
  ResponseBody Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return ConversationRepository(client);
}

Conversation _makeConversation() => Conversation.fromJson({
  'id': 1,
  'customer': {'id': 100, 'display_name': 'Test Customer'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 3,
  'last_message_preview': 'Third message',
  'last_message_at': DateTime.now().toIso8601String(),
});

Message _makeMessage({required int id, String text = 'Hi'}) =>
    Message.fromJson({
      'id': id,
      'text': text,
      'direction': 'IN',
      'sent_at': DateTime.now().toIso8601String(),
      'sender_name': 'Customer',
      'sender_initials': 'C',
    });

void main() {
  group('ConversationRepository.deleteMessage', () {
    test(
      'DELETEs the trailing-slash path the backend actually serves',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json('', 204);
        });

        await repository.deleteMessage(1, 42);

        expect(captured!.method, 'DELETE');
        expect(captured!.path, '/conversations/1/messages/42/');
      },
    );

    test('omits the body when no reason is given', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('', 204);
      });

      await repository.deleteMessage(1, 42);

      expect(captured!.data, isNull);
    });

    test('sends {"reason": ...} when a reason is given', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('', 204);
      });

      await repository.deleteMessage(
        1,
        42,
        reason: "Contained a customer's card number",
      );

      expect(captured!.data, {'reason': "Contained a customer's card number"});
    });
  });

  group('ConversationState message removal', () {
    // ConversationController.removeMessage() is
    // `current.copyWith(messages: current.messages.where((m) => m.id != id))`
    // — exercised here at the state-shape level, the same boundary
    // `ConversationState merge preserves pending messages`
    // (realtime_bridge_test.dart) already tests other message-list mutations
    // at, since driving the real AsyncNotifier requires stubbing the full
    // inbox/detail/messages fetch cascade its build() and markReadAndSync()
    // trigger.
    test('removing a message drops only that row', () {
      final messages = [
        _makeMessage(id: 1, text: 'First'),
        _makeMessage(id: 2, text: 'Second'),
        _makeMessage(id: 3, text: 'Third'),
      ];
      final state = ConversationState(
        conversation: _makeConversation(),
        messages: messages,
      );

      final updated = state.copyWith(
        messages: state.messages.where((m) => m.id != 2).toList(),
      );

      expect(updated.messages.map((m) => m.id), [1, 3]);
    });

    test('removing an id not present is a no-op', () {
      final messages = [_makeMessage(id: 1), _makeMessage(id: 2)];
      final state = ConversationState(
        conversation: _makeConversation(),
        messages: messages,
      );

      final updated = state.copyWith(
        messages: state.messages.where((m) => m.id != 999).toList(),
      );

      expect(updated.messages.map((m) => m.id), [1, 2]);
    });
  });
}
