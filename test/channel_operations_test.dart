/// Channel mute/unmute/test: `ChannelConnection`/`ChannelTestResult` model
/// parsing and `DirectoryRepository.muteChannel()`/`.unmuteChannel()`/
/// `.testChannel()`.
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
}
