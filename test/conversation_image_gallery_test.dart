/// The conversation image gallery: every inline image of the conversation,
/// the agent's and the customer's, in timeline order — swipeable, zoomable,
/// and honest about history that is not loaded yet.
///
/// Runs the real conversation screen against a stub backend with two pages
/// of history. Image bytes never load in a widget test (no network), which
/// doubles as the "image failed" case.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/image_gallery.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

String _url(String name) => 'https://cdn.example.com/$name.jpg';

Map<String, dynamic> _image(String name, {String type = 'IMAGE'}) => {
  'type': type,
  'id': 'att-$name',
  'url': _url(name),
  'mime_type': 'image/jpeg',
  'file_name': '$name.jpg',
};

Map<String, dynamic> _message(
  int id, {
  List<Map<String, dynamic>> attachments = const [],
  bool mine = false,
  String text = '',
}) => {
  'id': id,
  'direction': mine ? 'OUTBOUND' : 'INBOUND',
  'sender_type': mine ? 'AGENT' : 'CUSTOMER',
  'sender_name': mine ? 'Sam Agent' : 'Customer',
  'message_type': attachments.isEmpty ? 'TEXT' : attachments.first['type'],
  'text': attachments.isEmpty && text.isEmpty ? 'Message $id' : text,
  'attachments': attachments,
  'delivery_status': 'DELIVERED',
  'sent_at': DateTime.utc(
    2026,
    11,
    1,
    10,
  ).add(Duration(minutes: id)).toIso8601String(),
};

/// Page 1 (newest): customer image A, agent image B, a two-image message
/// C+D, a video, an image sent as a *document*, a voice-free text, customer
/// image E. Page 2 (older): image Z and text.
class _Server implements HttpClientAdapter {
  bool olderFails = false;

  /// A long history: page 2 is text only, and Z moves to page 3.
  bool textOnlyPage = false;
  final pageRequests = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final path = options.path;
    if (path == '/conversations/42/messages/') {
      final page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
      pageRequests.add(page);
      if (page == 1) {
        return _json({
          'count': 12,
          'next': 'https://api.example.com/conversations/42/messages/?page=2',
          'results': [
            _message(20),
            _message(21, attachments: [_image('A')]),
            _message(22, attachments: [_image('B')], mine: true),
            _message(23, attachments: [_image('C'), _image('D')]),
            _message(
              24,
              attachments: [
                {
                  'type': 'VIDEO',
                  'id': 'att-video',
                  'url': 'https://cdn.example.com/clip.mp4',
                  'mime_type': 'video/mp4',
                  'file_name': 'clip.mp4',
                },
              ],
            ),
            _message(25, attachments: [_image('doc', type: 'FILE')]),
            _message(26),
            _message(27, attachments: [_image('E')]),
          ],
        });
      }
      if (olderFails) {
        return _json({
          'error': {'code': 'server_error', 'message': 'Down.'},
        }, 500);
      }
      if (textOnlyPage && page == 2) {
        return _json({
          'count': 30,
          'next': 'https://api.example.com/conversations/42/messages/?page=3',
          'results': [for (var id = 5; id < 15; id++) _message(id)],
        });
      }
      return _json({
        'count': 12,
        'next': null,
        'results': [
          _message(2, attachments: [_image('Z')]),
          _message(3),
        ],
      });
    }
    if (path.contains('/notes/')) return _json([]);
    if (path.contains('/saved-replies/')) return _json({'results': []});
    if (path == '/conversations/42/') {
      return _json({
        'id': 42,
        'customer': {'id': 42, 'display_name': 'Customer', 'initials': 'C'},
        'provider': 'WHATSAPP',
        'status': 'OPEN',
        'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
      });
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

const _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply},
  visibilityScope: 'ALL',
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Server server, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee),
      ],
      child: MaterialApp(
        locale: locale,
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

Finder _thumb(String name) => find.byWidgetPredicate(
  (w) => w is CachedNetworkImage && w.imageUrl == _url(name),
);

Future<void> _tapThumb(WidgetTester tester, String name) async {
  await tester.tap(_thumb(name).first, warnIfMissed: false);
  await _frames(tester, 12);
}

String _counter(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('galleryCounter'))).data!;

/// The key of the page on screen.
String _shown(WidgetTester tester) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final pages = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('galleryPage_'),
  );
  for (final e in pages.evaluate()) {
    final center = tester.getCenter(find.byWidget(e.widget));
    if (center.dx > 0 && center.dx < screen.width) {
      return (e.widget.key! as ValueKey<String>).value.substring(
        'galleryPage_'.length,
      );
    }
  }
  return '';
}

Future<void> _swipe(WidgetTester tester, {required bool towardNext}) async {
  final rtl =
      Directionality.of(
        tester.element(find.byKey(const ValueKey('galleryPages'))),
      ) ==
      TextDirection.rtl;
  // In LTR the next image is to the right, reached by dragging left.
  final dx = (towardNext != rtl) ? -400.0 : 400.0;
  await tester.fling(
    find.byKey(const ValueKey('galleryPages')),
    Offset(dx, 0),
    1500,
  );
  await _frames(tester, 16);
}

Future<void> _doubleTap(WidgetTester tester) async {
  final target = find.byKey(const ValueKey('galleryPages'));
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(target);
  await _frames(tester, 10);
}

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(
      find.descendant(
        of: find.byKey(ValueKey('galleryPage_${_shown(tester)}')),
        matching: find.byType(InteractiveViewer),
      ),
    )
    .transformationController!
    .value
    .getMaxScaleOnAxis();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which images, in which order', () {
    Message m(Map<String, dynamic> json) => Message.fromJson(json);

    test('every inline image, both senders, timeline and attachment order; '
        'no video, document, audio or text', () {
      final images = galleryImagesOf([
        m(_message(21, attachments: [_image('A')])),
        m(_message(22, attachments: [_image('B')], mine: true)),
        m(_message(23, attachments: [_image('C'), _image('D')])),
        m(
          _message(
            24,
            attachments: [
              {
                'type': 'VIDEO',
                'id': 'v',
                'url': 'https://cdn.example.com/v.mp4',
                'mime_type': 'video/mp4',
              },
            ],
          ),
        ),
        m(_message(25, attachments: [_image('doc', type: 'FILE')])),
        m(
          _message(
            26,
            attachments: [
              {
                'type': 'AUDIO',
                'id': 'a',
                'url': 'https://cdn.example.com/a.ogg',
                'mime_type': 'audio/ogg',
                'duration_ms': 3000,
              },
            ],
          ),
        ),
        m(_message(27)),
        m(_message(28, attachments: [_image('E')])),
      ]);
      expect(
        [for (final i in images) i.key],
        ['21:0', '22:0', '23:0', '23:1', '28:0'],
      );
    });

    test('an image with nothing to load is left out', () {
      final images = galleryImagesOf([
        m(
          _message(
            30,
            attachments: [
              {'type': 'IMAGE', 'id': '', 'url': '', 'mime_type': 'image/png'},
            ],
          ),
        ),
      ]);
      expect(images, isEmpty);
    });
  });

  testWidgets('a middle image opens on itself; the counter admits older '
      'history is not loaded', (tester) async {
    await _open(tester, _Server());
    await _tapThumb(tester, 'B'); // the agent's own image

    expect(find.byKey(const ValueKey('imageGallery')), findsOneWidget);
    expect(_shown(tester), '22:0');
    expect(_counter(tester), '2 / 5+');
    expect(find.byKey(const ValueKey('galleryPrevious')), findsOneWidget);
    expect(find.byKey(const ValueKey('galleryNext')), findsOneWidget);
  });

  testWidgets('swiping both ways crosses senders and multi-image messages', (
    tester,
  ) async {
    await _open(tester, _Server());
    await _tapThumb(tester, 'B');

    await _swipe(tester, towardNext: true);
    expect(_shown(tester), '23:0');
    expect(_counter(tester), '3 / 5+');
    await _swipe(tester, towardNext: true);
    expect(_shown(tester), '23:1');
    await _swipe(tester, towardNext: true);
    // The video and the document are skipped.
    expect(_shown(tester), '27:0');
    expect(_counter(tester), '5 / 5+');

    await _swipe(tester, towardNext: false);
    expect(_shown(tester), '23:1');
  });

  testWidgets('a tap on the second picture of a grid opens on that picture', (
    tester,
  ) async {
    await _open(tester, _Server());
    await _tapThumb(tester, 'D');
    expect(_shown(tester), '23:1');
    expect(_counter(tester), '4 / 5+');
  });

  testWidgets('the last image: no next, and swiping on does not leave it', (
    tester,
  ) async {
    await _open(tester, _Server());
    await _tapThumb(tester, 'E');
    expect(_counter(tester), '5 / 5+');
    expect(find.byKey(const ValueKey('galleryNext')), findsNothing);
    await _swipe(tester, towardNext: true);
    expect(_shown(tester), '27:0');
  });

  testWidgets('the first loaded image pulls in older pages — into the '
      'gallery only — and the counter becomes exact', (tester) async {
    final server = _Server();
    final c = await _open(tester, server);
    final before = c.read(conversationControllerProvider(42)).value!;
    await _tapThumb(tester, 'A');
    await _frames(tester, 10);

    // Older history arrived in front; A stays on screen, now second.
    expect(server.pageRequests.where((p) => p == 2), hasLength(1));
    expect(_shown(tester), '21:0');
    expect(_counter(tester), '2 / 6');
    await _swipe(tester, towardNext: false);
    expect(_shown(tester), '2:0');
    expect(_counter(tester), '1 / 6');
    expect(find.byKey(const ValueKey('galleryPrevious')), findsNothing);
    // And the first image is a real boundary.
    await _swipe(tester, towardNext: false);
    expect(_shown(tester), '2:0');

    // The thread underneath was not touched.
    final after = c.read(conversationControllerProvider(42)).value!;
    expect(after.messages.length, before.messages.length);
    expect(after.hasMore, isTrue);
    expect(after.nextPage, before.nextPage);
  });

  testWidgets('a long history: pages without images are passed over until '
      'an older image turns up', (tester) async {
    final server = _Server()..textOnlyPage = true;
    await _open(tester, server);
    await _tapThumb(tester, 'A');
    await _frames(tester, 16);

    expect(server.pageRequests.where((p) => p == 2), hasLength(1));
    expect(server.pageRequests.where((p) => p == 3), hasLength(1));
    expect(_shown(tester), '21:0');
    expect(_counter(tester), '2 / 6');
    await _swipe(tester, towardNext: false);
    expect(_shown(tester), '2:0');
  });

  testWidgets('older history that fails to load says so, and a retry works', (
    tester,
  ) async {
    final server = _Server()..olderFails = true;
    await _open(tester, server);
    await _tapThumb(tester, 'A');
    await _frames(tester, 10);

    expect(find.byKey(const ValueKey('galleryEarlierFailed')), findsOneWidget);
    expect(_counter(tester), '1 / 5+');

    server.olderFails = false;
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('galleryEarlierFailed')),
        matching: find.byType(TextButton),
      ),
    );
    await _frames(tester, 10);
    expect(find.byKey(const ValueKey('galleryEarlierFailed')), findsNothing);
    expect(_counter(tester), '2 / 6');
  });

  testWidgets('double-tap zooms, the pager stands aside, double-tap again '
      'restores swiping', (tester) async {
    await _open(tester, _Server());
    await _tapThumb(tester, 'B');

    await _doubleTap(tester);
    expect(_scale(tester), greaterThan(2));
    expect(
      tester
          .widget<PageView>(find.byKey(const ValueKey('galleryPages')))
          .physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    // A drag while zoomed is a pan, never a page change.
    await _swipe(tester, towardNext: true);
    expect(_shown(tester), '22:0');
    expect(find.byKey(const ValueKey('galleryNext')), findsNothing);

    await _doubleTap(tester);
    expect(_scale(tester), closeTo(1, 0.01));
    await _swipe(tester, towardNext: true);
    expect(_shown(tester), '23:0');
  });

  testWidgets('pinch-to-zoom and panning are available on every image', (
    tester,
  ) async {
    await _open(tester, _Server());
    await _tapThumb(tester, 'C');
    final viewer = tester.widget<InteractiveViewer>(
      find.descendant(
        of: find.byKey(const ValueKey('galleryPage_23:0')),
        matching: find.byType(InteractiveViewer),
      ),
    );
    expect(viewer.scaleEnabled, isTrue);
    expect(viewer.maxScale, 4);
    expect(viewer.minScale, 1);
  });

  testWidgets('an image that cannot load says so and offers a retry', (
    tester,
  ) async {
    // A file that is there but is not an image: the same failure path a
    // broken or expired URL takes (a widget test has no network or cache
    // plugins to fail on).
    final file = File(
      '${Directory.systemTemp.createTempSync('gallery').path}/broken.jpg',
    )..writeAsBytesSync(List.filled(64, 7));
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final broken = GalleryImage(
      key: '9:0',
      attachment: MessageAttachment(
        type: 'IMAGE',
        fileName: 'broken.jpg',
        localFilePath: file.path,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.create(cookieJar: CookieJar()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageGalleryViewer(images: [broken], initialKey: '9:0'),
        ),
      ),
    );
    Future<void> settleDecode() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    }

    await settleDecode();
    expect(find.byKey(const ValueKey('galleryImageFailed')), findsOneWidget);
    expect(find.text("Couldn't load this image."), findsOneWidget);
    // One image: no counter, no previous/next.
    expect(find.byKey(const ValueKey('galleryCounter')), findsNothing);
    expect(find.byKey(const ValueKey('galleryNext')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('galleryRetry')));
    await settleDecode();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('galleryImageFailed')), findsOneWidget);
    // Let the page's double-tap detector's window close.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('closing returns to the thread exactly as it was', (
    tester,
  ) async {
    final c = await _open(tester, _Server());
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ConversationScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final offset = list.position.pixels;
    final before = c.read(conversationControllerProvider(42)).value!;

    await _tapThumb(tester, 'A'); // also loads older pages, into the gallery
    await _frames(tester, 10);
    await tester.tap(find.byKey(const ValueKey('galleryClose')));
    await _frames(tester, 12);

    expect(find.byKey(const ValueKey('imageGallery')), findsNothing);
    expect(list.position.pixels, offset);
    final after = c.read(conversationControllerProvider(42)).value!;
    expect(after.messages.length, before.messages.length);
  });

  testWidgets('videos and documents keep their own taps', (tester) async {
    await _open(tester, _Server());
    await tester.tap(find.text('doc.jpg').first, warnIfMissed: false);
    await _frames(tester, 6);
    expect(find.byKey(const ValueKey('imageGallery')), findsNothing);
  });

  testWidgets('Arabic: counter in Arabic, newer images to the left', (
    tester,
  ) async {
    await _open(tester, _Server(), locale: const Locale('ar'));
    await _tapThumb(tester, 'B');
    expect(_counter(tester), '2 من 5+');
    double x(String key) => tester
        .getCenter(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(IconButton),
          ),
        )
        .dx;
    final previous = x('galleryPrevious');
    final next = x('galleryNext');
    // Right to left: "previous" sits on the right, "next" on the left.
    expect(previous, greaterThan(next));
    await _swipe(tester, towardNext: true);
    expect(_shown(tester), '23:0');
  });

  testWidgets('outside a conversation thread, a bubble\'s gallery covers '
      'its own message', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final message = Message.fromJson(
      _message(23, attachments: [_image('C'), _image('D')]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient.create(cookieJar: CookieJar()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(message: message, provider: 'WHATSAPP'),
          ),
        ),
      ),
    );
    await _frames(tester, 10);
    await _tapThumb(tester, 'D');
    expect(_shown(tester), '23:1');
    expect(_counter(tester), '2 / 2');
  });
}
