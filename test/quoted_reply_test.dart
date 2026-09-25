/// Quoted replies: `QuotedMessage` parsing, `ConversationRepository.reply()`
/// sending `reply_to_id`, and `ConversationController.send()`/`retry()`
/// building and preserving the optimistic quote.
///
/// Mirrors `message_deletion_test.dart`'s `_StubAdapter` pattern for the
/// repository layer.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
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
  group('QuotedMessage.fromJson', () {
    test('parses a full reply_to snapshot', () {
      final message = Message.fromJson({
        'id': 99,
        'text': 'Got it, thanks!',
        'direction': 'OUTBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
        'reply_to': {
          'id': 42,
          'text': 'What time do you close?',
          'truncated': false,
          'message_type': 'TEXT',
          'direction': 'INBOUND',
          'sender_name': 'Sarah Connor',
          'sent_at': '2026-01-01T00:00:00Z',
          'is_deleted': false,
          'available': true,
        },
      });

      final quote = message.replyTo;
      expect(quote, isNotNull);
      expect(quote!.id, 42);
      expect(quote.text, 'What time do you close?');
      expect(quote.senderName, 'Sarah Connor');
      expect(quote.isDeleted, isFalse);
      expect(quote.available, isTrue);
    });

    test('renders when the original was deleted', () {
      final message = Message.fromJson({
        'id': 99,
        'text': 'Re: that',
        'direction': 'OUTBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
        'reply_to': {'id': 42, 'is_deleted': true, 'available': true},
      });

      expect(message.replyTo!.isDeleted, isTrue);
    });

    test('is null when the message has no reply_to', () {
      final message = Message.fromJson({
        'id': 99,
        'text': 'Not a reply',
        'direction': 'OUTBOUND',
        'sent_at': '2026-01-01T00:00:00Z',
      });

      expect(message.replyTo, isNull);
    });
  });

  group('QuotedMessage.fromMessage', () {
    test('snapshots the fields the bubble needs, from a live Message', () {
      final original = Message.fromJson({
        'id': 42,
        'text': 'What time do you close?',
        'direction': 'INBOUND',
        'sender_name': 'Sarah Connor',
        'sent_at': '2026-01-01T00:00:00Z',
      });

      final quote = QuotedMessage.fromMessage(original);

      expect(quote.id, 42);
      expect(quote.text, 'What time do you close?');
      expect(quote.senderName, 'Sarah Connor');
      expect(quote.direction, 'INBOUND');
      // A locally-built snapshot is never "deleted" or "unavailable" — those
      // states only ever come from the server's own reply_to.
      expect(quote.isDeleted, isFalse);
      expect(quote.available, isTrue);
    });
  });

  group('ConversationRepository.reply with replyToId', () {
    test('sends reply_to_id when a quoted message is given', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"id": 99, "text": "Got it", "direction": "OUTBOUND", '
          '"sent_at": "2026-01-01T00:00:00Z"}',
          201,
        );
      });

      await repository.reply(1, 'Got it', replyToId: 42);

      expect(captured!.data, containsPair('reply_to_id', 42));
    });

    test(
      'omits reply_to_id when no quote is given, rather than sending null',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json(
            '{"id": 99, "text": "Hi", "direction": "OUTBOUND", '
            '"sent_at": "2026-01-01T00:00:00Z"}',
            201,
          );
        });

        await repository.reply(1, 'Hi');

        expect(
          (captured!.data as Map).containsKey('reply_to_id'),
          isFalse,
          reason:
              'the backend documents omission and null differently for some '
              'fields; sending nothing when nothing was quoted is the safe '
              'default',
        );
      },
    );
  });

  group('Message.pending with a quote', () {
    test('carries the quote through as replyTo, marked sending', () {
      final quoted = QuotedMessage(id: 42, text: 'Original text');
      final pending = Message.pending(
        localId: 'local-1',
        text: 'My reply',
        senderName: 'Agent',
        senderInitials: 'A',
        replyTo: quoted,
      );

      expect(pending.replyTo, quoted);
      expect(pending.sendState, SendState.sending);
      expect(pending.id, lessThan(0), reason: 'optimistic ids are negative');
    });

    test('has no quote when none was given', () {
      final pending = Message.pending(
        localId: 'local-1',
        text: 'My reply',
        senderName: 'Agent',
        senderInitials: 'A',
      );

      expect(pending.replyTo, isNull);
    });
  });

  group('ConversationState/failed-message quote preservation', () {
    // ConversationController.retry() passes `failed.replyTo` straight through
    // to send()'s new `replyTo` parameter — exercised here at the model
    // level, the same boundary other ConversationState mutations are tested
    // at (message_deletion_test.dart, realtime_bridge_test.dart), since
    // driving the real AsyncNotifier requires stubbing the full
    // detail/messages fetch cascade its build() triggers.
    test('a failed quoted message keeps its quote after copyWith(failed)', () {
      final quoted = QuotedMessage(id: 42, text: 'Original text');
      final pending = Message.pending(
        localId: 'local-1',
        text: 'My reply',
        senderName: 'Agent',
        senderInitials: 'A',
        replyTo: quoted,
      );

      final failed = pending.copyWith(
        sendState: SendState.failed,
        deliveryError: 'No connection.',
      );

      expect(failed.replyTo, quoted);
    });
  });

  group('Conversation model unaffected by reply changes (sanity)', () {
    test('Conversation.fromJson still parses without a reply_to anywhere', () {
      final convo = Conversation.fromJson({
        'id': 1,
        'customer': {'id': 100, 'display_name': 'Test Customer'},
        'provider': 'WHATSAPP',
        'status': 'OPEN',
        'priority': 'NORMAL',
        'unread_count': 0,
        'message_count': 1,
        'last_message_preview': 'Hello',
      });

      expect(convo.id, 1);
    });
  });
}
