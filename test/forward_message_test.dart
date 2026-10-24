/// Forwarding a message into another conversation.
///
/// All of this is mocked or stubbed: a Dio stub plays the backend, and the
/// attachment download is a fake that hands back a temp file. They prove what
/// the app *sends* — which requests, in which order, with what — and what it
/// shows when the server refuses. They do not prove a WhatsApp customer
/// receives anything: that needs the real backend and a real channel, and the
/// backend has no forward endpoint (see `docs/MOBILE_BACKEND_SYNC.md`, R6).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/messages/forward_message_sheet.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/features/messages/message_forwarding.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';

// ---------------------------------------------------------------------------
// A backend that records what it is asked.
// ---------------------------------------------------------------------------

class _Request {
  _Request(this.method, this.path, this.query, this.body, this.form);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;
  final FormData? form;
}

class _Server implements HttpClientAdapter {
  final requests = <_Request>[];

  /// Conversations the list answers with, newest first.
  var conversations = <Map<String, dynamic>>[
    _conversation(5, 'Source Customer', '+201000000005', 'Support Line'),
    _conversation(21, 'Mona Adel', '+201000000021', 'Support Line'),
    _conversation(22, 'Mona Adel', '+201000000022', 'Sales Line'),
    _conversation(23, 'Omar Said', '', 'Support Line'),
  ];
  bool listHasMore = false;
  int listStatus = 200;

  /// What `reply` answers: a status and, for an error, its message.
  int replyStatus = 201;
  String replyMessage = 'Refused.';
  bool replyNetworkDown = false;
  Completer<void>? holdReply;

  /// What staging a draft answers.
  int stageStatus = 201;
  var _drafts = 0;

  List<_Request> where(String method, String endsWith) => [
    for (final r in requests)
      if (r.method == method && r.path.endsWith(endsWith)) r,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Drained so a multipart upload releases the file it streams (Windows
    // keeps it locked otherwise).
    await requestStream?.drain<void>();
    final path = options.uri.path;
    final data = options.data;
    requests.add(
      _Request(
        options.method,
        path,
        options.queryParameters,
        data is FormData ? null : data,
        data is FormData ? data : null,
      ),
    );

    if (options.method == 'GET' && path.endsWith('/conversations/')) {
      if (listStatus != 200) return _error(listStatus, 'Try later.');
      final search = '${options.queryParameters['search'] ?? ''}'.toLowerCase();
      final rows = [
        for (final c in conversations)
          if (search.isEmpty ||
              '${(c['customer'] as Map)['display_name']}'
                  .toLowerCase()
                  .contains(search))
            c,
      ];
      return _ok({
        'count': rows.length,
        'next': listHasMore ? 'https://x.test/?page=2' : null,
        'previous': null,
        'results': rows,
      });
    }
    if (options.method == 'POST' && path.endsWith('/attachments/')) {
      if (stageStatus != 201) return _error(stageStatus, 'Too large.');
      _drafts++;
      return _ok({
        'id': 'draft-$_drafts',
        'type': 'IMAGE',
        'mime_type': 'image/jpeg',
        'file_name': 'x.jpg',
        'size_bytes': 3,
        'is_voice': false,
        'expires_at': '2026-10-25T00:00:00Z',
      }, 201);
    }
    if (options.method == 'DELETE' && path.contains('/attachments/')) {
      return ResponseBody.fromString('', 204);
    }
    if (options.method == 'POST' && path.endsWith('/reply/')) {
      final hold = holdReply;
      if (hold != null) await hold.future;
      if (replyNetworkDown) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      if (replyStatus != 201) return _error(replyStatus, replyMessage);
      final body = data is Map ? data : const {};
      return _ok({
        'id': 900,
        'direction': 'OUTBOUND',
        'sender_type': 'AGENT',
        'message_type': 'TEXT',
        'text': body['text'] ?? '',
        'delivery_status': 'SENT',
        'sent_at': '2026-10-24T10:00:00Z',
      }, 201);
    }
    return _ok({});
  }

  @override
  void close({bool force = false}) {}

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = this;
    return client;
  }
}

ResponseBody _ok(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _error(int status, String message) => ResponseBody.fromString(
  jsonEncode({
    'error': {'code': 'refused', 'message': message},
  }),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _conversation(
  int id,
  String name,
  String phone,
  String channel,
) => {
  'id': id,
  'customer': {
    'id': id,
    'display_name': name,
    'initials': name.substring(0, 1),
    'phone': phone,
  },
  'provider': 'WHATSAPP',
  'channel_name': channel,
  'channel_id': 1,
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
};

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

Message _message({
  int id = 7,
  String text = 'Our opening hours are 9 to 5.',
  List<Map<String, dynamic>> attachments = const [],
  String type = 'TEXT',
  String senderType = 'CUSTOMER',
}) => Message.fromJson({
  'id': id,
  'direction': senderType == 'CUSTOMER' ? 'INBOUND' : 'OUTBOUND',
  'sender_type': senderType,
  'message_type': type,
  'text': text,
  'delivery_status': 'DELIVERED',
  'sent_at': '2026-10-24T09:00:00Z',
  'attachments': attachments,
});

Map<String, dynamic> _attachment({
  String id = 'att-1',
  String type = 'IMAGE',
  String mime = 'image/jpeg',
  String name = 'photo.jpg',
  String status = 'READY',
  int? durationMs,
}) => {
  'id': id,
  'type': type,
  'mime_type': mime,
  'file_name': name,
  'status': status,
  'url': 'https://scenariomnchnl.tech/api/attachments/$id/content/',
  'duration_ms': ?durationMs,
};

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply},
  visibilityScope: 'ALL',
);

class _FakeInbox extends InboxController {
  static int refreshes = 0;

  @override
  Future<InboxState> build() async => const InboxState();

  @override
  Future<void> refreshQuietly({bool reset = false}) async {
    refreshes++;
  }
}

late Directory _tmp;

/// A fetcher that "downloads" each attachment to a real temp file.
class _Fetcher {
  final fetched = <String>[];
  final unavailable = <String>{};

  Future<File?> call(MessageAttachment attachment, int messageId) async {
    fetched.add(attachment.attachmentId);
    if (unavailable.contains(attachment.attachmentId)) return null;
    final file = File('${_tmp.path}/${attachment.attachmentId}.bin');
    file.writeAsBytesSync([1, 2, 3]);
    return file;
  }
}

ProviderContainer _container(_Server server, _Fetcher fetcher) {
  final c = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(server.client()),
      currentEmployeeProvider.overrideWithValue(_employee),
      forwardAttachmentFetcherProvider.overrideWithValue(fetcher.call),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _app(
  _Server server,
  _Fetcher fetcher, {
  required Message message,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(server.client()),
    currentEmployeeProvider.overrideWithValue(_employee),
    forwardAttachmentFetcherProvider.overrideWithValue(fetcher.call),
    inboxControllerProvider.overrideWith(_FakeInbox.new),
    conversationCountsProvider.overrideWith((ref) async => {}),
    channelsProvider.overrideWith(
      (ref) async => [
        ChannelConnection.fromJson(const {
          'id': 1,
          'provider': 'WHATSAPP',
          'status': 'CONNECTED',
          'is_active': true,
        }),
      ],
    ),
  ],
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              startForwardMessage(context, conversationId: 5, message: message),
          child: const Text('forward'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('forward'));
  await tester.pumpAndSettle();
}

Finder _row(int id) => find.byKey(ValueKey('forwardDestination_$id'));
final _confirmButton = find.byKey(const Key('forwardConfirmButton'));
final _dialogSend = find.byKey(const Key('forwardConfirmSend'));

Future<void> _chooseAndConfirm(WidgetTester tester, int id) async {
  await tester.tap(_row(id));
  await tester.pump();
  await tester.tap(_confirmButton);
  await tester.pumpAndSettle();
  await tester.tap(_dialogSend);
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('forward_test_');
    _FakeInbox.refreshes = 0;
  });
  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A handle still closing on Windows; the OS cleans temp up.
    }
  });

  // -------------------------------------------------------------------------
  group('what can be forwarded', () {
    test('text, pictures, video, audio, voice notes and documents can', () {
      expect(forwardBlockOf(_message()), isNull);
      for (final a in [
        _attachment(),
        _attachment(type: 'VIDEO', mime: 'video/mp4', name: 'clip.mp4'),
        _attachment(type: 'AUDIO', mime: 'audio/mpeg', name: 'song.mp3'),
        _attachment(
          type: 'VOICE',
          mime: 'audio/ogg',
          name: 'voice.ogg',
          durationMs: 4000,
        ),
        _attachment(type: 'FILE', mime: 'application/pdf', name: 'invoice.pdf'),
      ]) {
        expect(
          forwardBlockOf(_message(text: '', attachments: [a])),
          isNull,
          reason: '${a['type']}',
        );
      }
      expect(
        forwardBlockOf(_message(attachments: [_attachment()])),
        isNull,
        reason: 'text with a file',
      );
    });

    test('a system line, an unsent message and a template are refused', () {
      expect(
        forwardBlockOf(_message(senderType: 'SYSTEM')),
        ForwardBlock.system,
      );
      expect(forwardBlockOf(_message(id: -3)), ForwardBlock.notSent);
      expect(
        forwardBlockOf(_message().copyWith(sendState: SendState.failed)),
        ForwardBlock.notSent,
      );
      expect(
        forwardBlockOf(_message().copyWith(sendState: SendState.sending)),
        ForwardBlock.notSent,
      );
      expect(
        forwardBlockOf(_message(type: 'TEMPLATE')),
        ForwardBlock.unsupported,
      );
    });

    test('a sticker or an unknown kind is refused, not passed off as a '
        'document', () {
      for (final type in ['STICKER', 'LOCATION', 'CONTACT']) {
        expect(
          forwardBlockOf(
            _message(
              text: '',
              attachments: [_attachment(type: type, mime: '')],
            ),
          ),
          ForwardBlock.unsupported,
          reason: type,
        );
      }
    });

    test('one unsupported attachment refuses the whole message', () {
      expect(
        forwardBlockOf(
          _message(
            attachments: [
              _attachment(),
              _attachment(id: 'b', type: 'STICKER'),
            ],
          ),
        ),
        ForwardBlock.unsupported,
      );
    });

    test('an attachment the server does not have ready is refused', () {
      for (final status in ['UNAVAILABLE', 'FAILED', 'FETCHING']) {
        expect(
          forwardBlockOf(_message(attachments: [_attachment(status: status)])),
          ForwardBlock.attachmentUnavailable,
          reason: status,
        );
      }
    });

    test('a message with nothing in it has nothing to send', () {
      expect(forwardBlockOf(_message(text: '  ')), ForwardBlock.nothingToSend);
    });
  });

  // -------------------------------------------------------------------------
  group('carrying it out', () {
    test('text: one reply to the destination, nothing staged', () async {
      final server = _Server();
      final fetcher = _Fetcher();
      final c = _container(server, fetcher);

      final sent = await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(text: '  Hello there  '),
            destinationConversationId: 21,
            clientMessageId: 'fwd-key-1',
          );

      expect(sent.id, 900);
      expect(server.where('POST', '/attachments/'), isEmpty);
      final reply = server.where('POST', '/conversations/21/reply/').single;
      expect(reply.body, {
        'text': 'Hello there',
        'client_message_id': 'fwd-key-1',
      });
      expect(fetcher.fetched, isEmpty);
      // Nothing was sent to the conversation it came from.
      expect(server.where('POST', '/conversations/5/reply/'), isEmpty);
    });

    test('a picture with a caption: fetched, staged in the destination, '
        'then sent with the draft id', () async {
      final server = _Server();
      final fetcher = _Fetcher();
      final c = _container(server, fetcher);

      await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(
              text: 'Look at this',
              attachments: [_attachment(id: 'att-9')],
            ),
            destinationConversationId: 21,
            clientMessageId: 'k',
          );

      expect(fetcher.fetched, ['att-9']);
      final staged = server.where('POST', '/conversations/21/attachments/');
      expect(staged, hasLength(1));
      expect(staged.single.form!.files.single.value.filename, 'photo.jpg');
      expect(
        staged.single.form!.files.single.value.contentType.toString(),
        'image/jpeg',
      );
      final reply = server.where('POST', '/conversations/21/reply/').single;
      expect(reply.body, {
        'text': 'Look at this',
        'attachment_ids': ['draft-1'],
        'client_message_id': 'k',
      });
      // Staged before it is sent.
      expect(
        server.requests.indexOf(staged.single),
        lessThan(server.requests.indexOf(reply)),
      );
    });

    test('a document with no text is a complete message', () async {
      final server = _Server();
      final c = _container(server, _Fetcher());
      await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(
              text: '',
              attachments: [
                _attachment(
                  type: 'FILE',
                  mime: 'application/pdf',
                  name: 'invoice.pdf',
                ),
              ],
            ),
            destinationConversationId: 22,
            clientMessageId: 'k',
          );
      final reply = server.where('POST', '/conversations/22/reply/').single;
      expect((reply.body as Map)['text'], '');
      expect((reply.body as Map)['attachment_ids'], ['draft-1']);
      expect(
        server
            .where('POST', '/attachments/')
            .single
            .form!
            .files
            .single
            .value
            .filename,
        'invoice.pdf',
      );
    });

    test('a voice note stays a voice note, with its length', () async {
      final server = _Server();
      final c = _container(server, _Fetcher());
      await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(
              text: '',
              attachments: [
                _attachment(
                  type: 'VOICE',
                  mime: 'audio/ogg',
                  name: 'voice.ogg',
                  durationMs: 4200,
                ),
              ],
            ),
            destinationConversationId: 21,
            clientMessageId: 'k',
          );
      final form = server.where('POST', '/attachments/').single.form!;
      final fields = {for (final f in form.fields) f.key: f.value};
      expect(fields['is_voice'], 'true');
      expect(fields['duration_ms'], '4200');
    });

    test('a voice note the platform describes only by its metadata is one '
        'too', () async {
      final server = _Server();
      final c = _container(server, _Fetcher());
      await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(
              text: '',
              attachments: [
                {
                  ..._attachment(
                    type: 'AUDIO',
                    mime: 'audio/ogg',
                    name: 'v.ogg',
                    durationMs: 3000,
                  ),
                  'metadata': {'whatsapp_type': 'voice'},
                },
              ],
            ),
            destinationConversationId: 21,
            clientMessageId: 'k',
          );
      final form = server.where('POST', '/attachments/').single.form!;
      expect({for (final f in form.fields) f.key: f.value}['is_voice'], 'true');
    });

    test('a plain audio file is not turned into a voice note', () async {
      final server = _Server();
      final c = _container(server, _Fetcher());
      await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(
              text: '',
              attachments: [
                _attachment(
                  type: 'AUDIO',
                  mime: 'audio/mpeg',
                  name: 'song.mp3',
                  durationMs: 215000,
                ),
              ],
            ),
            destinationConversationId: 21,
            clientMessageId: 'k',
          );
      final form = server.where('POST', '/attachments/').single.form!;
      expect([for (final f in form.fields) f.key], isNot(contains('is_voice')));
    });

    test('several attachments go in one reply, in order', () async {
      final server = _Server();
      final c = _container(server, _Fetcher());
      await c
          .read(messageForwarderProvider)
          .forward(
            message: _message(
              text: '',
              attachments: [
                _attachment(id: 'a'),
                _attachment(id: 'b', name: 'two.jpg'),
              ],
            ),
            destinationConversationId: 21,
            clientMessageId: 'k',
          );
      expect(server.where('POST', '/attachments/'), hasLength(2));
      expect(
        (server.where('POST', '/reply/').single.body as Map)['attachment_ids'],
        ['draft-1', 'draft-2'],
      );
    });

    test(
      'a message that cannot be forwarded asks the server for nothing',
      () async {
        final server = _Server();
        final fetcher = _Fetcher();
        final c = _container(server, fetcher);
        await expectLater(
          c
              .read(messageForwarderProvider)
              .forward(
                message: _message(senderType: 'SYSTEM'),
                destinationConversationId: 21,
                clientMessageId: 'k',
              ),
          throwsA(
            isA<ForwardException>().having(
              (e) => e.block,
              'block',
              ForwardBlock.system,
            ),
          ),
        );
        expect(server.requests, isEmpty);
        expect(fetcher.fetched, isEmpty);
      },
    );

    test('an attachment that cannot be fetched: nothing is sent, and the '
        'drafts already staged are put away', () async {
      final server = _Server();
      final fetcher = _Fetcher()..unavailable.add('b');
      final c = _container(server, fetcher);

      await expectLater(
        c
            .read(messageForwarderProvider)
            .forward(
              message: _message(
                attachments: [
                  _attachment(id: 'a'),
                  _attachment(id: 'b'),
                ],
              ),
              destinationConversationId: 21,
              clientMessageId: 'k',
            ),
        throwsA(
          isA<ForwardException>().having(
            (e) => e.block,
            'block',
            ForwardBlock.attachmentUnavailable,
          ),
        ),
      );

      expect(server.where('POST', '/reply/'), isEmpty);
      expect(
        server.where('DELETE', '/conversations/21/attachments/draft-1/'),
        hasLength(1),
      );
    });

    test('the server refusing the send: drafts are put away and the refusal '
        'is the error', () async {
      final server = _Server()
        ..replyStatus = 400
        ..replyMessage = 'The 24-hour window is closed.';
      final c = _container(server, _Fetcher());

      await expectLater(
        c
            .read(messageForwarderProvider)
            .forward(
              message: _message(attachments: [_attachment()]),
              destinationConversationId: 21,
              clientMessageId: 'k',
            ),
        throwsA(
          isA<Object>().having((e) => '$e', 'text', contains('24-hour window')),
        ),
      );
      expect(
        server.where('DELETE', '/conversations/21/attachments/draft-1/'),
        hasLength(1),
      );
    });

    test('a staging refusal (file too large) stops before any send', () async {
      final server = _Server()..stageStatus = 413;
      final c = _container(server, _Fetcher());
      await expectLater(
        c
            .read(messageForwarderProvider)
            .forward(
              message: _message(attachments: [_attachment()]),
              destinationConversationId: 21,
              clientMessageId: 'k',
            ),
        throwsA(isA<Object>()),
      );
      expect(server.where('POST', '/reply/'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('what the agent is told', () {
    final en = AppLocalizationsEn();
    ApiException api(int status, [String message = '']) =>
        ApiException(statusCode: status, message: message);

    test('each refusal in its own words, the server\'s own for a 400', () {
      expect(
        forwardErrorMessage(en, api(400, 'The 24-hour window is closed.')),
        'The 24-hour window is closed.',
      );
      expect(
        forwardErrorMessage(en, api(400)),
        en.forwardDestinationRefusedMessage,
      );
      expect(
        forwardErrorMessage(en, api(403)),
        en.forwardPermissionDeniedMessage,
      );
      expect(
        forwardErrorMessage(en, api(404)),
        en.forwardDestinationGoneMessage,
      );
      expect(forwardErrorMessage(en, api(429)), en.forwardTooManyMessage);
      expect(forwardErrorMessage(en, api(500)), en.forwardFailedMessage);
      expect(forwardErrorMessage(en, api(502)), en.forwardFailedMessage);
      expect(forwardErrorMessage(en, StateError('x')), en.forwardFailedMessage);
      expect(
        forwardErrorMessage(
          en,
          const ForwardException(ForwardBlock.attachmentUnavailable),
        ),
        en.forwardAttachmentUnavailable,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the sheet', () {
    testWidgets('lists the other conversations, told apart by channel and '
        'number, and leaves out the one it came from', (tester) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      expect(find.text('Forward to'), findsOneWidget);
      expect(_row(5), findsNothing); // the source
      expect(_row(21), findsOneWidget);
      expect(_row(22), findsOneWidget);
      expect(_row(23), findsOneWidget);
      // Two threads of one name, distinguishable.
      expect(find.text('WhatsApp · Support Line'), findsNWidgets(2));
      expect(find.text('WhatsApp · Sales Line'), findsOneWidget);
      expect(find.text('+201000000021'), findsOneWidget);
      expect(find.text('+201000000022'), findsOneWidget);
      // Nothing is sent just by looking.
      expect(server.where('POST', '/reply/'), isEmpty);
      // The button waits for a choice.
      expect(tester.widget<FilledButton>(_confirmButton).onPressed, isNull);
    });

    testWidgets('only the accounts the inbox shows are searched', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);
      final list = server.where('GET', '/conversations/').first;
      expect(list.query['channel_connections'], '1');
    });

    testWidgets('searching asks the server and narrows the list', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      await tester.enterText(
        find.byKey(const Key('forwardSearchField')),
        'omar',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        server.where('GET', '/conversations/').last.query['search'],
        'omar',
      );
      expect(_row(23), findsOneWidget);
      expect(_row(21), findsNothing);
    });

    testWidgets('no match says so, and nothing can be sent', (tester) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('forwardSearchField')),
        'zzz',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forwardNoResults')), findsOneWidget);
      expect(tester.widget<FilledButton>(_confirmButton).onPressed, isNull);
    });

    testWidgets('more results than one page says to narrow the search', (
      tester,
    ) async {
      final server = _Server()..listHasMore = true;
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);
      expect(find.byKey(const Key('forwardMoreHint')), findsOneWidget);
    });

    testWidgets('a list that will not load can be retried', (tester) async {
      final server = _Server()..listStatus = 503;
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(_row(21), findsNothing);

      server.listStatus = 200;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(_row(21), findsOneWidget);
    });

    testWidgets('choosing shows who, and asks before anything is sent', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      await tester.tap(_row(22));
      await tester.pump();
      expect(find.text('Forward to Mona Adel'), findsOneWidget);

      await tester.tap(_confirmButton);
      await tester.pumpAndSettle();
      // The confirmation names the customer and the channel, and shows what
      // is about to be sent.
      expect(find.byKey(const Key('forwardConfirmDialog')), findsOneWidget);
      expect(
        find.text('It will be sent to Mona Adel on WhatsApp · Sales Line.'),
        findsOneWidget,
      );
      expect(find.text('Our opening hours are 9 to 5.'), findsOneWidget);
      expect(server.where('POST', '/reply/'), isEmpty);

      // Cancelling sends nothing and keeps the sheet.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.where('POST', '/reply/'), isEmpty);
      expect(find.text('Forward to'), findsOneWidget);
    });

    testWidgets('confirming sends to that conversation, closes the sheet, and '
        'says so', (tester) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      await _chooseAndConfirm(tester, 22);
      await tester.pumpAndSettle();

      final reply = server.where('POST', '/reply/').single;
      expect(reply.path, endsWith('/conversations/22/reply/'));
      expect((reply.body as Map)['text'], 'Our opening hours are 9 to 5.');
      expect(find.text('Forward to'), findsNothing); // the sheet closed
      expect(find.text('Forwarded to Mona Adel.'), findsOneWidget);
      // Back where it was: the page underneath is untouched.
      expect(find.text('forward'), findsOneWidget);
      // The lists that show the destination are brought up to date.
      expect(_FakeInbox.refreshes, 1);
    });

    testWidgets('a forwarded picture goes through the attachment flow', (
      tester,
    ) async {
      final server = _Server();
      final fetcher = _Fetcher();
      await tester.pumpWidget(
        _app(
          server,
          fetcher,
          message: _message(
            text: '',
            attachments: [_attachment(id: 'att-3')],
          ),
        ),
      );
      await _open(tester);
      await tester.runAsync(() async {
        await _chooseAndConfirm(tester, 21);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(fetcher.fetched, ['att-3']);
      expect(
        server.where('POST', '/conversations/21/attachments/'),
        hasLength(1),
      );
      expect(
        (server.where('POST', '/reply/').single.body as Map)['attachment_ids'],
        ['draft-1'],
      );
      expect(find.text('Forwarded to Mona Adel.'), findsOneWidget);
    });

    testWidgets('while it is sending: busy, locked, and a second tap does '
        'nothing', (tester) async {
      final server = _Server()..holdReply = Completer<void>();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      await _chooseAndConfirm(tester, 21);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Forwarding…'), findsOneWidget);
      expect(tester.widget<FilledButton>(_confirmButton).onPressed, isNull);
      // Tapping the busy button, and a row, changes nothing.
      await tester.tap(_confirmButton, warnIfMissed: false);
      await tester.tap(_row(22), warnIfMissed: false);
      await tester.pump();
      expect(server.where('POST', '/reply/'), hasLength(1));
      expect(find.text('Forward to Mona Adel'), findsNothing);

      server.holdReply!.complete();
      await tester.pumpAndSettle();
      expect(server.where('POST', '/reply/'), hasLength(1));
      expect(find.text('Forwarded to Mona Adel.'), findsOneWidget);
    });

    testWidgets('a double tap on Forward in the dialog sends once and does '
        'not close the sheet twice', (tester) async {
      final server = _Server()..holdReply = Completer<void>();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      await tester.tap(_row(21));
      await tester.pump();
      await tester.tap(_confirmButton);
      await tester.pumpAndSettle();
      // Two presses with no frame between them. (Flutter itself ignores
      // pointer events on a route that is closing; calling the handler
      // directly is what proves this sheet does not depend on that.)
      final send = tester.widget<FilledButton>(_dialogSend).onPressed!;
      send();
      send();
      await tester.pump(const Duration(milliseconds: 50));

      expect(server.where('POST', '/reply/'), hasLength(1));
      // The sheet is still there, sending — not popped by the second tap.
      expect(find.text('Forwarding…'), findsOneWidget);

      server.holdReply!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Forwarded to Mona Adel.'), findsOneWidget);
    });

    testWidgets('two quick taps on the sheet\'s button open one dialog', (
      tester,
    ) async {
      final server = _Server();
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);
      await tester.tap(_row(21));
      await tester.pump();
      await tester.tap(_confirmButton);
      await tester.tap(_confirmButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forwardConfirmDialog')), findsOneWidget);
    });

    for (final (status, expected) in [
      (400, 'The 24-hour window is closed.'),
      (403, AppLocalizationsEn().forwardPermissionDeniedMessage),
      (404, AppLocalizationsEn().forwardDestinationGoneMessage),
      (429, AppLocalizationsEn().forwardTooManyMessage),
      (500, AppLocalizationsEn().forwardFailedMessage),
    ]) {
      testWidgets('the server answering $status: shown, nothing reported as '
          'sent, and it can be tried again', (tester) async {
        final server = _Server()
          ..replyStatus = status
          ..replyMessage = 'The 24-hour window is closed.';
        await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
        await _open(tester);

        await _chooseAndConfirm(tester, 21);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('forwardError')), findsOneWidget);
        expect(find.text(expected), findsOneWidget);
        expect(find.textContaining('Forwarded to'), findsNothing);
        expect(find.text('Forward to'), findsOneWidget); // still open
        expect(_FakeInbox.refreshes, 0);
        expect(
          tester.widget<FilledButton>(_confirmButton).onPressed,
          isNotNull,
        );
      });
    }

    testWidgets('a retry after a failure sends the same idempotency key', (
      tester,
    ) async {
      final server = _Server()..replyNetworkDown = true;
      await tester.pumpWidget(_app(server, _Fetcher(), message: _message()));
      await _open(tester);

      await _chooseAndConfirm(tester, 21);
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizationsEn().forwardFailedMessage),
        findsOneWidget,
      );

      server.replyNetworkDown = false;
      await tester.tap(_confirmButton);
      await tester.pumpAndSettle();
      await tester.tap(_dialogSend);
      await tester.pumpAndSettle();

      final keys = [
        for (final r in server.where('POST', '/reply/'))
          (r.body as Map)['client_message_id'],
      ];
      expect(keys, hasLength(2));
      expect(keys.first, keys.last);
      expect(find.text('Forwarded to Mona Adel.'), findsOneWidget);
    });

    testWidgets('an attachment that cannot be fetched is reported and nothing '
        'is sent', (tester) async {
      final server = _Server();
      final fetcher = _Fetcher()..unavailable.add('att-1');
      await tester.pumpWidget(
        _app(
          server,
          fetcher,
          message: _message(text: 'x', attachments: [_attachment()]),
        ),
      );
      await _open(tester);
      await _chooseAndConfirm(tester, 21);
      await tester.pumpAndSettle();

      expect(
        find.text(AppLocalizationsEn().forwardAttachmentUnavailable),
        findsOneWidget,
      );
      expect(server.where('POST', '/reply/'), isEmpty);
    });

    testWidgets('a message that cannot be forwarded says why and opens '
        'nothing', (tester) async {
      final server = _Server();
      await tester.pumpWidget(
        _app(server, _Fetcher(), message: _message(type: 'TEMPLATE')),
      );
      await tester.tap(find.text('forward'));
      await tester.pumpAndSettle();

      expect(find.text('Forward to'), findsNothing);
      expect(
        find.text(AppLocalizationsEn().forwardBlockedUnsupported),
        findsOneWidget,
      );
      expect(server.requests, isEmpty);
    });

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic RTL' : 'English LTR'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('layout and wording — $label', (tester) async {
          final server = _Server();
          await tester.pumpWidget(
            _app(
              server,
              _Fetcher(),
              message: _message(attachments: [_attachment()]),
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await _open(tester);
          expect(tester.takeException(), isNull);

          expect(find.text(l10n.forwardSheetTitle), findsOneWidget);
          expect(find.text(l10n.forwardChooseHint), findsOneWidget);
          expect(find.text('Mona Adel'), findsNWidgets(2));
          // The number reads left to right in both.
          final phone = tester.widget<Text>(find.text('+201000000021'));
          expect(phone.textDirection, TextDirection.ltr);

          await tester.tap(_row(21));
          await tester.pump();
          expect(find.text(l10n.forwardToNamed('Mona Adel')), findsOneWidget);
          await tester.tap(_confirmButton);
          await tester.pumpAndSettle();
          expect(find.text(l10n.forwardConfirmTitle), findsOneWidget);
          expect(find.text(l10n.forwardAttachmentCount(1)), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (arabic) {
            expect(l10n.forwardMessageAction, 'إعادة توجيه');
          }
        });
      }
    }

    testWidgets('a narrow screen with a long name does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final server = _Server()
        ..conversations = [
          _conversation(
            21,
            'A very long customer name that keeps on going and going',
            '+20 1000 0000 21 0000 0000 0000',
            'A very long account name for a sales line',
          ),
        ];
      await tester.pumpWidget(
        _app(
          server,
          _Fetcher(),
          message: _message(),
          locale: const Locale('ar'),
        ),
      );
      await _open(tester);
      await tester.tap(_row(21));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('the message menu', () {
    Message bubbleMessage() => _message(id: 3, text: 'Hello there');

    Widget bubble({VoidCallback? onForward, VoidCallback? onReply}) =>
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: MessageBubble(
                  message: bubbleMessage(),
                  provider: 'WHATSAPP',
                  onReply: onReply,
                  onForward: onForward,
                ),
              ),
            ),
          ),
        );

    testWidgets('Forward is in the long-press menu beside Reply and Copy', (
      tester,
    ) async {
      var forwarded = 0;
      var replied = 0;
      await tester.pumpWidget(
        bubble(onForward: () => forwarded++, onReply: () => replied++),
      );
      await tester.longPress(find.text('Hello there'));
      await tester.pumpAndSettle();

      expect(find.text('Forward'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.byKey(const Key('messageForwardAction')));
      await tester.pumpAndSettle();
      expect(forwarded, 1);
      expect(replied, 0);
    });

    testWidgets('without it the menu is what it was', (tester) async {
      await tester.pumpWidget(bubble(onReply: () {}));
      await tester.longPress(find.text('Hello there'));
      await tester.pumpAndSettle();
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('Forward alone is enough to open the menu', (tester) async {
      await tester.pumpWidget(bubble(onForward: () {}));
      await tester.longPress(find.text('Hello there'));
      await tester.pumpAndSettle();
      expect(find.text('Forward'), findsOneWidget);
    });

    testWidgets('the Arabic label', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: MessageBubble(
                  message: bubbleMessage(),
                  provider: 'WHATSAPP',
                  onForward: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Hello there'));
      await tester.pumpAndSettle();
      expect(find.text('إعادة توجيه'), findsOneWidget);
    });
  });
}
