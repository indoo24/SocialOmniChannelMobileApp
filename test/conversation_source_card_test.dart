/// The conversation-source ("came from a Meta ad") card: parsing of the
/// web-derived `attribution` contract, and its behaviour in the real
/// conversation screen — placement above the oldest message, pagination,
/// link opening, RTL, rebuilds, and "Jump to source".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/config/environment.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_attribution.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/external_link.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Payloads
// ---------------------------------------------------------------------------

Map<String, dynamic> _referral({
  Object? id = 7,
  String? source = 'META_PAID_AD',
  String? platform = 'FACEBOOK',
  String? url = 'https://www.facebook.com/ads/library/?id=123',
  String? headline = 'Deep hydration course — last seats',
  String? summary = 'Everything your hair needs in one routine',
  bool truncated = true,
  String? observedAt = '2026-09-25T10:55:00Z',
  String? creative,
}) => {
  'creative_thumbnail_url': ?creative,
  'id': ?id,
  'source': ?source,
  'platform_hint': ?platform,
  'source_url': ?url,
  'headline': ?headline,
  'summary': ?summary,
  'summary_truncated': truncated,
  'observed_at': ?observedAt,
};

Map<String, dynamic> _conversation({Object? attribution}) => {
  'id': 42,
  'customer': {'id': 7, 'display_name': 'Sarah', 'initials': 'S'},
  'provider': 'WHATSAPP',
  'channel_name': 'Scenario Sales',
  'status': 'OPEN',
  'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
  'attribution': attribution,
};

Map<String, dynamic> _message(int id) => {
  'id': id,
  'text': 'Message number $id',
  'direction': id.isEven ? 'OUTBOUND' : 'INBOUND',
  'sender_name': id.isEven ? 'Sam Agent' : 'Sarah',
  'sent_at': DateTime.utc(
    2026,
    9,
    25,
    10,
  ).add(Duration(minutes: id)).toIso8601String(),
  'delivery_status': 'DELIVERED',
};

// ---------------------------------------------------------------------------
// Stub backend
// ---------------------------------------------------------------------------

class _Server implements HttpClientAdapter {
  _Server({required this.detail, required this.pages});

  Map<String, dynamic> detail;

  /// Page number → message ids on that page (newest page first).
  final Map<int, List<int>> pages;
  int detailFetches = 0;
  final List<int> pagesFetched = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final path = options.path;
    if (path == '/conversations/42/messages/') {
      final page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
      pagesFetched.add(page);
      final ids = pages[page] ?? const [];
      return _json({
        'count': pages.values.expand((p) => p).length,
        'next': pages.containsKey(page + 1)
            ? 'https://api.test/conversations/42/messages/?page=${page + 1}'
            : null,
        'previous': null,
        'results': [for (final id in ids) _message(id)],
      });
    }
    if (path.contains('/notes/')) return _json([]);
    if (path == '/conversations/42/') {
      detailFetches++;
      return _json(detail);
    }
    if (path.contains('/saved-replies/')) return _json({'results': []});
    return _json({});
  }

  static ResponseBody _json(Object body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
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

Future<_Server> _open(
  WidgetTester tester, {
  Object? attribution,
  Map<int, List<int>>? pages,
  Locale? locale,
  ThemeData? theme,
  Size size = const Size(800, 1400),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final server = _Server(
    detail: _conversation(attribution: attribution),
    pages:
        pages ??
        {
          1: [1, 2, 3],
        },
  );
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
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
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A creative's image load keeps scheduling frames; bounded pumps are
    // enough for the thread and the card to be on screen.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return server;
}

final _card = find.byKey(const ValueKey('conversationSourceCard'));
final _pill = find.byKey(const ValueKey('conversationSourceJump'));
final _creative = find.byKey(const ValueKey('conversationSourceCreative'));
final _creativeFrame = find.byKey(
  const ValueKey('conversationSourceCreativeFrame'),
);
const _creativePath =
    '/api/referral-creatives/0b5f3c1e-8d2a-4f6b-9c7e-1a2b3c4d5e6f/content/';

void main() {
  group('ConversationAttribution parsing', () {
    test('1. a full attribution', () {
      final a = ConversationAttribution.fromJson({
        'first': _referral(),
        'latest': _referral(),
        'has_multiple': false,
      })!;
      final r = a.primary;
      expect(r.id, '7');
      expect(r.source, ReferralSource.metaPaidAd);
      expect(r.platformHint, 'FACEBOOK');
      expect(r.platformName, 'Facebook');
      expect(
        r.openableUrl,
        Uri.parse('https://www.facebook.com/ads/library/?id=123'),
      );
      expect(r.headline, 'Deep hydration course — last seats');
      expect(r.summary, 'Everything your hair needs in one routine');
      expect(r.summaryTruncated, isTrue);
      expect(r.observedAt, DateTime.utc(2026, 9, 25, 10, 55).toLocal());
      expect(a.mostRecent, isNull);
    });

    test('2 + 3. first only, latest only', () {
      final firstOnly = ConversationAttribution.fromJson({
        'first': _referral(headline: 'First'),
      })!;
      expect(firstOnly.primary.headline, 'First');
      final latestOnly = ConversationAttribution.fromJson({
        'latest': _referral(headline: 'Latest'),
      })!;
      expect(latestOnly.primary.headline, 'Latest');
    });

    test('4 + 5. both, with and without has_multiple', () {
      Map<String, dynamic> both({required bool multiple, Object? latestId}) => {
        'first': _referral(id: 1, headline: 'First'),
        'latest': _referral(id: latestId, headline: 'Latest'),
        'has_multiple': multiple,
      };

      expect(
        ConversationAttribution.fromJson(
          both(multiple: false, latestId: 2),
        )!.mostRecent,
        isNull,
        reason: 'has_multiple false: one card only',
      );
      expect(
        ConversationAttribution.fromJson(
          both(multiple: true, latestId: 1),
        )!.mostRecent,
        isNull,
        reason: 'same referral: not drawn twice',
      );
      final multiple = ConversationAttribution.fromJson(
        both(multiple: true, latestId: 2),
      )!;
      expect(multiple.primary.headline, 'First');
      expect(multiple.mostRecent!.headline, 'Latest');
    });

    test('6. missing optional fields are simply empty', () {
      final r = ConversationAttribution.fromJson({
        'first': <String, dynamic>{},
      })!.primary;
      expect(r.id, isNull);
      expect(r.source, ReferralSource.unknown);
      expect(r.platformName, isNull);
      expect(r.headline, isEmpty);
      expect(r.summary, isEmpty);
      expect(r.summaryTruncated, isFalse);
      expect(r.observedAt, isNull);
      expect(r.openableUrl, isNull);
    });

    test('7. unknown source and platform fall back, never throw', () {
      final r = ConversationAttribution.fromJson({
        'first': _referral(source: 'TIKTOK_SPARK_AD', platform: 'THREADS'),
      })!.primary;
      expect(r.source, ReferralSource.unknown);
      expect(r.platformHint, 'THREADS');
      expect(r.platformName, isNull);
    });

    test('8 + 9. only an https URL with a host is openable', () {
      String? open(String? url) => ConversationAttribution.fromJson({
        'first': _referral(url: url),
      })!.primary.openableUrl?.toString();

      expect(open('https://fb.me/abc'), 'https://fb.me/abc');
      expect(open('http://fb.me/abc'), isNull);
      expect(open('javascript:alert(1)'), isNull);
      expect(open('/relative/path'), isNull);
      expect(open('https://'), isNull);
      expect(open(''), isNull);
      expect(open(null), isNull);
    });

    test('10. absent or malformed attribution is "no attribution"', () {
      for (final malformed in <Object?>[
        null,
        'ad',
        42,
        [1, 2],
        <String, dynamic>{},
        {'first': 'x', 'latest': 3},
        {'has_multiple': true},
      ]) {
        expect(ConversationAttribution.fromJson(malformed), isNull);
      }
      // Wrongly typed fields inside a referral are ignored one by one.
      final r = ConversationAttribution.fromJson({
        'first': {
          'id': {'nested': true},
          'source': 7,
          'platform_hint': ['FACEBOOK'],
          'source_url': 12,
          'headline': false,
          'summary_truncated': 'yes',
          'observed_at': 'not a date',
        },
      })!.primary;
      expect(r.id, isNull);
      expect(r.source, ReferralSource.unknown);
      expect(r.headline, isEmpty);
      expect(r.summaryTruncated, isFalse);
      expect(r.observedAt, isNull);
    });

    test(
      'creative_thumbnail_url: only a path on this API becomes a picture',
      () {
        ConversationReferral parse(Object? value) =>
            ConversationAttribution.fromJson({
              'first': {..._referral(), 'creative_thumbnail_url': value},
            })!.primary;

        final r = parse(_creativePath);
        expect(r.creativeThumbnailPath, _creativePath);
        expect(
          r.creativeImageUrl,
          Environment.current.resolveMedia(_creativePath),
        );
        expect(r.creativeImageUrl, startsWith(Environment.current.apiBaseUrl));

        // Absent is the ordinary case and simply means no picture.
        expect(
          ConversationAttribution.fromJson({
            'first': _referral(),
          })!.primary.creativeImageUrl,
          isEmpty,
        );
        for (final value in <Object?>[
          null,
          '',
          '   ',
          42,
          {'url': _creativePath},
          // Never fetched with the session cookie: another host's URL, even
          // Meta's own, and a protocol-relative one.
          'https://scontent.xx.fbcdn.net/v/t45.1600-4/ad.jpg',
          '//evil.example/x.jpg',
          'api/referral-creatives/x/content/',
        ]) {
          final r = parse(value);
          expect(r.creativeThumbnailPath, isEmpty, reason: '$value');
          expect(r.creativeImageUrl, isEmpty, reason: '$value');
        }
      },
    );

    test('the conversation parses around a malformed attribution, and '
        'copyWith keeps a good one', () {
      final bad = Conversation.fromJson(_conversation(attribution: 'oops'));
      expect(bad.id, 42);
      expect(bad.attribution, isNull);

      final good = Conversation.fromJson(
        _conversation(attribution: {'first': _referral()}),
      );
      expect(good.attribution, isNotNull);
      expect(
        good.copyWith(status: 'RESOLVED').attribution,
        same(good.attribution),
      );
    });
  });

  group('in the conversation screen', () {
    late List<Uri> opened;
    late Future<bool> Function(Uri) realOpener;

    setUp(() {
      opened = [];
      realOpener = launchExternalUrl;
      launchExternalUrl = (uri) async {
        opened.add(uri);
        return true;
      };
    });
    tearDown(() => launchExternalUrl = realOpener);

    testWidgets('1. a full attribution renders the web card', (tester) async {
      await _open(tester, attribution: {'first': _referral()});

      expect(_card, findsOneWidget);
      expect(find.text('CAME FROM A META AD ON FACEBOOK'), findsOneWidget);
      expect(find.text('Deep hydration course — last seats'), findsOneWidget);
      expect(
        find.text('Everything your hair needs in one routine…'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card,
          matching: find.byIcon(Icons.open_in_new_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card,
          matching: find.byIcon(Icons.campaign_outlined),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an ad with a captured creative asks our API for its picture '
        'and shows it at the start of the card, beside the text', (
      tester,
    ) async {
      await _open(
        tester,
        attribution: {'first': _referral(creative: _creativePath)},
        settle: false,
      );

      expect(_card, findsOneWidget);
      expect(find.text('Deep hydration course — last seats'), findsOneWidget);
      expect(
        find.text('Everything your hair needs in one routine…'),
        findsOneWidget,
      );

      final image = tester.widget<CachedNetworkImage>(_creative);
      expect(image.imageUrl, Environment.current.resolveMedia(_creativePath));
      expect(
        find.descendant(of: _card, matching: _creative),
        findsOneWidget,
        reason: 'one picture, inside the card — not a message attachment',
      );

      // While it loads, a 56×56 tile holds its place before the text.
      final frame = find.descendant(
        of: _creativeFrame,
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(frame.first), const Size.square(56));
      expect(
        tester.getTopLeft(_creativeFrame).dx,
        lessThan(
          tester.getTopLeft(find.text('Deep hydration course — last seats')).dx,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a creative that cannot be loaded leaves the card as it would '
        'be without one: text intact, no broken image', (tester) async {
      await _open(
        tester,
        attribution: {'first': _referral(creative: _creativePath)},
        settle: false,
      );
      expect(_creativeFrame, findsOneWidget);

      // CachedNetworkImage's own fetch never settles under flutter_test (its
      // cache store is a platform plugin), so drive the failure through the
      // widget's error builder — what a 403, a 404/409 or a dead network
      // render as.
      final image = tester.widget<CachedNetworkImage>(_creative);
      final failed = image.errorWidget!(
        tester.element(_creative),
        image.imageUrl,
        Exception('HTTP 409'),
      );
      expect(failed, isA<SizedBox>());
      expect((failed as SizedBox).width, 0, reason: 'takes no space at all');
      expect(failed.height, 0);
      expect(failed.child, isNull, reason: 'no broken-image glyph');

      expect(find.text('Deep hydration course — last seats'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no creative, or one that is not ours: no picture is fetched', (
      tester,
    ) async {
      await _open(tester, attribution: {'first': _referral()});
      expect(_creative, findsNothing);
      expect(_creativeFrame, findsNothing);

      await _open(
        tester,
        attribution: {
          'first': _referral(
            creative: 'https://scontent.xx.fbcdn.net/v/t45.1600-4/ad.jpg',
          ),
        },
      );
      expect(_card, findsOneWidget);
      expect(_creative, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a creative in Arabic RTL sits at the start — the right', (
      tester,
    ) async {
      await _open(
        tester,
        attribution: {
          'first': _referral(
            headline: 'آخر قطع من كورس الترطيب العميق',
            creative: _creativePath,
          ),
        },
        locale: const Locale('ar'),
        settle: false,
      );

      expect(
        tester.getTopRight(_creativeFrame).dx,
        greaterThan(
          tester.getTopRight(find.text('آخر قطع من كورس الترطيب العميق')).dx,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. has_multiple shows the most recent referral under it', (
      tester,
    ) async {
      await _open(
        tester,
        attribution: {
          'first': _referral(id: 1, headline: 'Spring ad'),
          'latest': _referral(
            id: 2,
            source: 'META_ORGANIC_POST',
            headline: 'Autumn post',
          ),
          'has_multiple': true,
        },
      );

      expect(find.text('Spring ad'), findsOneWidget);
      final line = tester.widget<Text>(
        find.byKey(const ValueKey('conversationSourceMostRecent')),
      );
      final plain = line.textSpan!.toPlainText();
      expect(plain, startsWith('Most recent: Autumn post · Seen '));
    });

    testWidgets('6 + 7. partial data: only what exists is shown', (
      tester,
    ) async {
      await _open(
        tester,
        attribution: {
          'latest': {'source': 'SOMETHING_NEW', 'platform_hint': 'THREADS'},
        },
      );

      expect(_card, findsOneWidget);
      expect(find.text('SOURCE NOT REPORTED'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('conversationSourceHeadline')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('conversationSourceSummary')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _card,
          matching: find.byIcon(Icons.open_in_new_rounded),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. a valid source URL makes the card open it', (tester) async {
      await _open(tester, attribution: {'first': _referral()});

      await tester.tap(_card);
      await tester.pump();

      expect(opened, [
        Uri.parse('https://www.facebook.com/ads/library/?id=123'),
      ]);
    });

    testWidgets('9. an invalid or missing URL leaves the card inert', (
      tester,
    ) async {
      await _open(
        tester,
        attribution: {'first': _referral(url: 'javascript:alert(1)')},
      );

      expect(
        find.descendant(of: _card, matching: find.byType(InkWell)),
        findsNothing,
      );
      await tester.tap(_card);
      await tester.pump();
      expect(opened, isEmpty);
    });

    testWidgets('10. no attribution: no card, no pill, thread unchanged', (
      tester,
    ) async {
      await _open(tester);

      expect(_card, findsNothing);
      expect(_pill, findsNothing);
      expect(find.text('Message number 1'), findsOneWidget);
      expect(find.text('Message number 3'), findsOneWidget);
    });

    testWidgets('Arabic RTL, dark mode', (tester) async {
      await _open(
        tester,
        attribution: {
          'first': _referral(headline: 'آخر قطع من كورس الترطيب العميق'),
        },
        locale: const Locale('ar'),
        theme: AppTheme.dark,
      );

      expect(find.text('جاء من إعلان على META على FACEBOOK'), findsOneWidget);
      expect(find.text('آخر قطع من كورس الترطيب العميق'), findsOneWidget);
      expect(Directionality.of(tester.element(_card)), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long headline and summary stay inside the card on a narrow '
        'phone', (tester) async {
      await _open(
        tester,
        size: const Size(320, 900),
        attribution: {
          'first': _referral(
            headline: 'Headline ' * 40,
            summary: 'A very long advertisement body. ' * 60,
          ),
        },
      );

      expect(tester.takeException(), isNull);
      final headline = tester.widget<Text>(
        find.byKey(const ValueKey('conversationSourceHeadline')),
      );
      expect(headline.maxLines, 3);
      expect(tester.getSize(_card).width, lessThanOrEqualTo(320));
    });

    testWidgets('11. rebuilds and refreshes never duplicate the card', (
      tester,
    ) async {
      final server = await _open(tester, attribution: {'first': _referral()});
      final container = ProviderScope.containerOf(tester.element(_card));
      final controller = container.read(
        conversationControllerProvider(42).notifier,
      );

      // Not awaited directly: the fake HTTP only progresses while the test
      // pumps frames.
      for (var i = 0; i < 3; i++) {
        final refresh = controller.refreshFromServer();
        await tester.pumpAndSettle();
        await refresh;
      }
      await tester.pumpWidget(tester.widget(find.byType(ProviderScope)));
      await tester.pumpAndSettle();

      expect(_card, findsOneWidget);
      expect(server.detailFetches, greaterThanOrEqualTo(1));
    });

    testWidgets('12. with older pages unloaded the card waits for the '
        'history start, then appears once, above the oldest message', (
      tester,
    ) async {
      final server = await _open(
        tester,
        attribution: {'first': _referral()},
        // Short pages that fit on screen: every list item is built, so a
        // card placed while older history is still unloaded would be found.
        pages: {
          1: [4, 5, 6],
          2: [1, 2, 3],
        },
      );

      expect(find.text('Message number 4'), findsOneWidget);
      expect(_card, findsNothing, reason: 'page 2 (older) not loaded yet');
      expect(_pill, findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(_pill));
      final older = container
          .read(conversationControllerProvider(42).notifier)
          .loadOlder();
      await tester.pumpAndSettle();
      await older;
      expect(server.pagesFetched, contains(2));

      // Scroll to the very top: the card is the first thing in the thread.
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, 20000));
      await tester.pumpAndSettle();

      expect(_card, findsOneWidget);
      final cardTop = tester.getTopLeft(_card).dy;
      final firstMessageTop = tester
          .getTopLeft(find.text('Message number 1'))
          .dy;
      expect(cardTop, lessThan(firstMessageTop));
    });

    testWidgets('13. "Jump to source" loads the history and lands on the '
        'rendered card', (tester) async {
      final server = await _open(
        tester,
        size: const Size(800, 900),
        attribution: {'first': _referral()},
        pages: {
          1: [for (var i = 41; i <= 80; i++) i],
          2: [for (var i = 1; i <= 40; i++) i],
        },
      );
      expect(_pill, findsOneWidget);
      expect(_card, findsNothing);

      await tester.tap(_pill);
      await tester.pumpAndSettle();

      expect(server.pagesFetched, contains(2));
      expect(_card, findsOneWidget);
      // Aligned to the top of the thread viewport, where the card really is.
      final listTop = tester.getTopLeft(find.byType(ListView).first).dy;
      final cardTop = tester.getTopLeft(_card).dy;
      expect(cardTop - listTop, inInclusiveRange(0, 48));
      expect(_pill, findsNothing, reason: 'card now on screen');
    });
  });
}
