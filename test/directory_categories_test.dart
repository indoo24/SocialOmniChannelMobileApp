/// `DirectoryRepository.categories()` — `GET /api/categories/`.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
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

void main() {
  group('DirectoryRepository.categories', () {
    test('parses a plain, unpaginated array', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '[{"id": 1, "slug": "sales", "label": "Sales", "color": "#0F766E", '
          '"is_system": false, "is_active": true, "display_order": 1}, '
          '{"id": 2, "slug": "support", "label": "Support", "color": "#2563EB", '
          '"is_system": true, "is_active": true, "display_order": 2}]',
          200,
        );
      });

      final result = await repository.categories();

      expect(captured!.path, '/categories/');
      expect(result, hasLength(2));
      expect(result.first.id, 1);
      expect(result.first.label, 'Sales');
      expect(result.first.slug, 'sales');
      expect(result.first.color, '#0F766E');
      expect(result.last.label, 'Support');
    });

    test('a malformed row is dropped, not fatal to the page', () async {
      final repository = _repositoryReturning(
        (_) => _json(
          '[{"id": 1, "label": "Sales"}, "not-an-object", {"id": 3, "label": "VIP"}]',
          200,
        ),
      );

      final result = await repository.categories();

      expect(result, hasLength(2));
      expect(result.map((c) => c.id), [1, 3]);
    });

    test('an empty list is handled cleanly', () async {
      final repository = _repositoryReturning((_) => _json('[]', 200));

      final result = await repository.categories();

      expect(result, isEmpty);
    });
  });
}
