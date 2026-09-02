/// Directory management: `DirectoryRepository.updateCustomer()`,
/// `.createEmployee()`, `.updateEmployee()`, `.deactivateEmployee()`,
/// `.createTeam()` — request paths, request bodies, response parsing, and
/// 400/403/404 handling. Also covers the `DirectoryEmployee.teamIds`/
/// `.maxOpenChats` and `CustomerDetail.tags` parsing these methods rely on.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets, the same
/// shape as `channel_operations_test.dart` and
/// `directory_online_and_customer_detail_test.dart`.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/customer_detail.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/features/directory/directory_repository.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

const _fullEmployeeJson = '''
{
  "id": 9,
  "public_id": "11111111-1111-1111-1111-111111111111",
  "email": "new.hire@acme.test",
  "first_name": "New",
  "last_name": "Hire",
  "full_name": "New Hire",
  "initials": "NH",
  "role": "AGENT",
  "role_display": "Agent",
  "availability": "OFFLINE",
  "avatar_url": "",
  "phone": "",
  "title": "",
  "is_active": true,
  "teams": [{"id": 3, "name": "Support", "color": "#0F766E"}],
  "last_seen_at": null,
  "max_open_chats": 8,
  "effective_capacity": 8,
  "routing_blocker": "",
  "is_routing_ready": true,
  "working_hours": [],
  "work_schedule": null,
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-01T00:00:00Z"
}
''';

void main() {
  group('DirectoryEmployee.fromJson — fields the write endpoints add', () {
    test('parses team ids alongside team names', () {
      final employee = DirectoryEmployee.fromJson({
        'id': 1,
        'full_name': 'Mona',
        'teams': [
          {'id': 3, 'name': 'Support'},
          {'id': 4, 'name': 'Sales'},
        ],
      });

      expect(employee.teamIds, [3, 4]);
      expect(employee.teamNames, ['Support', 'Sales']);
    });

    test('parses max_open_chats, defaulting to null rather than 0', () {
      expect(
        DirectoryEmployee.fromJson({
          'id': 1,
          'max_open_chats': 12,
        }).maxOpenChats,
        12,
      );
      expect(DirectoryEmployee.fromJson({'id': 1}).maxOpenChats, isNull);
    });

    test('a malformed teams entry is dropped rather than throwing', () {
      final employee = DirectoryEmployee.fromJson({
        'id': 1,
        'teams': [
          {'id': 3, 'name': 'Support'},
          'not-an-object',
          {'name': 'no id here'},
        ],
      });

      expect(employee.teamIds, [3]);
      expect(employee.teamNames, ['Support', 'no id here']);
    });
  });

  group('CustomerDetail.fromJson — tags', () {
    test('parses the tags string', () {
      final customer = CustomerDetail.fromJson({
        'id': 1,
        'tags': 'vip, wholesale',
      });
      expect(customer.tags, 'vip, wholesale');
    });

    test('defaults to empty rather than throwing when absent', () {
      expect(CustomerDetail.fromJson(const {}).tags, isEmpty);
    });
  });

  group('DirectoryRepository.updateCustomer', () {
    test('PATCHes the correct path with the given body and parses the '
        'full detail response', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"id": 7, "display_name": "Nour Updated", "tags": "vip"}',
          200,
        );
      });

      final result = await repository.updateCustomer(7, {
        'display_name': 'Nour Updated',
      });

      expect(captured!.method, 'PATCH');
      expect(captured!.path, '/customers/7/');
      expect(captured!.data, {'display_name': 'Nour Updated'});
      expect(result.displayName, 'Nour Updated');
      expect(result.tags, 'vip');
    });

    test(
      'a 400 validation error throws ApiException with the server message',
      () {
        final repository = _repositoryReturning(
          (_) => _json(
            '{"error": {"code": "invalid", "message": "Invalid lifecycle stage.", "details": {}}}',
            400,
          ),
        );

        expect(
          () => repository.updateCustomer(7, {'lifecycle_stage': 'NOT_REAL'}),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Invalid lifecycle stage.',
            ),
          ),
        );
      },
    );

    test('a 403 throws ApiException with isForbidden true', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
          403,
        ),
      );

      expect(
        () => repository.updateCustomer(7, {'display_name': 'x'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });

    test('a 404 throws ApiException with isNotFound true', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "not_found", "message": "Not found.", "details": {}}}',
          404,
        ),
      );

      expect(
        () => repository.updateCustomer(999, {'display_name': 'x'}),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', isTrue),
        ),
      );
    });
  });

  group('DirectoryRepository.createEmployee', () {
    test('POSTs to /employees/ with the given body and parses the response '
        'as DirectoryEmployee', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_fullEmployeeJson, 201);
      });

      final body = {
        'email': 'new.hire@acme.test',
        'first_name': 'New',
        'last_name': 'Hire',
        'role': 'AGENT',
        'availability': 'OFFLINE',
        'is_active': true,
        'password': 'correct horse battery staple',
        'team_ids': <int>[3],
      };
      final result = await repository.createEmployee(body);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/employees/');
      expect(captured!.data, body);
      expect(result.email, 'new.hire@acme.test');
      expect(result.fullName, 'New Hire');
      expect(result.teamIds, [3]);
      expect(result.maxOpenChats, 8);
    });

    test('a duplicate-email 400 surfaces the backend message', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "invalid", "message": "This email is already in use.", "details": {}}}',
          400,
        ),
      );

      expect(
        () => repository.createEmployee({'email': 'dup@acme.test'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'This email is already in use.',
          ),
        ),
      );
    });

    test('a non-admin 403 throws ApiException', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Admins only.", "details": {}}}',
          403,
        ),
      );

      expect(
        () => repository.createEmployee({'email': 'x@acme.test'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });
  });

  group('DirectoryRepository.updateEmployee', () {
    test('PATCHes /employees/{id}/ with only the given fields', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_fullEmployeeJson, 200);
      });

      await repository.updateEmployee(9, {'availability': 'ONLINE'});

      expect(captured!.method, 'PATCH');
      expect(captured!.path, '/employees/9/');
      expect(captured!.data, {'availability': 'ONLINE'});
    });

    test('a 404 for an out-of-organization id throws ApiException', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "not_found", "message": "Not found.", "details": {}}}',
          404,
        ),
      );

      expect(
        () => repository.updateEmployee(999, {'role': 'ADMIN'}),
        throwsA(
          isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', isTrue),
        ),
      );
    });
  });

  group('DirectoryRepository.deactivateEmployee', () {
    test(
      'DELETEs /employees/{id}/ and parses an is_active: false response',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json(
            '{"id": 9, "full_name": "New Hire", "is_active": false}',
            200,
          );
        });

        final result = await repository.deactivateEmployee(9);

        expect(captured!.method, 'DELETE');
        expect(captured!.path, '/employees/9/');
        expect(result.isActive, isFalse);
      },
    );

    test('self-deactivation comes back as a 400, handled as a normal '
        'ApiException rather than a permission failure', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "invalid", "message": "You cannot deactivate your own account.", "details": {}}}',
          400,
        ),
      );

      expect(
        () => repository.deactivateEmployee(1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.isForbidden, 'isForbidden', isFalse)
              .having(
                (e) => e.message,
                'message',
                'You cannot deactivate your own account.',
              ),
        ),
      );
    });
  });

  group('DirectoryRepository.createTeam', () {
    test('POSTs to /teams/ with member_ids/leader_ids and reuses '
        'Team.fromJson for the response', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"id": 5, "name": "VIP desk", "description": "", "language": "en", '
          '"color": "#0F766E", "is_active": true, '
          '"members": [{"id": 1, "full_name": "Mona"}, {"id": 2, "full_name": "Sam"}], '
          '"leaders": [{"id": 1, "full_name": "Mona"}], '
          '"member_count": 2, "created_at": "2026-01-01T00:00:00Z", '
          '"updated_at": "2026-01-01T00:00:00Z"}',
          201,
        );
      });

      final body = {
        'name': 'VIP desk',
        'is_active': true,
        'member_ids': [1, 2],
        'leader_ids': [1],
      };
      final result = await repository.createTeam(body);

      expect(captured!.method, 'POST');
      expect(captured!.path, '/teams/');
      expect(captured!.data, body);
      expect(result.name, 'VIP desk');
      expect(result.memberCount, 2);
      expect(result.leaderNames, ['Mona']);
    });

    test('a validation 400 (e.g. blank name) surfaces the backend message', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "invalid", "message": "This field may not be blank.", "details": {}}}',
          400,
        ),
      );

      expect(
        () => repository.createTeam({'name': ''}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'This field may not be blank.',
          ),
        ),
      );
    });

    test('a non-admin 403 throws ApiException', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Admins only.", "details": {}}}',
          403,
        ),
      );

      expect(
        () => repository.createTeam({'name': 'New team'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });
  });

  group('DirectoryRepository.updateTeam', () {
    test('PATCHes /teams/{id}/ with only the given fields', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(
          '{"id": 5, "name": "VIP desk updated", "description": "High tier", '
          '"language": "en", "color": "#0F766E", "is_active": true, '
          '"members": [{"id": 1, "full_name": "Mona"}], "leaders": [], '
          '"member_count": 1, "created_at": "2026-01-01T00:00:00Z", '
          '"updated_at": "2026-01-01T00:00:00Z"}',
          200,
        );
      });

      final body = {'name': 'VIP desk updated', 'description': 'High tier'};
      final result = await repository.updateTeam(5, body);

      expect(captured!.method, 'PATCH');
      expect(captured!.path, '/teams/5/');
      expect(captured!.data, body);
      expect(result.name, 'VIP desk updated');
      expect(result.description, 'High tier');
      expect(result.memberIds, [1]);
    });

    test('a 404 for a missing team throws ApiException', () {
      final repository = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "not_found", "message": "Not found.", "details": {}}}',
          404,
        ),
      );

      expect(
        () => repository.updateTeam(999, {'name': 'Ghost team'}),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', 'Not found.'),
        ),
      );
    });
  });

  group('DirectoryRepository.deactivateTeam', () {
    test(
      'DELETEs /teams/{id}/ and parses an is_active: false response',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json(
            '{"id": 5, "name": "VIP desk", "is_active": false, "members": [], '
            '"leaders": [], "member_count": 0}',
            200,
          );
        });

        final result = await repository.deactivateTeam(5);

        expect(captured!.method, 'DELETE');
        expect(captured!.path, '/teams/5/');
        expect(result.isActive, isFalse);
      },
    );
  });
}
