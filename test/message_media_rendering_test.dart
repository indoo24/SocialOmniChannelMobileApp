/// Regression tests for rendering image and voice-message attachments as
/// real media (not the generic filename-only chip), and for the
/// `MessageAttachment` URL-resolution fix underneath it.
///
/// Context: `Message.attachments[]` is untyped in the backend's own OpenAPI
/// schema. What is verified here instead:
///
///  - `Environment.resolveMedia()` already existed in this codebase (used by
///    nothing, until this fix) specifically to turn a host-relative URL
///    absolute — its presence is itself evidence the backend can send
///    relative attachment URLs.
///  - `GET /api/attachments/{id}/content/` is a real, documented endpoint
///    (`api/docs`) for fetching an attachment's bytes when a direct URL
///    is not usable, gated on the session cookie.
///
/// `MessageAttachment.resolvedUrl` combines both: use `url` once resolved
/// against the API host if that is non-empty, else fall back to the content
/// endpoint from an id. `CachedNetworkImage`/`AudioPlayer` both need the
/// session cookie attached by hand — neither goes through the app's Dio
/// client, which is the only HTTP client the cookie-manager interceptor
/// covers.
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
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// HTTP stub — same pattern as composer_attachment_test.dart /
// message_deletion_test.dart.
// ---------------------------------------------------------------------------

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
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

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

// ---------------------------------------------------------------------------
// Fake: audioplayers
//
// Like image_picker/record before it, audioplayers has no platform channel
// handler in the widget-test environment — every platform call just hangs
// forever waiting on a response nothing will ever send. This fakes both
// halves of the plugin's own platform interface (per-player and global) so
// AudioPlayer's real Dart-side code runs against a fake that actually
// answers, the same "only replace the native call at the bottom" approach
// settings_channels_tab_test.dart / composer_attachment_test.dart already
// use for their own plugins.
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

class _FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _eventCtrls = {};

  /// When set, [setSourceBytes] never emits `prepared` — used to exercise
  /// the player's own error path deterministically instead of waiting out
  /// the real 30s preparation timeout.
  bool failToPrepare = false;

  @override
  Future<void> create(String playerId) async {
    _eventCtrls[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    await _eventCtrls.remove(playerId)?.close();
  }

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

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
    _prepared(playerId);
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    _prepared(playerId);
  }

  void _prepared(String playerId) {
    if (failToPrepare) return;
    _eventCtrls[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
    _eventCtrls[playerId]?.add(
      const AudioEvent(
        eventType: AudioEventType.duration,
        duration: Duration(seconds: 7),
      ),
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
      _eventCtrls[playerId]?.stream ?? const Stream.empty();
}

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

const _conversationDetail = '''
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
  "status": "OPEN"
}
''';

/// One inbound message per attachment JSON given, so each test can drop in
/// exactly the attachment shape it wants to assert against.
String _messagesResponse(List<Map<String, dynamic>> attachmentsList) {
  final results = [
    for (var i = 0; i < attachmentsList.length; i++)
      {
        'id': 100 + i,
        'direction': 'INBOUND',
        'sender_type': 'CUSTOMER',
        'sender_name': 'Sarah Connor',
        'sender_initials': 'SC',
        'message_type': 'IMAGE',
        'text': '',
        'attachments': [attachmentsList[i]],
        'delivery_status': 'DELIVERED',
        'sent_at': '2026-09-04T12:00:00Z',
      },
  ];
  return jsonEncode({'results': results});
}

Future<void> _pumpConversation(
  WidgetTester tester,
  ApiClient client, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: theme ?? AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  // Not pumpAndSettle(): `_AttachmentImage`'s FutureBuilder
  // (mediaAuthHeaders()) and CachedNetworkImage's own network fetch (which
  // genuinely fails in this offline test environment, by design — see the
  // class doc comment) both keep scheduling frames for a while. A handful
  // of bounded pumps is enough for the branch selection and initial state
  // this file asserts on to settle.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A fixture "audio bytes" response, standing in for the real content
/// endpoint answering with the file itself. The exact bytes do not matter —
/// the fake audio platform (below) never actually decodes them.
final Uint8List _fakeAudioBytes = Uint8List.fromList(List<int>.filled(32, 1));

ApiClient _conversationClient(String messagesBody) => _stubClient((options) {
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
  // The one fixture URL tests use to exercise a *successful* audio fetch.
  // Every other request in these tests is a fixture audio/image "url"
  // pointing at a fake host with no real content behind it — the same stub
  // adapter still handles it (any absolute URL goes through this Dio
  // instance's adapter regardless of host), answering 404 so it is always
  // the media widget's own error path under test, never a silently-fake
  // 200 masking a typo'd path or an unhandled host.
  if (options.path == 'https://cdn.example.com/voice.ogg') {
    return ResponseBody.fromBytes(_fakeAudioBytes, 200);
  }
  return _json('{"error": {"code": "not_found", "message": "no"}}', 404);
});

void main() {
  final fakeAudioPlatform = _FakeAudioplayersPlatform();
  AudioplayersPlatformInterface.instance = fakeAudioPlatform;
  GlobalAudioplayersPlatformInterface.instance =
      _FakeGlobalAudioplayersPlatform();

  setUp(() {
    fakeAudioPlatform.failToPrepare = false;
  });

  group('MessageAttachment.resolvedUrl', () {
    test('an absolute https url is used as-is', () {
      final attachment = MessageAttachment.fromJson({
        'type': 'IMAGE',
        'url': 'https://cdn.example.com/photo.jpg',
        'mime_type': 'image/jpeg',
      });

      expect(attachment.resolvedUrl, 'https://cdn.example.com/photo.jpg');
    });

    test('a host-relative url is resolved against the API host', () {
      final attachment = MessageAttachment.fromJson({
        'type': 'IMAGE',
        'url': '/media/attachments/photo.jpg',
        'mime_type': 'image/jpeg',
      });

      expect(
        attachment.resolvedUrl,
        'https://scenariomnchnl.tech/media/attachments/photo.jpg',
      );
    });

    test(
      'an empty url with an id falls back to the attachment content endpoint',
      () {
        final attachment = MessageAttachment.fromJson({
          'type': 'AUDIO',
          'id': 'abc-123',
          'mime_type': 'audio/ogg',
        });

        expect(
          attachment.resolvedUrl,
          'https://scenariomnchnl.tech/api/attachments/abc-123/content/',
        );
      },
    );

    test('public_id is read the same way as id', () {
      final attachment = MessageAttachment.fromJson({
        'type': 'IMAGE',
        'public_id': 'uuid-456',
      });

      expect(
        attachment.resolvedUrl,
        'https://scenariomnchnl.tech/api/attachments/uuid-456/content/',
      );
    });

    test('no url and no id resolves to empty, not a crash', () {
      final attachment = MessageAttachment.fromJson({'type': 'IMAGE'});

      expect(attachment.resolvedUrl, isEmpty);
    });
  });

  group('MessageAttachment type detection', () {
    test('image/* mime type is detected regardless of type field', () {
      final attachment = MessageAttachment.fromJson({
        'type': 'FILE',
        'mime_type': 'image/webp',
      });
      expect(attachment.isImage, isTrue);
      expect(attachment.isAudio, isFalse);
    });

    test('audio/* mime type is detected regardless of type field', () {
      final attachment = MessageAttachment.fromJson({
        'type': 'FILE',
        'mime_type': 'audio/ogg',
      });
      expect(attachment.isAudio, isTrue);
      expect(attachment.isImage, isFalse);
    });

    test('a non-media type is neither image nor audio', () {
      final attachment = MessageAttachment.fromJson({
        'type': 'FILE',
        'mime_type': 'application/pdf',
      });
      expect(attachment.isImage, isFalse);
      expect(attachment.isAudio, isFalse);
    });
  });

  group('Message bubble — image attachment', () {
    testWidgets('a resolvable image url renders as an image, not a filename '
        'chip', (tester) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'IMAGE',
            'url': 'https://cdn.example.com/photo.jpg',
            'file_name': 'scaled_1000517466.jpg',
            'mime_type': 'image/jpeg',
          },
        ]),
      );

      await _pumpConversation(tester, client);

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('scaled_1000517466.jpg'), findsNothing);
    });

    testWidgets('tapping an image opens a full-screen viewer', (tester) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'IMAGE',
            'url': 'https://cdn.example.com/photo.jpg',
            'mime_type': 'image/jpeg',
          },
        ]),
      );

      await _pumpConversation(tester, client);
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      await tester.tap(find.byType(CachedNetworkImage).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Two CachedNetworkImage widgets now: the thumbnail underneath (the
      // route is pushed on top, not replacing it) plus the full-screen one.
      expect(find.byType(CachedNetworkImage), findsWidgets);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('a missing/unresolvable url falls back to the generic chip '
        'without crashing', (tester) async {
      final client = _conversationClient(
        _messagesResponse([
          {'type': 'IMAGE', 'file_name': 'photo.jpg', 'mime_type': ''},
        ]),
      );

      await _pumpConversation(tester, client);

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an image load failure degrades to the generic chip, not a crash',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'IMAGE',
              // Not a real host - CachedNetworkImage's fetch fails, which is
              // exactly the state under test.
              'url': 'https://this-host-does-not-resolve.invalid/photo.jpg',
              'file_name': 'photo.jpg',
              'mime_type': 'image/jpeg',
            },
          ]),
        );

        await _pumpConversation(tester, client);
        // Give the failed fetch's error callback more time than the shared
        // helper's default budget to land.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Message bubble — voice attachment', () {
    testWidgets(
      'an audio mime type renders the voice player, not the generic chip',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              'url': 'https://cdn.example.com/voice.ogg',
              'file_name': 'voice-message.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);

        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.text('voice-message.ogg'), findsNothing);
      },
    );

    testWidgets('voice duration is shown before playback starts', (
      tester,
    ) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'AUDIO',
            'url': 'https://cdn.example.com/voice.ogg',
            'mime_type': 'audio/ogg',
            'duration_ms': 7000,
          },
        ]),
      );

      await _pumpConversation(tester, client);

      expect(find.text('0:07'), findsOneWidget);
    });

    testWidgets('tapping play fetches the audio and flips to a pause control', (
      tester,
    ) async {
      // Routed through the app's own Dio client (see `_conversationClient`
      // above) so the byte-fetch behind play actually succeeds — this is
      // the "play/pause works" happy path; the fetch-failure path is
      // covered separately below.
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'AUDIO',
            'url': 'https://cdn.example.com/voice.ogg',
            'mime_type': 'audio/ogg',
            'duration_ms': 7000,
          },
        ]),
      );

      await _pumpConversation(tester, client);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      // Not pumpAndSettle(): the tap kicks off a real byte-fetch and the
      // fake audio platform's own async event stream, behind a
      // CircularProgressIndicator — same reasoning as the composer's own
      // busy-spinner tests.
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byIcon(Icons.pause).evaluate().isNotEmpty) break;
      }

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a fetch failure behind play shows the retry affordance, not a crash',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {
              'type': 'AUDIO',
              // Not covered by cdn.example.com's 404 stub below — a
              // distinct host so this test is unambiguous about which
              // failure path it is exercising.
              'url': 'https://voice-storage.example.net/voice.ogg',
              'mime_type': 'audio/ogg',
              'duration_ms': 7000,
            },
          ]),
        );

        await _pumpConversation(tester, client);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);

        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.pump();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        expect(find.text('Couldn\'t play this voice message.'), findsOneWidget);
      },
    );

    testWidgets(
      'a voice message with no resolvable url shows the duration chip, '
      'not a crash',
      (tester) async {
        final client = _conversationClient(
          _messagesResponse([
            {'type': 'AUDIO', 'mime_type': 'audio/ogg', 'duration_ms': 3000},
          ]),
        );

        await _pumpConversation(tester, client);

        expect(find.byIcon(Icons.play_arrow), findsNothing);
        expect(find.text('0:03'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Message bubble — generic attachment behavior is unaffected', () {
    testWidgets('a document attachment still renders as the generic chip', (
      tester,
    ) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'FILE',
            'url': 'https://cdn.example.com/invoice.pdf',
            'file_name': 'invoice.pdf',
            'mime_type': 'application/pdf',
          },
        ]),
      );

      await _pumpConversation(tester, client);

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('a plain text message with no attachments is unaffected', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json(
            jsonEncode({
              'results': [
                {
                  'id': 1,
                  'direction': 'INBOUND',
                  'sender_type': 'CUSTOMER',
                  'sender_name': 'Sarah Connor',
                  'sender_initials': 'SC',
                  'message_type': 'TEXT',
                  'text': 'Hello there',
                  'attachments': <Object?>[],
                  'delivery_status': 'DELIVERED',
                  'sent_at': '2026-09-04T12:00:00Z',
                },
              ],
            }),
            200,
          );
        }
        if (options.path.contains('/notes/')) return _json('[]', 200);
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);

      expect(find.text('Hello there'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Theming, RTL, and narrow screens', () {
    testWidgets('image and voice attachments render in dark theme', (
      tester,
    ) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'IMAGE',
            'url': 'https://cdn.example.com/photo.jpg',
            'mime_type': 'image/jpeg',
          },
          {
            'type': 'AUDIO',
            'url': 'https://cdn.example.com/voice.ogg',
            'mime_type': 'audio/ogg',
            'duration_ms': 5000,
          },
        ]),
      );

      await _pumpConversation(tester, client, theme: AppTheme.dark);

      expect(find.byType(CachedNetworkImage), findsWidgets);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('image and voice attachments render in Arabic (RTL)', (
      tester,
    ) async {
      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'IMAGE',
            'url': 'https://cdn.example.com/photo.jpg',
            'mime_type': 'image/jpeg',
          },
          {
            'type': 'AUDIO',
            'url': 'https://cdn.example.com/voice.ogg',
            'mime_type': 'audio/ogg',
            'duration_ms': 5000,
          },
        ]),
      );

      await _pumpConversation(tester, client, locale: const Locale('ar'));

      expect(find.byType(CachedNetworkImage), findsWidgets);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a voice player does not overflow on a narrow Android '
        'width', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = _conversationClient(
        _messagesResponse([
          {
            'type': 'AUDIO',
            'url': 'https://cdn.example.com/voice.ogg',
            'mime_type': 'audio/ogg',
            'duration_ms': 65000,
          },
        ]),
      );

      await _pumpConversation(tester, client);

      expect(tester.takeException(), isNull);
    });
  });
}
