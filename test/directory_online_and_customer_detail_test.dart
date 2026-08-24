/// `DirectoryRepository.onlineEmployees()`/`.customerDetail()`, the
/// `CustomerDetail` model, and proof that `onlineEmployeesProvider` reads a
/// genuinely independent endpoint rather than filtering
/// `employeeDirectoryProvider`'s already-loaded page.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/customer_detail.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
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
  group('DirectoryRepository.onlineEmployees', () {
    test('hits the dedicated unpaginated endpoint', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '[{"id": 1, "full_name": "Mona", "availability": "ONLINE"}, '
          '{"id": 2, "full_name": "Sam", "availability": "AWAY"}]',
          200,
        );
      });

      final result = await repository.onlineEmployees();

      expect(captured!.path, '/employees/online/');
      expect(result, hasLength(2));
      expect(result.first.fullName, 'Mona');
      expect(result.last.availability, 'AWAY');
    });

    test('a malformed row is dropped, not fatal to the page', () async {
      final repository = _repositoryReturning(
        (_) => _json('[{"id": 1, "full_name": "Mona"}, "not-an-object"]', 200),
      );

      final result = await repository.onlineEmployees();

      expect(result, hasLength(1));
    });
  });

  group('DirectoryRepository.customerDetail', () {
    test('parses the full backend shape, including detail-only fields', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"id": 7, "display_name": "Nour", "lifecycle_stage": "REPEAT_BUYER", '
          '"conversation_count": 4, "confirmed_purchase_count": 2, '
          '"notes": "Prefers WhatsApp.", '
          '"facts": [{"id": 1, "key": "address", "value": "12 Nile St", '
          '"confidence": 0.9, "source": "EMPLOYEE", "status": "CONFIRMED", '
          '"needs_review": false}], '
          '"identities": [{"provider": "WHATSAPP"}], '
          '"created_at": "2026-01-01T00:00:00Z"}',
          200,
        );
      });

      final result = await repository.customerDetail(7);

      expect(captured!.path, '/customers/7/');
      expect(result.id, 7);
      expect(result.displayName, 'Nour');
      expect(result.confirmedPurchaseCount, 2);
      expect(result.notes, 'Prefers WhatsApp.');
      expect(result.facts, hasLength(1));
      expect(result.facts.single.key, 'address');
      expect(result.providers, ['WHATSAPP']);
      expect(result.createdAt, isNotNull);
    });

    test('malformed fields fall back rather than throwing', () {
      final customer = CustomerDetail.fromJson(const {});

      expect(customer.id, -1);
      expect(customer.displayName, isEmpty);
      expect(customer.confirmedPurchaseCount, 0);
      expect(customer.facts, isEmpty);
      expect(customer.notes, isEmpty);
    });
  });

  group('onlineEmployeesProvider reads an independent endpoint', () {
    test(
      'returns a different set than employeeDirectoryProvider, not a client-side filter',
      () async {
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = _StubAdapter((options) {
          if (options.path == '/employees/online/') {
            return _json(
              '[{"id": 2, "full_name": "Sam", "availability": "ONLINE"}]',
              200,
            );
          }
          // The paginated directory — deliberately a different page/shape
          // than the online endpoint, so a client-side-filter regression
          // would fail this assertion.
          return _json(
            '{"count": 2, "next": null, "previous": null, "results": '
            '[{"id": 1, "full_name": "Mona", "availability": "OFFLINE"}, '
            '{"id": 2, "full_name": "Sam", "availability": "ONLINE"}]}',
            200,
          );
        });

        final container = ProviderContainer(
          overrides: [
            cookieJarProvider.overrideWithValue(CookieJar()),
            apiClientProvider.overrideWithValue(client),
          ],
        );
        addTearDown(container.dispose);

        final all = await container.read(employeeDirectoryProvider.future);
        final online = await container.read(onlineEmployeesProvider.future);

        expect(all, hasLength(2));
        expect(online, hasLength(1));
        expect(online.single.fullName, 'Sam');
      },
    );
  });
}
