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
import 'package:scenario_mobile/features/messages/swipe_to_reply.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

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
  Future<void> setSourceUrl(String playerId, String url, {bool? isLocal, String? mimeType}) async {}
  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes, {String? mimeType}) async {}
  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) async {}
  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}
  @override
  Future<int?> getDuration(String playerId) async => 5000;
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

ApiClient _clientForMessages(String messagesJson) {
  return _stubClient((options) {
    if (options.path.contains('/conversations/42/messages/')) {
      return _json(messagesJson, 200);
    }
    if (options.path.contains('/conversations/42/notes/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/conversations/42/')) {
      return _json(_conversationJson(), 200);
    }
    if (options.path.contains('/saved-replies/')) {
      return _json('{"results": []}', 200);
    }
    return _json('{}', 200);
  });
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationNote,
    Perm.conversationDeleteMessage,
  },
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

String _conversationJson() => '''
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
  "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
}
''';

Widget _harness(ApiClient client, {ThemeData? theme, Locale? locale}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioplayersPlatformInterface.instance = _FakeAudioplayersPlatform();
  GlobalAudioplayersPlatformInterface.instance =
      _FakeGlobalAudioplayersPlatform();

  group('SwipeToReply unit & widget behavior', () {
    testWidgets('1. Horizontal swipe below threshold does NOT activate Reply', (
      tester,
    ) async {
      var replyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwipeToReply(
                onReply: () => replyCalled = true,
                threshold: 64.0,
                child: const Text('Swipeable text message'),
              ),
            ),
          ),
        ),
      );

      final textFinder = find.text('Swipeable text message');
      expect(textFinder, findsOneWidget);

      // Drag 40px (under 64px threshold)
      await tester.drag(textFinder, const Offset(40.0, 0.0));
      await tester.pumpAndSettle();

      expect(replyCalled, isFalse);
    });

    testWidgets('2. Horizontal swipe above threshold activates Reply', (
      tester,
    ) async {
      var replyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwipeToReply(
                onReply: () => replyCalled = true,
                threshold: 64.0,
                child: const Text('Swipeable text message'),
              ),
            ),
          ),
        ),
      );

      final textFinder = find.text('Swipeable text message');

      // Drag 80px (over 64px threshold)
      await tester.drag(textFinder, const Offset(80.0, 0.0));
      await tester.pumpAndSettle();

      expect(replyCalled, isTrue);
    });

    testWidgets(
      '3. Message returns to original position after release',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SwipeToReply(
                  onReply: () {},
                  threshold: 64.0,
                  child: const Text('Swipeable text message'),
                ),
              ),
            ),
          ),
        );

        final textFinder = find.text('Swipeable text message');
        final initialTopLeft = tester.getTopLeft(textFinder);

        // Start dragging
        final gesture = await tester.startGesture(tester.getCenter(textFinder));
        await gesture.moveBy(const Offset(50.0, 0.0));
        await tester.pump();

        // While dragging, text has translated horizontally
        final movingTopLeft = tester.getTopLeft(textFinder);
        expect(movingTopLeft.dx, greaterThan(initialTopLeft.dx + 30.0));

        // Release
        await gesture.up();
        await tester.pumpAndSettle();

        // After release, smoothly returns to original position
        final settledTopLeft = tester.getTopLeft(textFinder);
        expect(settledTopLeft.dx, equals(initialTopLeft.dx));
      },
    );

    testWidgets(
      '4. Vertical drag does not trigger Reply and allows scrolling',
      (tester) async {
        var replyCalled = false;
        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                controller: scrollController,
                itemCount: 20,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SwipeToReply(
                    onReply: () => replyCalled = true,
                    child: Text('Message item $i'),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(scrollController.offset, 0.0);

        // Drag vertically upwards on 'Message item 0'
        await tester.drag(find.text('Message item 0'), const Offset(0.0, -150.0));
        await tester.pumpAndSettle();

        // Scroll controller scrolled normally
        expect(scrollController.offset, greaterThan(100.0));
        // Reply was not activated
        expect(replyCalled, isFalse);
      },
    );

    testWidgets(
      '5. Disabled onReply does not register gestures or translate',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SwipeToReply(
                  onReply: null,
                  child: Text('Unreplyable message'),
                ),
              ),
            ),
          ),
        );

        final textFinder = find.text('Unreplyable message');
        final initialTopLeft = tester.getTopLeft(textFinder);

        await tester.drag(textFinder, const Offset(80.0, 0.0));
        await tester.pumpAndSettle();

        final afterTopLeft = tester.getTopLeft(textFinder);
        expect(afterTopLeft.dx, equals(initialTopLeft.dx));
      },
    );

    testWidgets(
      '6. RTL Arabic mode supports the natural WhatsApp reply swipe',
      (tester) async {
        var replyCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: SwipeToReply(
                    onReply: () => replyCalled = true,
                    threshold: 64.0,
                    child: const Text('رسالة قابلة للرد'),
                  ),
                ),
              ),
            ),
          ),
        );

        final textFinder = find.text('رسالة قابلة للرد');

        // Drag leftward in RTL (natural RTL start-to-end reply direction)
        await tester.drag(textFinder, const Offset(-80.0, 0.0));
        await tester.pumpAndSettle();

        expect(replyCalled, isTrue);
      },
    );
  });

  group('ConversationScreen integrated swipe-to-reply', () {
    testWidgets(
      '7. Swiping a message activates reply with the exact message ID and preview',
      (tester) async {
        final messagesJson = jsonEncode({
          'results': [
            {
              'id': 101,
              'direction': 'INBOUND',
              'sender_name': 'Sarah Connor',
              'text': 'Can you help with my order?',
              'sent_at': '2026-09-02T14:10:00Z',
            },
            {
              'id': 102,
              'direction': 'OUTBOUND',
              'sender_name': 'Sam Agent',
              'text': 'Sure, what is your order number?',
              'sent_at': '2026-09-02T14:11:00Z',
            },
          ],
        });

        final client = _clientForMessages(messagesJson);
        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        // Initially, composer has no reply preview
        expect(find.text('Replying to Sarah Connor'), findsNothing);

        // Swipe message 101 to the right
        final msg1Finder = find.text('Can you help with my order?');
        expect(msg1Finder, findsOneWidget);

        await tester.drag(msg1Finder, const Offset(100.0, 0.0));
        await tester.pumpAndSettle();

        // Reply preview is now visible in composer!
        expect(find.text('Replying to Sarah Connor'), findsOneWidget);
        expect(find.text('Can you help with my order?'), findsWidgets);

        // Swipe message 102 to the right
        final msg2Finder = find.text('Sure, what is your order number?');
        expect(msg2Finder, findsOneWidget);

        await tester.drag(msg2Finder, const Offset(100.0, 0.0));
        await tester.pumpAndSettle();

        // Composer now switches to replying to message 102!
        expect(find.text('Replying to Sam Agent'), findsOneWidget);
      },
    );

    testWidgets('8. Swipe-to-reply works on attachment messages', (
      tester,
    ) async {
      final messagesJson = jsonEncode({
        'results': [
          {
            'id': 201,
            'direction': 'INBOUND',
            'sender_name': 'Sarah Connor',
            'text': 'Here is the contract',
            'sent_at': '2026-09-02T14:10:00Z',
            'attachments': [
              {
                'id': 'att_contract',
                'type': 'FILE',
                'file_name': 'contract_terms.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 1024,
              },
            ],
          },
          {
            'id': 202,
            'direction': 'INBOUND',
            'sender_name': 'Sarah Connor',
            'text': '',
            'sent_at': '2026-09-02T14:11:00Z',
            'attachments': [
              {
                'id': 'att_voice',
                'type': 'AUDIO',
                'duration_ms': 5000,
              },
            ],
          },
        ],
      });

      final client = _clientForMessages(messagesJson);
      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      // Swipe the PDF document message
      expect(find.text('contract_terms.pdf'), findsOneWidget);
      await tester.drag(find.text('contract_terms.pdf'), const Offset(100.0, 0.0));
      await tester.pumpAndSettle();

      expect(find.text('Replying to Sarah Connor'), findsOneWidget);

      // Swipe the voice note message
      expect(find.text('0:05'), findsOneWidget);
      await tester.drag(find.text('0:05'), const Offset(100.0, 0.0));
      await tester.pumpAndSettle();

      expect(find.text('Replying to Sarah Connor'), findsOneWidget);
    });

    testWidgets('9. Existing long-press Reply action still functions properly', (
      tester,
    ) async {
      final messagesJson = jsonEncode({
        'results': [
          {
            'id': 301,
            'direction': 'INBOUND',
            'sender_name': 'Sarah Connor',
            'text': 'Long press to reply test',
            'sent_at': '2026-09-02T14:10:00Z',
          },
        ],
      });

      final client = _clientForMessages(messagesJson);
      await tester.pumpWidget(_harness(client));
      await tester.pumpAndSettle();

      final msgFinder = find.text('Long press to reply test');
      expect(msgFinder, findsOneWidget);

      // Long press without dragging
      await tester.longPress(msgFinder);
      await tester.pumpAndSettle();

      // Popup menu appears with Reply option
      expect(find.byIcon(Icons.reply_outlined), findsOneWidget);

      // Tap Reply
      await tester.tap(find.byIcon(Icons.reply_outlined));
      await tester.pumpAndSettle();

      // Composer enters reply mode
      expect(find.text('Replying to Sarah Connor'), findsOneWidget);
    });

    testWidgets(
      '10. Keyboard-open state does not cause layout or scroll regressions',
      (tester) async {
        final messagesJson = jsonEncode({
          'results': [
            {
              'id': 401,
              'direction': 'INBOUND',
              'sender_name': 'Sarah Connor',
              'text': 'Keyboard test message',
              'sent_at': '2026-09-02T14:10:00Z',
            },
          ],
        });

        final client = _clientForMessages(messagesJson);

        // Simulate keyboard open by setting viewInsets.bottom
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(() => tester.view.resetViewInsets());

        await tester.pumpWidget(_harness(client));
        await tester.pumpAndSettle();

        // Swipe the message with keyboard open
        final msgFinder = find.text('Keyboard test message');
        expect(msgFinder, findsOneWidget);

        await tester.drag(msgFinder, const Offset(100.0, 0.0));
        await tester.pumpAndSettle();

        // Verified: Reply preview appeared with zero layout overflow errors!
        expect(find.text('Replying to Sarah Connor'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
