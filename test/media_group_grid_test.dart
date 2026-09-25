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
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/media_group_grid.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
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

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String payload, int status) => ResponseBody.fromString(
  payload,
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
  permissions: {
    Perm.conversationReply,
    Perm.conversationNote,
    Perm.conversationDeleteMessage,
  },
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

ApiClient _clientForMessages(String messagesJson) {
  final adapter = _StubAdapter((options) {
    if (options.path.contains('/messages/')) {
      return _json(messagesJson, 200);
    }
    if (options.path.contains('/notes/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/conversations/42/')) {
      return _json('''
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
  "last_customer_message_at": "2026-09-02T14:10:00Z"
}
''', 200);
    }
    if (options.path.contains('/channels/')) {
      return _json('[]', 200);
    }
    if (options.path.contains('/read/')) {
      return _json('{"status": "ok"}', 200);
    }
    return _json('{}', 200);
  });

  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

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

Widget _gridHarness(Widget child, {ApiClient? client}) {
  final defaultClient = client ?? _clientForMessages('{"results": []}');
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(defaultClient),
      currentEmployeeProvider.overrideWithValue(_employee()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: child,
        ),
      ),
    ),
  );
}

Future<void> _pumpConversation(
  WidgetTester tester,
  ApiClient client, {
  ThemeData? theme,
  Locale? locale,
}) async {
  await tester.pumpWidget(_harness(client, theme: theme, locale: locale));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

MessageAttachment _imageAttachment(String id, String url) => MessageAttachment(
  attachmentId: id,
  type: 'IMAGE',
  mimeType: 'image/jpeg',
  url: url,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioplayersPlatformInterface.instance = _FakeAudioplayersPlatform();
  GlobalAudioplayersPlatformInterface.instance =
      _FakeGlobalAudioplayersPlatform();

  group('MediaGroupGrid widget layouts', () {
    testWidgets('1. 2 images render side-by-side row layout', (tester) async {
      final attachments = [
        _imageAttachment('1', 'https://example.com/1.jpg'),
        _imageAttachment('2', 'https://example.com/2.jpg'),
      ];

      await tester.pumpWidget(
        _gridHarness(
          MediaGroupGrid(
            attachments: attachments,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(MediaGroupGrid), findsOneWidget);
      // Grid height for 2 images is 150
      final gridBox = tester.renderObject<RenderBox>(find.byType(MediaGroupGrid));
      expect(gridBox.size.height, 150.0);
      expect(gridBox.size.width, lessThanOrEqualTo(MediaGroupGrid.maxGridWidth));
      expect(find.byType(GestureDetector), findsNWidgets(2));
    });

    testWidgets('2. 3 images render asymmetric layout (1 large + 2 stacked)', (
      tester,
    ) async {
      final attachments = [
        _imageAttachment('1', 'https://example.com/1.jpg'),
        _imageAttachment('2', 'https://example.com/2.jpg'),
        _imageAttachment('3', 'https://example.com/3.jpg'),
      ];

      await tester.pumpWidget(
        _gridHarness(
          MediaGroupGrid(
            attachments: attachments,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(MediaGroupGrid), findsOneWidget);
      final gridBox = tester.renderObject<RenderBox>(find.byType(MediaGroupGrid));
      expect(gridBox.size.height, 180.0);
      expect(find.byType(GestureDetector), findsNWidgets(3));
    });

    testWidgets('3. 4 images render 2x2 grid layout', (tester) async {
      final attachments = [
        _imageAttachment('1', 'https://example.com/1.jpg'),
        _imageAttachment('2', 'https://example.com/2.jpg'),
        _imageAttachment('3', 'https://example.com/3.jpg'),
        _imageAttachment('4', 'https://example.com/4.jpg'),
      ];

      await tester.pumpWidget(
        _gridHarness(
          MediaGroupGrid(
            attachments: attachments,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(MediaGroupGrid), findsOneWidget);
      expect(find.byType(GestureDetector), findsNWidgets(4));
      // No overflow badge on 4 images
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('4. More than 4 images displays +N overlay on the 4th tile', (
      tester,
    ) async {
      final attachments = [
        _imageAttachment('1', 'https://example.com/1.jpg'),
        _imageAttachment('2', 'https://example.com/2.jpg'),
        _imageAttachment('3', 'https://example.com/3.jpg'),
        _imageAttachment('4', 'https://example.com/4.jpg'),
        _imageAttachment('5', 'https://example.com/5.jpg'),
        _imageAttachment('6', 'https://example.com/6.jpg'),
      ];

      await tester.pumpWidget(
        _gridHarness(
          MediaGroupGrid(
            attachments: attachments,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byType(MediaGroupGrid), findsOneWidget);
      // 6 images total: 4th tile shows +3 (attachments.length - 3 = 6 - 3 = 3)
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('5. Tapping tile invokes onTapImage with exact index', (
      tester,
    ) async {
      final attachments = [
        _imageAttachment('1', 'https://example.com/1.jpg'),
        _imageAttachment('2', 'https://example.com/2.jpg'),
        _imageAttachment('3', 'https://example.com/3.jpg'),
      ];

      int? tappedIndex;

      await tester.pumpWidget(
        _gridHarness(
          MediaGroupGrid(
            attachments: attachments,
            onTapImage: (idx) => tappedIndex = idx,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Tap second image
      final gestureFinders = find.descendant(
        of: find.byType(MediaGroupGrid),
        matching: find.byType(GestureDetector),
      );
      await tester.tap(gestureFinders.at(1));
      await tester.pump();

      expect(tappedIndex, equals(1));
    });
  });

  group('ConversationScreen integration & grouping behavior', () {
    testWidgets('6. Single image message uses single image view without grid', (
      tester,
    ) async {
      final messagesJson = jsonEncode({
        'results': [
          {
            'id': 101,
            'direction': 'INBOUND',
            'sender_name': 'Sarah Connor',
            'message_type': 'IMAGE',
            'text': '',
            'sent_at': '2026-09-02T14:10:00Z',
            'attachments': [
              {
                'id': 'att_1',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/single.jpg',
              },
            ],
          },
        ],
      });

      final client = _clientForMessages(messagesJson);
      await _pumpConversation(tester, client);

      expect(find.byType(MessageBubble), findsOneWidget);
      // MediaGroupGrid is NOT used for 1 image
      expect(find.byType(MediaGroupGrid), findsNothing);
    });

    testWidgets(
      '7. Multiple images in the same message are grouped into MediaGroupGrid',
      (tester) async {
        final messagesJson = jsonEncode({
          'results': [
            {
              'id': 201,
              'direction': 'OUTBOUND',
              'sender_name': 'Sam Agent',
              'message_type': 'IMAGE',
              'text': 'Here are the design options',
              'sent_at': '2026-09-02T14:10:00Z',
              'attachments': [
                {
                  'id': 'att_1',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/opt1.jpg',
                },
                {
                  'id': 'att_2',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/opt2.jpg',
                },
                {
                  'id': 'att_3',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/opt3.jpg',
                },
                {
                  'id': 'att_4',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/opt4.jpg',
                },
              ],
            },
          ],
        });

        final client = _clientForMessages(messagesJson);
        await _pumpConversation(tester, client);

        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.byType(MediaGroupGrid), findsOneWidget);
        // Caption text is preserved below the grid!
        expect(find.text('Here are the design options'), findsOneWidget);
      },
    );

    testWidgets(
      '8. Separate image messages at different times are NOT grouped together',
      (tester) async {
        final messagesJson = jsonEncode({
          'results': [
            {
              'id': 301,
              'direction': 'INBOUND',
              'sender_name': 'Sarah Connor',
              'message_type': 'IMAGE',
              'text': 'First photo',
              'sent_at': '2026-09-02T14:10:00Z',
              'attachments': [
                {
                  'id': 'att_1',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/photo1.jpg',
                },
              ],
            },
            {
              'id': 302,
              'direction': 'INBOUND',
              'sender_name': 'Sarah Connor',
              'message_type': 'IMAGE',
              'text': 'Second photo later',
              'sent_at': '2026-09-02T15:30:00Z',
              'attachments': [
                {
                  'id': 'att_2',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/photo2.jpg',
                },
              ],
            },
          ],
        });

        final client = _clientForMessages(messagesJson);
        await _pumpConversation(tester, client);

        // Two separate message bubbles
        expect(find.byType(MessageBubble), findsNWidgets(2));
        // No MediaGroupGrid created because each message only has 1 image
        expect(find.byType(MediaGroupGrid), findsNothing);
        expect(find.text('First photo'), findsOneWidget);
        expect(find.text('Second photo later'), findsOneWidget);
      },
    );

    testWidgets(
      '9. Mixed attachments (images + PDF) keep PDF separate from image grid',
      (tester) async {
        final messagesJson = jsonEncode({
          'results': [
            {
              'id': 401,
              'direction': 'INBOUND',
              'sender_name': 'Sarah Connor',
              'message_type': 'FILE',
              'text': 'Photos and contract',
              'sent_at': '2026-09-02T14:10:00Z',
              'attachments': [
                {
                  'id': 'att_img1',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/img1.jpg',
                },
                {
                  'id': 'att_img2',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/img2.jpg',
                },
                {
                  'id': 'att_doc',
                  'type': 'FILE',
                  'file_name': 'contract.pdf',
                  'mime_type': 'application/pdf',
                  'size_bytes': 2048,
                },
              ],
            },
          ],
        });

        final client = _clientForMessages(messagesJson);
        await _pumpConversation(tester, client);

        // 2 images formed a MediaGroupGrid
        expect(find.byType(MediaGroupGrid), findsOneWidget);
        // The PDF is rendered as a distinct document attachment chip
        expect(find.text('contract.pdf'), findsOneWidget);
      },
    );

    testWidgets(
      '10. Tapping an image in the group opens gallery viewer at the selected image',
      (tester) async {
        final messagesJson = jsonEncode({
          'results': [
            {
              'id': 501,
              'direction': 'INBOUND',
              'sender_name': 'Sarah Connor',
              'message_type': 'IMAGE',
              'text': '',
              'sent_at': '2026-09-02T14:10:00Z',
              'attachments': [
                {
                  'id': 'att_1',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/one.jpg',
                },
                {
                  'id': 'att_2',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/two.jpg',
                },
                {
                  'id': 'att_3',
                  'type': 'IMAGE',
                  'mime_type': 'image/jpeg',
                  'url': 'https://example.com/three.jpg',
                },
              ],
            },
          ],
        });

        final client = _clientForMessages(messagesJson);
        await _pumpConversation(tester, client);

        final tiles = find.descendant(
          of: find.byType(MediaGroupGrid),
          matching: find.byType(GestureDetector),
        );
        expect(tiles, findsNWidgets(3));

        // Tap the 2nd image tile (index 1)
        await tester.tap(tiles.at(1));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Gallery viewer opened, showing title '2 / 3'
        expect(find.text('2 / 3'), findsOneWidget);
        expect(find.byType(PageView), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);

        // Swipe right-to-left to go to the 3rd image (screen width is 800, so drag > 400px)
        await tester.fling(find.byType(PageView), const Offset(-500.0, 0.0), 1000.0);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Counter updated to '3 / 3'
        expect(find.text('3 / 3'), findsOneWidget);
      },
    );

    testWidgets('11. RTL Arabic mode renders correctly without overflow', (
      tester,
    ) async {
      final messagesJson = jsonEncode({
        'results': [
          {
            'id': 601,
            'direction': 'INBOUND',
            'sender_name': 'سارة',
            'message_type': 'IMAGE',
            'text': 'مجموعة صور جديدة',
            'sent_at': '2026-09-02T14:10:00Z',
            'attachments': [
              {
                'id': 'att_1',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/1.jpg',
              },
              {
                'id': 'att_2',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/2.jpg',
              },
              {
                'id': 'att_3',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/3.jpg',
              },
            ],
          },
        ],
      });

      final client = _clientForMessages(messagesJson);
      await _pumpConversation(
        tester,
        client,
        theme: AppTheme.dark,
        locale: const Locale('ar'),
      );

      expect(find.byType(MediaGroupGrid), findsOneWidget);
      expect(find.text('مجموعة صور جديدة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. Small screen width does not produce layout overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 2.0, 600 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final messagesJson = jsonEncode({
        'results': [
          {
            'id': 701,
            'direction': 'OUTBOUND',
            'sender_name': 'Sam Agent',
            'message_type': 'IMAGE',
            'text': 'Small screen test',
            'sent_at': '2026-09-02T14:10:00Z',
            'attachments': [
              {
                'id': 'att_1',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/1.jpg',
              },
              {
                'id': 'att_2',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/2.jpg',
              },
              {
                'id': 'att_3',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/3.jpg',
              },
              {
                'id': 'att_4',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/4.jpg',
              },
            ],
          },
        ],
      });

      final client = _clientForMessages(messagesJson);
      await _pumpConversation(tester, client);

      expect(find.byType(MediaGroupGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('13. 4 separate server messages from same send batch render as single MediaGroupGrid', (
      tester,
    ) async {
      final messagesJson = jsonEncode({
        'results': [
          {
            'id': 88757,
            'direction': 'OUTBOUND',
            'sender_name': 'Sam Agent',
            'message_type': 'IMAGE',
            'client_message_id': 'local-1790091831787555',
            'text': 'Here are the requested photos',
            'delivery_status': 'SENT',
            'sent_at': '2026-09-22T18:00:00Z',
            'attachments': [
              {
                'id': 'att_1',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/1.jpg',
              },
            ],
          },
          {
            'id': 88759,
            'direction': 'OUTBOUND',
            'sender_name': 'Sam Agent',
            'message_type': 'IMAGE',
            'client_message_id': 'local-1790091831787555:1',
            'text': '',
            'delivery_status': 'SENT',
            'sent_at': '2026-09-22T18:00:01Z',
            'attachments': [
              {
                'id': 'att_2',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/2.jpg',
              },
            ],
          },
          {
            'id': 88760,
            'direction': 'OUTBOUND',
            'sender_name': 'Sam Agent',
            'message_type': 'IMAGE',
            'client_message_id': 'local-1790091831787555:2',
            'text': '',
            'delivery_status': 'SENT',
            'sent_at': '2026-09-22T18:00:02Z',
            'attachments': [
              {
                'id': 'att_3',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/3.jpg',
              },
            ],
          },
          {
            'id': 88761,
            'direction': 'OUTBOUND',
            'sender_name': 'Sam Agent',
            'message_type': 'IMAGE',
            'client_message_id': 'local-1790091831787555:3',
            'text': '',
            'delivery_status': 'SENT',
            'sent_at': '2026-09-22T18:00:03Z',
            'attachments': [
              {
                'id': 'att_4',
                'type': 'IMAGE',
                'mime_type': 'image/jpeg',
                'url': 'https://example.com/4.jpg',
              },
            ],
          },
        ],
      });

      final client = _clientForMessages(messagesJson);
      await _pumpConversation(tester, client);

      // Only ONE MessageBubble and ONE MediaGroupGrid should be rendered,
      // NOT 4 separate stacked single-image bubbles!
      expect(find.byType(MediaGroupGrid), findsOneWidget);
      expect(find.byType(MessageBubble), findsOneWidget);
      expect(find.text('Here are the requested photos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('groupMediaBatchMessages unit tests', () {
    test('groups 4 messages sharing base client_message_id into 1 composite message', () {
      final m1 = Message(
        id: 88757,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: 'Look at these pictures',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:00Z'),
        clientMessageId: 'local-1790091831787555',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/1.jpg'),
        ],
      );
      final m2 = Message(
        id: 88759,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:01Z'),
        clientMessageId: 'local-1790091831787555:1',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/2.jpg'),
        ],
      );
      final m3 = Message(
        id: 88760,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:02Z'),
        clientMessageId: 'local-1790091831787555:2',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/3.jpg'),
        ],
      );
      final m4 = Message(
        id: 88761,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:03Z'),
        clientMessageId: 'local-1790091831787555:3',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/4.jpg'),
        ],
      );

      final grouped = groupMediaBatchMessages([m1, m2, m3, m4]);
      expect(grouped.length, 1);
      final composite = grouped.first;
      expect(composite.id, 88757);
      expect(composite.attachments.length, 4);
      expect(composite.text, 'Look at these pictures');
      expect(composite.memberMessageIds, [88757, 88759, 88760, 88761]);
    });

    test('does not group messages with different base client message ids', () {
      final m1 = Message(
        id: 101,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:00Z'),
        clientMessageId: 'local-batchA',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/1.jpg'),
        ],
      );
      final m2 = Message(
        id: 102,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:01Z'),
        clientMessageId: 'local-batchB',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/2.jpg'),
        ],
      );

      final grouped = groupMediaBatchMessages([m1, m2]);
      expect(grouped.length, 2);
    });

    test('does not group non-image messages', () {
      final m1 = Message(
        id: 101,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'FILE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:00Z'),
        clientMessageId: 'local-batchA',
        attachments: const [
          MessageAttachment(type: 'FILE', url: 'https://example.com/file.pdf'),
        ],
      );
      final m2 = Message(
        id: 102,
        direction: 'OUTBOUND',
        senderType: 'AGENT',
        senderName: 'Agent',
        messageType: 'IMAGE',
        text: '',
        deliveryStatus: 'SENT',
        sentAt: DateTime.parse('2026-09-22T18:00:01Z'),
        clientMessageId: 'local-batchA:1',
        attachments: const [
          MessageAttachment(type: 'IMAGE', url: 'https://example.com/2.jpg'),
        ],
      );

      final grouped = groupMediaBatchMessages([m1, m2]);
      expect(grouped.length, 2);
    });
  });
}
