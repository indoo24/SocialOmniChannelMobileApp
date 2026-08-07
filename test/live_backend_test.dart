/// Vertical slice against the **real running backend**.
///
/// Not a mock. This drives the actual client code — cookie jar, CSRF
/// interceptor, repositories, models — against Django on 127.0.0.1:8000 and
/// asserts the whole path the first milestone specifies:
///
///     login → session → employee → conversations → messages → reply
///
/// Skipped automatically when the backend is not reachable, so the ordinary
/// `flutter test` run stays hermetic:
///
///     flutter test test/live_backend_test.dart \
///       --dart-define=SCENARIO_API_HOST=127.0.0.1:8000 \
///       --dart-define=SCENARIO_LIVE=1
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/auth/auth_repository.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';

const _live = bool.fromEnvironment('SCENARIO_LIVE');
const _email = String.fromEnvironment(
  'SCENARIO_LIVE_EMAIL',
  defaultValue: 'admin@scenario.demo',
);
const _password = String.fromEnvironment('SCENARIO_LIVE_PASSWORD');

/// SecureStore needs platform channels; the live check only needs the API.
class _NoopStore implements SecureStore {
  @override
  Future<void> writeLastEmail(String email) async {}
  @override
  Future<String?> readLastEmail() async => null;
  @override
  Future<String> deviceId() async => 'test-device';
  @override
  Future<void> clearSession() async {}
  @override
  Future<void> wipe() async {}
}

void main() {
  if (!_live) {
    test('live backend slice (skipped — pass --dart-define=SCENARIO_LIVE=1)',
        () {}, skip: true);
    return;
  }

  late ApiClient api;
  late AuthRepository auth;
  late ConversationRepository conversations;

  setUpAll(() {
    api = ApiClient.create(cookieJar: CookieJar());
    auth = AuthRepository(api: api, store: _NoopStore());
    conversations = ConversationRepository(api);
  });

  test('logs in and loads the employee with real permissions', () async {
    final employee = await auth.login(email: _email, password: _password);

    expect(employee.id, greaterThan(0));
    expect(employee.email, _email);
    expect(employee.permissions, isNotEmpty);
    expect(employee.visibilityScope, isNotEmpty);
    // ignore: avoid_print
    print('  employee: ${employee.fullName} (${employee.role}), '
        '${employee.permissions.length} permissions, '
        'scope=${employee.visibilityScope}');
  });

  test('the session restores from the cookie jar', () async {
    expect(await api.hasSessionCookie(), isTrue);

    final restored = await auth.restore();

    expect(restored, isNotNull);
    expect(restored!.email, _email);
  });

  test('loads the conversations this employee can actually see', () async {
    final page = await conversations.list();

    // ignore: avoid_print
    print('  visible conversations: ${page.count}');
    expect(page.results.length, lessThanOrEqualTo(page.count));
    for (final conversation in page.results) {
      expect(conversation.id, greaterThan(0));
      expect(conversation.customer.displayName, isNotEmpty);
    }
  });

  test('opens a real conversation and loads its message history', () async {
    final page = await conversations.list();
    if (page.results.isEmpty) {
      markTestSkipped('no conversations in the dev database');
      return;
    }

    final target = page.results.first;
    final detail = await conversations.detail(target.id);
    final messages = await conversations.messages(target.id);

    expect(detail.id, target.id);
    // ignore: avoid_print
    print('  conversation #${detail.id} "${detail.customer.displayName}" '
        '— ${messages.count} messages, provider=${detail.provider}');
    for (final message in messages.results) {
      expect(message.sentAt, isA<DateTime>());
    }
  });

  test('sends a real reply through the backend', () async {
    final page = await conversations.list(
      filters: const ConversationFilters(provider: 'MOCK'),
    );
    if (page.results.isEmpty) {
      markTestSkipped('no MOCK-channel conversation to reply on safely');
      return;
    }

    final target = page.results.first;
    final before = await conversations.messages(target.id);

    final sent = await conversations.reply(
      target.id,
      'Mobile client verification ${DateTime.now().toIso8601String()}',
    );

    expect(sent.id, greaterThan(0));
    expect(sent.isOutbound, isTrue);

    final after = await conversations.messages(target.id);
    expect(after.count, greaterThan(before.count));
    // ignore: avoid_print
    print('  reply #${sent.id} accepted, status=${sent.deliveryStatus}, '
        'thread ${before.count} → ${after.count}');
  });

  test('logs out and the session stops working', () async {
    await auth.logout();

    expect(await api.hasSessionCookie(), isFalse);
    expect(await auth.restore(), isNull);
  });
}
