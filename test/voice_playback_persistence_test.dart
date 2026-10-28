/// Voice-note playback that outlives the bubble showing it.
///
/// The player belongs to `voicePlaybackProvider`, not to `VoiceNotePlayer`:
/// scrolling a playing note away (the message list disposes off-screen
/// bubbles — it has `addAutomaticKeepAlives: false`), opening an image,
/// visiting another screen or another conversation must leave the audio
/// playing, and a bubble built again must show the session where it is.
///
/// These run the real conversation screen over real `AudioPlayer` objects;
/// only the platform channel beneath them is the recording fake in
/// `support/fake_audioplayers.dart`, so creation, disposal, pauses and
/// listeners are counted where they actually happen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/session/session_reset.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/features/messages/voice_playback_service.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/fake_audioplayers.dart';

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

const _voiceA = 'https://cdn.example.com/voice-a.ogg';
const _voiceB = 'https://cdn.example.com/voice-b.ogg';

Map<String, dynamic> _detail(int id) => {
  'id': id,
  'customer': {'id': id, 'display_name': 'Customer $id', 'initials': 'C'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
};

Map<String, dynamic> _message(int id, {Map<String, dynamic>? attachment}) => {
  'id': id,
  'direction': 'INBOUND',
  'sender_type': 'CUSTOMER',
  'sender_name': 'Customer',
  'message_type': attachment == null ? 'TEXT' : attachment['type'],
  'text': attachment == null ? 'Message number $id, long enough to wrap' : '',
  'attachments': [?attachment],
  'delivery_status': 'DELIVERED',
  'sent_at': DateTime.utc(
    2026,
    9,
    4,
    10,
  ).add(Duration(minutes: id)).toIso8601String(),
};

Map<String, dynamic> _voice(String id, String url) => {
  'type': 'AUDIO',
  'id': id,
  'url': url,
  'mime_type': 'audio/ogg',
  'duration_ms': 7000,
};

/// Conversation 42: forty text messages, then an image, then two voice
/// notes at the bottom, newest last. Conversation 43: one text message.
class _Server implements HttpClientAdapter {
  /// When set, the recording fetches answer 404.
  bool audioMissing = false;
  final List<String> audioFetches = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final path = options.path;
    if (path == '/conversations/42/messages/') {
      return _json({
        'results': [
          for (var i = 1; i <= 40; i++) _message(i),
          _message(
            41,
            attachment: {
              'type': 'IMAGE',
              'id': 'img-1',
              'url': 'https://cdn.example.com/photo.jpg',
              'mime_type': 'image/jpeg',
              'file_name': 'photo.jpg',
            },
          ),
          _message(42, attachment: _voice('att-a', _voiceA)),
          _message(43, attachment: _voice('att-b', _voiceB)),
        ],
      });
    }
    if (path == '/conversations/43/messages/') {
      return _json({
        'results': [_message(1)],
      });
    }
    if (path.contains('/notes/')) return _json([]);
    if (path.contains('/saved-replies/')) return _json({'results': []});
    if (path == '/conversations/42/') return _json(_detail(42));
    if (path == '/conversations/43/') return _json(_detail(43));
    if (path == _voiceA || path == _voiceB) {
      audioFetches.add(path);
      if (audioMissing) {
        return _json({
          'error': {'code': 'not_found', 'message': 'gone'},
        }, 404);
      }
      return ResponseBody.fromBytes(List.filled(32, 1), 200);
    }
    return _json({});
  }

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

final _nav = GlobalKey<NavigatorState>();
final _list = find.byType(ListView).first;
final _pause = find.byIcon(Icons.pause);
final _play = find.byIcon(Icons.play_arrow);

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ProviderContainer> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        navigatorKey: _nav,
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await _frames(tester, 20);
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Taps the play button of the voice note whose time label reads [label]
/// (both read `0:07` until played, so [index] picks among them).
Future<void> _startPlaying(WidgetTester tester, {int index = 0}) async {
  await tester.tap(_play.at(index));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (_pause.evaluate().isNotEmpty) break;
  }
  expect(_pause, findsOneWidget);
}

VoicePlaybackSession? _session(ProviderContainer c) =>
    c.read(voicePlaybackProvider);

Future<void> _scrollAway(WidgetTester tester) async {
  await tester.drag(_list, const Offset(0, 6000));
  await _frames(tester);
}

Future<void> _scrollBack(WidgetTester tester) async {
  await tester.drag(_list, const Offset(0, -30000));
  await _frames(tester);
}

void main() {
  late FakeAudioplayersPlatform audio;

  setUp(() {
    audio = FakeAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = audio;
    GlobalAudioplayersPlatformInterface.instance =
        FakeGlobalAudioplayersPlatform();
  });

  /// Nothing has paused, stopped or disposed the one player.
  void expectStillPlaying(ProviderContainer c) {
    expect(audio.created, hasLength(1));
    final id = audio.created.single;
    expect(audio.disposed, isEmpty);
    expect(audio.pauses[id] ?? 0, 0);
    expect(audio.stops[id] ?? 0, 0);
    expect(_session(c)?.status, VoicePlaybackStatus.playing);
  }

  group('playback survives', () {
    testWidgets('1 + 2. scrolling the playing note away disposes its bubble, '
        'not the audio', (tester) async {
      final c = await _open(tester, _Server());
      await _startPlaying(tester, index: 1);
      expect(find.byType(VoiceNotePlayer), findsNWidgets(2));

      await _scrollAway(tester);

      expect(
        find.byType(VoiceNotePlayer),
        findsNothing,
        reason: 'the bubbles really are gone',
      );
      expectStillPlaying(c);

      await _scrollBack(tester);
      expect(_pause, findsOneWidget, reason: 'and come back showing it');
      expectStillPlaying(c);
    });

    testWidgets('3. opening and closing the image viewer', (tester) async {
      final c = await _open(tester, _Server());
      await _startPlaying(tester, index: 1);

      await tester.tap(find.byType(CachedNetworkImage).first);
      await _frames(tester, 20);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expectStillPlaying(c);

      await tester.pageBack();
      await _frames(tester, 20);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(_pause, findsOneWidget);
      expectStillPlaying(c);
    });

    testWidgets('4. visiting another screen and coming back', (tester) async {
      final c = await _open(tester, _Server());
      await _startPlaying(tester, index: 1);

      unawaited(
        _nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Settings')),
          ),
        ),
      );
      await _frames(tester, 20);
      expect(find.text('Settings'), findsOneWidget);
      expectStillPlaying(c);

      _nav.currentState!.pop();
      await _frames(tester, 20);
      expect(_pause, findsOneWidget);
      expectStillPlaying(c);
    });

    testWidgets('5. switching conversations, and returning to the playing '
        'note', (tester) async {
      final c = await _open(tester, _Server());
      await _startPlaying(tester, index: 1);
      final id = audio.created.single;
      audio.positions[id] = const Duration(seconds: 2);
      await _frames(tester);

      // Conversation 42 is closed — its screen and bubbles are disposed.
      unawaited(
        _nav.currentState!.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const ConversationScreen(conversationId: 43),
          ),
        ),
      );
      await _frames(tester, 20);
      expect(find.text('Customer 43'), findsWidgets);
      expect(find.byType(VoiceNotePlayer), findsNothing);
      expectStillPlaying(c);

      audio.positions[id] = const Duration(seconds: 4);
      unawaited(
        _nav.currentState!.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const ConversationScreen(conversationId: 42),
          ),
        ),
      );
      await _frames(tester, 20);

      expect(_pause, findsOneWidget, reason: 'the bubble shows it playing');
      expect(find.text('0:04'), findsOneWidget, reason: 'at its position');
      expectStillPlaying(c);
    });
  });

  testWidgets('6. starting a second note stops the first and returns it to '
      'idle, on the same player', (tester) async {
    final c = await _open(tester, _Server());
    await _startPlaying(tester, index: 0);
    final id = audio.created.single;
    expect(_session(c)?.key, 'attachment:att-a');

    await tester.tap(_play);
    await _frames(tester, 20);

    expect(_session(c)?.key, 'attachment:att-b');
    expect(_session(c)?.status, VoicePlaybackStatus.playing);
    expect(audio.pauses[id], 1, reason: 'the first one stopped');
    expect(audio.created, hasLength(1), reason: 'no second player');
    expect(audio.sourcesSet[id], 2);
    expect(_pause, findsOneWidget, reason: 'one note playing');
    expect(_play, findsOneWidget, reason: 'the other idle');
    expect(find.text('0:07'), findsOneWidget, reason: 'idle shows full length');
  });

  testWidgets('7. a bubble built again shows the live position and does not '
      'restart the recording', (tester) async {
    final server = _Server();
    final c = await _open(tester, server);
    await _startPlaying(tester, index: 1);
    final id = audio.created.single;

    audio.positions[id] = const Duration(seconds: 3);
    await _frames(tester);
    expect(find.text('0:03'), findsOneWidget);

    await _scrollAway(tester);
    audio.positions[id] = const Duration(seconds: 5);
    await _frames(tester);
    await _scrollBack(tester);

    expect(find.text('0:05'), findsOneWidget);
    expect(_pause, findsOneWidget);
    // Not reloaded, not rewound, not fetched again.
    expect(audio.sourcesSet[id], 1);
    expect(audio.seeks[id] ?? const [], isEmpty);
    expect(server.audioFetches, [_voiceB]);
    expectStillPlaying(c);

    // Paused from the rebuilt bubble: the same session, kept where it is.
    await tester.tap(_pause);
    await _frames(tester);
    expect(_session(c)?.status, VoicePlaybackStatus.paused);
    expect(find.text('0:05'), findsOneWidget);
  });

  group('8. the player goes with its lifecycle boundary', () {
    /// `AudioPlayer.dispose()` releases the native player at once and
    /// disposes it after its own streams close, which takes real time.
    Future<void> expectDisposed(WidgetTester tester, String id) async {
      await _frames(tester);
      expect(audio.released, [id]);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _frames(tester);
      expect(audio.disposed, [id]);
      expect(audio.live, isEmpty);
    }

    testWidgets('the app\'s provider scope', (tester) async {
      await _open(tester, _Server());
      await _startPlaying(tester, index: 1);
      final id = audio.created.single;
      expect(audio.released, isEmpty);

      await tester.pumpWidget(const SizedBox());

      await expectDisposed(tester, id);
    });

    testWidgets('sign-out', (tester) async {
      final c = await _open(tester, _Server());
      await _startPlaying(tester, index: 1);
      final id = audio.created.single;

      // Not left playing for the next person to sign in.
      clearSessionScopedState(c.read(_refProvider));

      await expectDisposed(tester, id);
      expect(_session(c), isNull);
      expect(_pause, findsNothing);
    });
  });

  group('9. a recording that cannot be played', () {
    testWidgets('fetch fails: an error the bubble shows, and a retry that '
        'works', (tester) async {
      final server = _Server()..audioMissing = true;
      final c = await _open(tester, server);

      await tester.tap(_play.at(1));
      await _frames(tester, 20);

      expect(_session(c)?.status, VoicePlaybackStatus.error);
      expect(find.text("Couldn't play this voice message."), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(audio.created, isEmpty, reason: 'no player for nothing');

      server.audioMissing = false;
      await tester.tap(find.byIcon(Icons.refresh));
      await _frames(tester, 20);
      expect(_session(c)?.status, VoicePlaybackStatus.playing);
      expect(_pause, findsOneWidget);
    });

    testWidgets('the player rejects the file: error, nothing leaked', (
      tester,
    ) async {
      final c = await _open(tester, _Server());
      audio.failNextSource = true;

      await tester.tap(_play.at(1));
      await _frames(tester, 20);

      expect(_session(c)?.status, VoicePlaybackStatus.error);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(audio.live, hasLength(1), reason: 'the one player, reused');

      await tester.tap(find.byIcon(Icons.refresh));
      await _frames(tester, 20);
      expect(_session(c)?.status, VoicePlaybackStatus.playing);
      expect(audio.created, hasLength(1));
    });
  });

  testWidgets('10. rebuilds, scrolling, navigation and replays add no '
      'players and no subscriptions', (tester) async {
    final c = await _open(tester, _Server());
    await _startPlaying(tester, index: 1);
    final id = audio.created.single;
    final controller = c.read(voicePlaybackProvider.notifier);
    final platformListeners = audio.listeners[id];
    expect(controller.debugSubscriptionCount, 4);

    for (var round = 0; round < 3; round++) {
      await _scrollAway(tester);
      await _scrollBack(tester);
      unawaited(
        _nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await _frames(tester);
      _nav.currentState!.pop();
      await _frames(tester);
      await tester.pumpWidget(tester.widget(find.byType(ProviderScope)));
      await _frames(tester);
    }
    // Play to the end, then again, then the other note.
    audio.complete(id);
    await _frames(tester);
    await _startPlaying(tester, index: 1);
    await tester.tap(_play.first);
    await _frames(tester, 20);

    expect(audio.created, [id]);
    expect(audio.live, [id]);
    expect(controller.debugSubscriptionCount, 4);
    expect(audio.listeners[id], platformListeners);
  });
}

/// Hands [clearSessionScopedState] a `Ref`, as `session_reset_test` does.
final _refProvider = Provider<Ref>((ref) => ref);
