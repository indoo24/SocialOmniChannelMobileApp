import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake audioplayers platform for voice message playback tests
// ---------------------------------------------------------------------------

class _FakeGlobalAudioplayersPlatform
    extends GlobalAudioplayersPlatformInterface {
  final _eventCtrl = StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _eventCtrl.stream;
}

class _TestAudioplayersPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> eventCtrls = {};
  final List<String> createdPlayers = [];
  final List<String> disposedPlayers = [];
  final Map<String, List<Duration>> seekCalls = {};
  final Map<String, int> resumeCalls = {};
  final Map<String, int> pauseCalls = {};
  final Map<String, int> setSourceBytesCalls = {};

  @override
  Future<void> create(String playerId) async {
    createdPlayers.add(playerId);
    eventCtrls[playerId] = StreamController<AudioEvent>.broadcast();
    seekCalls[playerId] = [];
    resumeCalls[playerId] = 0;
    pauseCalls[playerId] = 0;
    setSourceBytesCalls[playerId] = 0;
  }

  @override
  Future<void> dispose(String playerId) async {
    disposedPlayers.add(playerId);
    await eventCtrls.remove(playerId)?.close();
  }

  @override
  Future<void> pause(String playerId) async {
    pauseCalls[playerId] = (pauseCalls[playerId] ?? 0) + 1;
  }

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {
    resumeCalls[playerId] = (resumeCalls[playerId] ?? 0) + 1;
  }

  @override
  Future<void> release(String playerId) async {
    disposedPlayers.add(playerId);
  }

  @override
  Future<void> seek(String playerId, Duration position) async {
    seekCalls[playerId]?.add(position);
    eventCtrls[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.seekComplete),
    );
  }

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _emitPrepared(playerId);
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    setSourceBytesCalls[playerId] = (setSourceBytesCalls[playerId] ?? 0) + 1;
    _emitPrepared(playerId);
  }

  void _emitPrepared(String playerId) {
    eventCtrls[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
    eventCtrls[playerId]?.add(
      const AudioEvent(
        eventType: AudioEventType.duration,
        duration: Duration(seconds: 7),
      ),
    );
  }

  void emitComplete(String playerId) {
    eventCtrls[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.complete),
    );
  }

  @override
  Future<void> setAudioContext(
    String playerId,
    AudioContext audioContext,
  ) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => 7000;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      eventCtrls[playerId]?.stream ?? const Stream.empty();
}

// ---------------------------------------------------------------------------
// HTTP stub & Mock client setup
// ---------------------------------------------------------------------------

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

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

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationNote},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

String get _conversationDetail {
  final recentTime = DateTime.now()
      .subtract(const Duration(minutes: 5))
      .toUtc()
      .toIso8601String();
  return '''
{
  "id": 42,
  "customer": {
    "id": 7,
    "display_name": "Sarah Connor",
    "avatar_url": "",
    "initials": "SC",
    "phone": "+201124868273"
  },
  "provider": "WHATSAPP",
  "channel_name": "Scenario Sales",
  "status": "OPEN",
  "last_customer_message_at": "$recentTime"
}
''';
}

String _messagesResponse(List<Map<String, dynamic>> attachmentsList) {
  final results = [
    for (var i = 0; i < attachmentsList.length; i++)
      {
        'id': 100 + i,
        'direction': 'INBOUND',
        'sender_type': 'CUSTOMER',
        'sender_name': 'Sarah Connor',
        'sender_initials': 'SC',
        'message_type': 'AUDIO',
        'text': '',
        'attachments': [attachmentsList[i]],
        'delivery_status': 'DELIVERED',
        'sent_at': '2026-09-04T12:00:00Z',
      },
  ];
  return jsonEncode({'results': results});
}

final Uint8List _fakeAudioBytes = Uint8List.fromList(List<int>.filled(32, 1));

ApiClient _conversationClient(
  String messagesBody, {
  Map<String, Uint8List>? customAudioUrls,
}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    if (options.path.contains('/messages/')) {
      return _json(messagesBody, 200);
    }
    if (options.path.contains('/notes/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/conversations/42/')) {
      return _json(_conversationDetail, 200);
    }
    if (options.path == '/conversations/') {
      return _json('{"results": []}', 200);
    }
    if (options.path.contains('/read/')) {
      return _json('{}', 200);
    }
    if (customAudioUrls != null && customAudioUrls.containsKey(options.path)) {
      return ResponseBody.fromBytes(customAudioUrls[options.path]!, 200);
    }
    if (options.path == 'https://cdn.example.com/voice.ogg' ||
        options.path == 'https://cdn.example.com/voice1.ogg' ||
        options.path == 'https://cdn.example.com/voice2.ogg') {
      return ResponseBody.fromBytes(_fakeAudioBytes, 200);
    }
    return _json('{"error": {"code": "not_found", "message": "no"}}', 404);
  });
  return client;
}

Future<void> _pumpConversation(
  WidgetTester tester,
  ApiClient client, {
  Widget? customHome,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: customHome ?? const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _TestAudioplayersPlatform fakeAudioPlatform;

  setUp(() {
    fakeAudioPlatform = _TestAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = fakeAudioPlatform;
    GlobalAudioplayersPlatformInterface.instance =
        _FakeGlobalAudioplayersPlatform();
  });

  group('Voice Message Playback Lifecycle', () {
    testWidgets(
      '1. Initial play: tapping play loads audio and begins playing',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.pause), findsNothing);

        // Tap play
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();

        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsNothing);
        expect(fakeAudioPlatform.createdPlayers.length, 1);
      },
    );

    testWidgets(
      '2. Pause/resume: tapping pause halts playback, resume resumes',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }
        expect(find.byIcon(Icons.pause), findsOneWidget);

        final playerId = fakeAudioPlatform.createdPlayers.first;

        // Pause playback
        await tester.tap(find.byIcon(Icons.pause));
        await tester.pump();
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.pause), findsNothing);
        expect(fakeAudioPlatform.pauseCalls[playerId], greaterThanOrEqualTo(1));

        // Resume playback
        final initialBytesCalls =
            fakeAudioPlatform.setSourceBytesCalls[playerId] ?? 0;
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }
        expect(find.byIcon(Icons.pause), findsOneWidget);
        // Ensure bytes were not re-downloaded / re-set
        expect(
          fakeAudioPlatform.setSourceBytesCalls[playerId],
          initialBytesCalls,
        );
      },
    );

    testWidgets(
      '3. Natural completion: audio reaching end resets position to 0:00 and ready state',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }
        expect(find.byIcon(Icons.pause), findsOneWidget);

        final playerId = fakeAudioPlatform.createdPlayers.first;

        fakeAudioPlatform.emitComplete(playerId);
        await tester.pump(const Duration(milliseconds: 50));

        // After completion:
        // - Play icon returned
        // - Pause icon gone
        // - Ready state duration shown
        // - Player kept in stop mode (not disposed) ready for instant replay
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.pause), findsNothing);
        expect(find.text('0:07'), findsOneWidget);
        expect(fakeAudioPlatform.disposedPlayers, isEmpty);
      },
    );

    testWidgets(
      '4. Tap after completion → replay from zero without leaving conversation',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);

        // 1. Initial play
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }
        expect(find.byIcon(Icons.pause), findsOneWidget);

        final playerId = fakeAudioPlatform.createdPlayers.first;

        // 2. Complete naturally
        fakeAudioPlatform.emitComplete(playerId);
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.pause), findsNothing);

        // 3. Tap again after completion
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }

        // 4. Starts playing again from zero instantly without creating a second player
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsNothing);
        expect(fakeAudioPlatform.createdPlayers.length, 1);
        expect(
          fakeAudioPlatform.resumeCalls[playerId],
          greaterThanOrEqualTo(1),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '5. Multiple voice messages: both render and operate independently',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 5000,
            },
            {
              'type': 'AUDIO',
              'id': 'att-2',
              'url': 'https://cdn.example.com/voice2.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 9000,
            },
          ]),
        );

        await _pumpConversation(tester, client);

        // Both messages render their duration chips and play buttons
        expect(find.byIcon(Icons.play_arrow), findsNWidgets(2));
        expect(find.text('0:05'), findsOneWidget);
        expect(find.text('0:09'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Switching between voice messages: playing message 2 pauses message 1',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 5000,
            },
            {
              'type': 'AUDIO',
              'id': 'att-2',
              'url': 'https://cdn.example.com/voice2.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 9000,
            },
          ]),
        );

        await _pumpConversation(tester, client);

        final playButtons = find.byIcon(Icons.play_arrow);
        expect(playButtons, findsNWidgets(2));

        // 1. Play first voice message
        await tester.tap(playButtons.first);
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }

        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);

        final firstPlayerId = fakeAudioPlatform.createdPlayers.first;

        // 2. Play second voice message
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (fakeAudioPlatform.createdPlayers.length > 1) break;
        }

        // First message should have paused automatically
        expect(
          fakeAudioPlatform.pauseCalls[firstPlayerId],
          greaterThanOrEqualTo(1),
        );
        // Only one pause icon should be present (the second player)
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      },
    );

    testWidgets(
      '7. Player lifetime: navigating away keeps the shared player playing; '
      'it is disposed with the app\'s provider scope',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'id': 'att-1',
              'url': 'https://cdn.example.com/voice1.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
        }
        expect(fakeAudioPlatform.createdPlayers.length, 1);
        final playerId = fakeAudioPlatform.createdPlayers.first;

        // Navigate away / replace conversation screen with placeholder
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: const MaterialApp(home: Scaffold(body: Text('Home'))),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // The conversation is gone; the voice note is not. Playback belongs
        // to the app-wide player, which outlives every screen.
        expect(fakeAudioPlatform.disposedPlayers, isEmpty);
        expect(fakeAudioPlatform.pauseCalls[playerId], 0);

        // The app's provider scope goes: so does the player.
        await tester.pumpWidget(const SizedBox());
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(fakeAudioPlatform.disposedPlayers, contains(playerId));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('8. Conversation rebuild does not break playback state', (
      tester,
    ) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'AUDIO',
            'id': 'att-1',
            'url': 'https://cdn.example.com/voice1.ogg',
            'mime_type': 'audio/ogg',
            'duration_ms': 7000,
          },
        ]),
      );

      await _pumpConversation(tester, client);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
      }
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // Trigger conversation widget rebuild
      await tester.pump();

      // Playback remains in playing state with same player
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(fakeAudioPlatform.createdPlayers.length, 1);
      expect(fakeAudioPlatform.disposedPlayers, isEmpty);
    });
  });
}
