/// Channel mute/unmute/test/disconnect/check-status/connect-another:
/// `ChannelConnection`/`ChannelTestResult`/`ChannelConnectionState`/
/// `WhatsAppChannelStatus`/`ChannelAuthorizationUrl` model parsing, and every
/// `DirectoryRepository` method the Channels settings card calls.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/features/directory/directory_repository.dart';

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

DirectoryRepository _repositoryReturning(
  ResponseBody Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return DirectoryRepository(client);
}

const _fullChannelJson = '''
{
  "id": 5,
  "provider": "WHATSAPP",
  "display_name": "Support line",
  "status": "CONNECTED",
  "is_active": true,
  "status_detail": "",
  "conversation_count": 12,
  "is_muted": true,
  "muted_at": "2026-08-20T09:00:00Z",
  "muted_by_name": "Mona"
}
''';

void main() {
  group('ChannelConnection.fromJson', () {
    test('parses the muting fields', () {
      final channel = ChannelConnection.fromJson({
        'id': 5,
        'provider': 'WHATSAPP',
        'is_muted': true,
        'muted_at': '2026-08-20T09:00:00Z',
        'muted_by_name': 'Mona',
      });

      expect(channel.isMuted, isTrue);
      expect(channel.mutedByName, 'Mona');
      expect(channel.mutedAt, isNotNull);
    });

    test('defaults to not muted when the fields are absent', () {
      final channel = ChannelConnection.fromJson({
        'id': 5,
        'provider': 'WHATSAPP',
      });

      expect(channel.isMuted, isFalse);
      expect(channel.mutedByName, isEmpty);
      expect(channel.mutedAt, isNull);
    });
  });

  group('ChannelTestResult.fromJson', () {
    test('parses an ok:true result', () {
      final result = ChannelTestResult.fromJson({
        'ok': true,
        'detail': 'Connection verified.',
      });

      expect(result.ok, isTrue);
      expect(result.detail, 'Connection verified.');
    });

    test('parses an ok:false result without throwing', () {
      final result = ChannelTestResult.fromJson({
        'ok': false,
        'detail': 'Not implemented yet.',
      });

      expect(result.ok, isFalse);
      expect(result.detail, 'Not implemented yet.');
    });
  });

  group('DirectoryRepository.muteChannel / unmuteChannel', () {
    test('mute POSTs to the correct path and parses the response', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_fullChannelJson, 200);
      });

      final result = await repository.muteChannel(5);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/channels/5/mute/');
      expect(result.isMuted, isTrue);
      expect(result.mutedByName, 'Mona');
    });

    test('unmute POSTs to the correct path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_fullChannelJson, 200);
      });

      await repository.unmuteChannel(5);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/channels/5/unmute/');
    });
  });

  group('DirectoryRepository.testChannel', () {
    // The endpoint always answers 200 — even a failed liveness check is a
    // normal response, not an ApiException. This is the same category of
    // behavior the guide warns about for report-conversion.
    test('a 200 with ok:false does not throw an ApiException', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"ok": false, "detail": "WhatsApp adapter not implemented yet."}',
          200,
        ),
      );

      final result = await repository.testChannel(5);

      expect(result.ok, isFalse);
      expect(result.detail, 'WhatsApp adapter not implemented yet.');
    });

    test('a 200 with ok:true parses as a success', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('{"ok": true, "detail": "Connection verified."}', 200);
      });

      final result = await repository.testChannel(5);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/channels/5/test/');
      expect(result.ok, isTrue);
    });

    test('a real error status still throws ApiException', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
          403,
        ),
      );

      expect(() => repository.testChannel(5), throwsA(isA<Exception>()));
    });
  });

  group('ChannelConnection.fromJson — extended fields', () {
    test('parses every field the live schema documents', () {
      final channel = ChannelConnection.fromJson({
        'id': 5,
        'provider': 'WHATSAPP',
        'provider_display': 'WhatsApp Business',
        'display_name': 'Support line',
        'external_account_id': '1234567890',
        'avatar_url': '',
        'status': 'CONNECTED',
        'is_active': true,
        'status_detail': '',
        'conversation_count': 12,
        'is_muted': false,
        'has_credentials': true,
        'is_operational': true,
        'token_expires_at': '2026-12-01T00:00:00Z',
        'token_days_remaining': 45,
        'connected_at': '2026-06-01T09:00:00Z',
        'last_sync_at': '2026-09-01T09:00:00Z',
        'last_message_at': '2026-09-02T09:00:00Z',
      });

      expect(channel.providerDisplay, 'WhatsApp Business');
      expect(channel.externalAccountId, '1234567890');
      expect(channel.hasCredentials, isTrue);
      expect(channel.isOperational, isTrue);
      expect(channel.tokenDaysRemaining, 45);
      expect(channel.tokenExpiresAt, isNotNull);
      expect(channel.connectedAt, isNotNull);
      expect(channel.lastSyncAt, isNotNull);
      expect(channel.lastMessageAt, isNotNull);
    });

    test('defaults extended fields safely when absent', () {
      final channel = ChannelConnection.fromJson({
        'id': 5,
        'provider': 'WHATSAPP',
      });

      expect(channel.providerDisplay, isEmpty);
      expect(channel.externalAccountId, isEmpty);
      expect(channel.hasCredentials, isFalse);
      expect(channel.isOperational, isFalse);
      expect(channel.tokenDaysRemaining, isNull);
      expect(channel.connectedAt, isNull);
      expect(channel.lastMessageAt, isNull);
    });
  });

  group('ChannelConnectionState.fromJson', () {
    test('parses the disconnect response shape', () {
      final state = ChannelConnectionState.fromJson({
        'status': 'DISCONNECTED',
        'detail': 'Credential removed.',
      });

      expect(state.status, 'DISCONNECTED');
      expect(state.detail, 'Credential removed.');
    });
  });

  group('WhatsAppChannelStatus.fromJson', () {
    test('parses the check-status response shape', () {
      final status = WhatsAppChannelStatus.fromJson({
        'id': 5,
        'display_name': 'Support line',
        'status': 'CONNECTED',
        'detail': 'Ready to send and receive.',
      });

      expect(status.id, 5);
      expect(status.status, 'CONNECTED');
      expect(status.detail, 'Ready to send and receive.');
    });
  });

  group('ChannelAuthorizationUrl.fromJson', () {
    test('parses the authorization_url field', () {
      final result = ChannelAuthorizationUrl.fromJson({
        'authorization_url': 'https://www.facebook.com/dialog/oauth?x=1',
      });

      expect(result.url, 'https://www.facebook.com/dialog/oauth?x=1');
    });

    test('defaults to empty string when absent', () {
      final result = ChannelAuthorizationUrl.fromJson({});
      expect(result.url, isEmpty);
    });
  });

  group('DirectoryRepository — provider disconnect', () {
    test('disconnectWhatsApp POSTs to the WhatsApp disconnect path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
      });

      final result = await repository.disconnectWhatsApp(5);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/whatsapp/5/disconnect/');
      expect(captured!.data, isNull);
      expect(result.status, 'DISCONNECTED');
    });

    test(
      'disconnectInstagram POSTs to the Instagram disconnect path',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
        });

        await repository.disconnectInstagram(7);

        expect(captured!.method, 'POST');
        expect(captured!.path, '/integrations/instagram/7/disconnect/');
      },
    );

    test('disconnectMeta POSTs to the Meta disconnect path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
      });

      await repository.disconnectMeta(9);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/meta/9/disconnect/');
    });

    test('disconnectTikTok POSTs to the TikTok disconnect path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('{"status": "DISCONNECTED", "detail": "ok"}', 200);
      });

      await repository.disconnectTikTok(11);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/tiktok/11/disconnect/');
    });

    test('a 403 from any disconnect throws ApiException', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
          403,
        ),
      );

      expect(() => repository.disconnectWhatsApp(5), throwsA(isA<Exception>()));
    });
  });

  group('DirectoryRepository.checkWhatsAppStatus', () {
    test('POSTs to the WhatsApp check-status path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json('''
{
  "id": 5,
  "display_name": "Support line",
  "status": "CONNECTED",
  "detail": "Ready to send and receive."
}
''', 200);
      });

      final result = await repository.checkWhatsAppStatus(5);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/whatsapp/5/check-status/');
      expect(result.status, 'CONNECTED');
    });
  });

  group('DirectoryRepository — connect-another authorization URLs', () {
    test(
      'startWhatsAppEmbeddedSignupMobile POSTs to the mobile/start path',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json(
            '{"authorization_url": "https://business.facebook.com/wa/signup?x=1"}',
            200,
          );
        });

        final result = await repository.startWhatsAppEmbeddedSignupMobile();

        expect(captured!.method, 'POST');
        expect(
          captured!.path,
          '/integrations/whatsapp/embedded-signup/mobile/start/',
        );
        expect(result.url, 'https://business.facebook.com/wa/signup?x=1');
      },
    );

    test('authorizeInstagram POSTs to the Instagram authorize path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"authorization_url": "https://instagram.com/oauth/authorize?x=1"}',
          200,
        );
      });

      final result = await repository.authorizeInstagram();

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/instagram/authorize/');
      expect(result.url, 'https://instagram.com/oauth/authorize?x=1');
    });

    test('connectMeta POSTs to the Meta connect path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"authorization_url": "https://www.facebook.com/dialog/oauth?x=1"}',
          200,
        );
      });

      final result = await repository.connectMeta();

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/meta/connect/');
      expect(result.url, 'https://www.facebook.com/dialog/oauth?x=1');
    });

    test('authorizeTikTok POSTs to the TikTok authorize path', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"authorization_url": "https://www.tiktok.com/v2/auth/authorize?x=1"}',
          200,
        );
      });

      final result = await repository.authorizeTikTok();

      expect(captured!.method, 'POST');
      expect(captured!.path, '/integrations/tiktok/authorize/');
      expect(result.url, 'https://www.tiktok.com/v2/auth/authorize?x=1');
    });
  });
}
