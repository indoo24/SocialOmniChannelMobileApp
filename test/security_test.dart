/// Regression tests for the security hardening pass.
///
/// Each group pins one specific vulnerability shut. They are written against
/// the behaviour an attacker would exploit rather than against the
/// implementation, so a refactor that preserves the property keeps passing and
/// one that quietly drops it fails.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/config/dev_tls_overrides.dart';
import 'package:scenario_mobile/core/config/environment.dart';
import 'package:scenario_mobile/core/logging/app_log.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/security/screen_security.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';
import 'package:scenario_mobile/core/utils/json_safe.dart';
import 'package:scenario_mobile/core/utils/safe_url.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TLS bypass is not reachable from a release build', () {
    test('installation is driven by the build gate, not the env name', () {
      // Tests run in debug, so this environment does permit the bypass. The
      // property under test is that `shouldInstall` derives from
      // `allowsDevTlsBypass` rather than from the environment name alone —
      // the latter is what made a default-configured release build trust any
      // certificate presented for the default host.
      expect(
        DevTlsOverrides.shouldInstall,
        Environment.current.allowsDevTlsBypass,
      );
    });

    test('the bypass requires a non-release build as well as a dev env', () {
      final env = Environment.current;

      if (env.allowsDevTlsBypass) {
        expect(env.isDevelopment, isTrue);
        expect(env.isReleaseBuild, isFalse);
      }

      // The security-relevant direction: a release build may never permit it,
      // whatever SCENARIO_ENV was set to.
      expect(env.isReleaseBuild && env.allowsDevTlsBypass, isFalse);
    });

    test('a release build can never be configured for cleartext', () {
      final env = Environment.current;

      expect(env.isReleaseBuild && !env.useTls, isFalse);

      if (env.useTls) {
        expect(env.apiBaseUrl, startsWith('https://'));
        expect(env.websocketUrl, startsWith('wss://'));
      }
    });

    test('developer affordances are withheld from release builds', () {
      final env = Environment.current;
      expect(env.isReleaseBuild && env.showsDeveloperAffordances, isFalse);
    });
  });

  group('server-supplied image URLs', () {
    test('https is accepted unchanged', () {
      expect(
        SafeUrl.forImage('https://cdn.example.com/a.jpg'),
        'https://cdn.example.com/a.jpg',
      );
    });

    test('cleartext http is rejected against a TLS backend', () {
      // The beaconing case: a customer-controlled avatar URL arriving over a
      // channel and pointing at an attacker's host, fetched by the agent's
      // device the moment the conversation is opened.
      expect(SafeUrl.forImage('http://attacker.example/track.png'), '');
    });

    test('non-network schemes are rejected', () {
      const hostile = [
        'file:///data/data/com.scenario.scenario_mobile/files/.cookies/c',
        'data:image/png;base64,iVBORw0KGgo=',
        'javascript:alert(1)',
        'content://com.android.providers/media/1',
      ];

      for (final url in hostile) {
        expect(SafeUrl.forImage(url), '', reason: 'must reject $url');
      }
    });

    test('malformed and empty values degrade to no image', () {
      expect(SafeUrl.forImage(null), '');
      expect(SafeUrl.forImage(''), '');
      expect(SafeUrl.forImage('   '), '');
      expect(SafeUrl.forImage('not a url'), '');
      expect(SafeUrl.forImage('https://'), '');
    });
  });

  group('untrusted JSON cannot crash a parse', () {
    test('an id of the wrong type does not throw', () {
      final hostile = <Object?>[null, 'abc', true, <Object>[], <String, Object>{}];

      for (final bad in hostile) {
        expect(
          () => Message.fromJson({'id': bad, 'text': 'hi'}),
          returnsNormally,
          reason: 'id=$bad must not throw',
        );
      }
    });

    test('a numeric-string id is still read as that id', () {
      expect(Message.fromJson({'id': '42'}).id, 42);
      expect(Message.fromJson({'id': 42}).id, 42);
    });

    test('an unparseable id is a sentinel, not a collision with row 0', () {
      expect(Message.fromJson({'id': null}).id, -1);
    });

    test('a non-list attachments field yields no attachments', () {
      expect(
        () => Message.fromJson({'id': 1, 'attachments': 'nope'}),
        returnsNormally,
      );
      expect(
        Message.fromJson({'id': 1, 'attachments': 'nope'}).attachments,
        isEmpty,
      );
    });

    test('non-object attachment elements are dropped, not fatal', () {
      final message = Message.fromJson({
        'id': 1,
        'attachments': <Object?>[
          'garbage',
          42,
          null,
          {'type': 'IMAGE', 'url': 'https://cdn.example.com/a.jpg'},
        ],
      });

      expect(message.attachments, hasLength(1));
      expect(message.attachments.single.url, 'https://cdn.example.com/a.jpg');
    });

    test('one malformed row does not empty a whole page', () {
      final page = Paginated.fromJson({
        'results': <Object?>[
          {'id': 1, 'text': 'ok'},
          'not an object',
          {'id': 2, 'text': 'also ok'},
        ],
        'count': 3,
      }, Message.fromJson);

      expect(page.results, hasLength(2));
      expect(page.results.map((m) => m.id), [1, 2]);
    });

    test('a count arriving as a string is still read', () {
      final page = Paginated.fromJson(
        {'results': const <Object?>[], 'count': '17'},
        Message.fromJson,
      );

      expect(page.count, 17);
    });
  });

  group('JsonSafe', () {
    test('asInt converts only what is unambiguous', () {
      expect(JsonSafe.asInt(5), 5);
      expect(JsonSafe.asInt('5'), 5);
      expect(JsonSafe.asInt(' 5 '), 5);
      expect(JsonSafe.asInt(5.0), 5);
      expect(JsonSafe.asInt('five', fallback: -1), -1);
      expect(JsonSafe.asInt(true, fallback: -1), -1);
      expect(JsonSafe.asInt(null, fallback: -1), -1);
      expect(JsonSafe.asInt(double.nan, fallback: -1), -1);
    });

    test('asMap normalises a dynamic-keyed map', () {
      final result = JsonSafe.asMap(<dynamic, dynamic>{'a': 1, 2: 'b'});

      expect(result['a'], 1);
      expect(result['2'], 'b');
    });

    test('asMap returns empty for non-maps rather than throwing', () {
      expect(JsonSafe.asMap('x'), isEmpty);
      expect(JsonSafe.asMap(null), isEmpty);
      expect(JsonSafe.asMap(<Object>[1, 2]), isEmpty);
    });

    test('parseList skips elements whose parser throws', () {
      final out = JsonSafe.parseList<int>(
        <Object?>[
          {'v': 1},
          {'v': 'boom'},
          {'v': 3},
        ],
        (m) => m['v'] as int,
      );

      expect(out, [1, 3]);
    });
  });

  group('log redaction', () {
    test('an email keeps its domain and loses the person', () {
      expect(AppLog.redactEmail('agent.name@company.com'), '***@company.com');
      expect(AppLog.redactEmail(''), 'null');
      expect(AppLog.redactEmail('malformed'), '<redacted>');
    });

    test('a redacted value never contains the whole original', () {
      const token = 'fcm-token-abcdefghijklmnop';
      final out = AppLog.redact(token);

      expect(out, isNot(contains('abcdefghijklmnop')));
      expect(out.length, lessThan(token.length));
    });

    test('a short value is not partially revealed', () {
      expect(AppLog.redact('secret'), '<redacted:6>');
    });

    test('a URI keeps scheme/host/path and drops the query', () {
      final uri = Uri.parse(
        'https://api.example.com/api/conversations/?search=%2B44700900123&page=2',
      );
      final out = AppLog.redactUri(uri);

      expect(out, 'https://api.example.com/api/conversations/');
      expect(out, isNot(contains('44700900123')));
      expect(out, isNot(contains('search')));
    });
  });

  group('device identifier', () {
    late Map<String, String> storage;

    setUp(() {
      // flutter_secure_storage speaks over a platform channel that has no
      // implementation in the test host; standing in for it exercises the real
      // SecureStore code path rather than a hand-written double.
      storage = <String, String>{};

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = Map<String, dynamic>.from(
            (call.arguments as Map).cast<String, dynamic>(),
          );
          switch (call.method) {
            case 'read':
              return storage[args['key'] as String];
            case 'write':
              storage[args['key'] as String] = args['value'] as String;
              return null;
            case 'delete':
              storage.remove(args['key'] as String);
              return null;
            case 'deleteAll':
              storage.clear();
              return null;
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    test('is 128 unpredictable bits, stable for the installation', () async {
      // The previous implementation was install time plus Object().hashCode:
      // two calls in the same microsecond could collide, and an attacker who
      // knew roughly when the app was installed could narrow it to a small
      // search space.
      final store = SecureStore();
      final first = await store.deviceId();

      expect(RegExp(r'^mob-[0-9a-f]{32}$').hasMatch(first), isTrue,
          reason: 'got "$first"');

      // Stable across calls within one installation.
      expect(await store.deviceId(), first);
    });

    test('distinct across installations', () async {
      final seen = <String>{};

      for (var i = 0; i < 50; i++) {
        storage.clear();
        seen.add(await SecureStore().deviceId());
      }

      expect(seen, hasLength(50));
    });
  });

  group('screen security', () {
    setUp(ScreenSecurity.resetForTest);

    test('nested sensitive screens hold the flag until the last one leaves',
        () async {
      final calls = <bool>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScreenSecurity.channel, (call) async {
        if (call.method == 'setSecure') {
          calls.add((call.arguments as Map)['secure'] as bool);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenSecurity.channel, null);
      });

      // A conversation opens, then pushes customer details on top of itself.
      await ScreenSecurity.acquire();
      await ScreenSecurity.acquire();
      expect(calls, [true], reason: 'only the first acquire sets the flag');

      // Customer details pops; the conversation is still on screen.
      await ScreenSecurity.release();
      expect(calls, [true], reason: 'flag must survive the inner pop');

      await ScreenSecurity.release();
      expect(calls, [true, false], reason: 'the last release clears it');
    });

    test('a missing platform handler is survivable, not fatal', () async {
      // iOS today: no handler is registered. The app must keep working, it
      // simply does not get this defence.
      await expectLater(ScreenSecurity.acquire(), completes);
      await expectLater(ScreenSecurity.release(), completes);
    });
  });
}
