/// Web links in message text: which strings become links
/// ([splitTextLinks], [SafeUrl.forLink]), how they open
/// ([openExternalLink]), and how the real [MessageBubble] renders them —
/// incoming, outgoing, templates, Arabic, dark mode, and the long-press Copy
/// that must still copy the original text.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/external_link.dart';
import 'package:scenario_mobile/core/utils/safe_url.dart';
import 'package:scenario_mobile/core/utils/text_links.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The links [text] yields, as written in the text.
List<String> _links(String text) =>
    splitTextLinks(text).where((p) => p.isLink).map((p) => p.text).toList();

/// Splitting never loses or adds a character.
void _expectLossless(String text) =>
    expect(splitTextLinks(text).map((p) => p.text).join(), text);

Message _message(
  String text, {
  String direction = 'INBOUND',
  List<Map<String, Object?>> attachments = const [],
}) => Message.fromJson({
  'id': 1,
  'text': text,
  'direction': direction,
  'sender_name': direction == 'INBOUND' ? 'Sarah' : 'Sam Agent',
  'sent_at': '2026-09-28T10:00:00Z',
  'delivery_status': 'DELIVERED',
  'attachments': attachments,
});

Widget _bubble(
  Message message, {
  ThemeData? theme,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: MessageBubble(message: message, onReply: () {}),
      ),
    ),
  ),
);

/// Every tappable span the bubble renders.
List<TextSpan> _linkSpans(WidgetTester tester) {
  final spans = <TextSpan>[];
  for (final paragraph in tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(MessageBubble),
      matching: find.byType(RichText),
    ),
  )) {
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) spans.add(span);
      return true;
    });
  }
  return spans;
}

/// Where [substring] is drawn on screen.
Offset _centerOfText(WidgetTester tester, String substring) {
  final range = find.textRange.ofSubstring(substring).evaluate().single;
  final box = range.renderObject
      .getBoxesForSelection(
        TextSelection(
          baseOffset: range.textRange.start,
          extentOffset: range.textRange.end,
        ),
      )
      .first;
  return range.renderObject.localToGlobal(box.toRect().center);
}

/// Replaces the platform launcher for one test and records what it gets.
List<Uri> _captureLaunches({bool Function()? result, Object? throws}) {
  final launched = <Uri>[];
  final real = launchExternalUrl;
  launchExternalUrl = (uri) async {
    launched.add(uri);
    if (throws != null) throw throws;
    return result?.call() ?? true;
  };
  addTearDown(() => launchExternalUrl = real);
  return launched;
}

List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  group('detection', () {
    test('1. one https URL', () {
      const text = 'Check our website:\nhttps://example.com/product/123';
      expect(_links(text), ['https://example.com/product/123']);
      expect(splitTextLinks(text), [
        const TextLinkPart('Check our website:\n'),
        TextLinkPart(
          'https://example.com/product/123',
          Uri.parse('https://example.com/product/123'),
        ),
      ]);
    });

    test('2. an http URL', () {
      expect(_links('see http://example.com'), ['http://example.com']);
    });

    test('3 + 22. several URLs, each separate, text between them kept', () {
      const text =
          'Website:\nhttps://example.com\n\nFacebook:\n'
          'https://facebook.com/example\n\nInstagram:\n'
          'https://instagram.com/example';
      expect(_links(text), [
        'https://example.com',
        'https://facebook.com/example',
        'https://instagram.com/example',
      ]);
      final plain = splitTextLinks(
        text,
      ).where((p) => !p.isLink).map((p) => p.text).toList();
      expect(plain, ['Website:\n', '\n\nFacebook:\n', '\n\nInstagram:\n']);
      _expectLossless(text);
    });

    test('4 + 5 + 6. in the middle, at the start, at the end', () {
      expect(_links('Visit https://example.com for more information.'), [
        'https://example.com',
      ]);
      expect(_links('https://example.com is ours'), ['https://example.com']);
      expect(_links('ours is https://example.com'), ['https://example.com']);
    });

    test('7. punctuation after a URL is not part of it', () {
      for (final (text, link) in [
        ('Visit https://example.com.', 'https://example.com'),
        ('https://example.com/test, then', 'https://example.com/test'),
        ('Really? https://example.com!', 'https://example.com'),
        ('Seen https://example.com/a?', 'https://example.com/a'),
        ('"https://example.com"', 'https://example.com'),
        ('https://example.com/x...', 'https://example.com/x'),
        ('https://example.com; next', 'https://example.com'),
      ]) {
        expect(_links(text), [link], reason: text);
        expect(
          splitTextLinks(text).firstWhere((p) => p.isLink).uri,
          Uri.parse(link),
          reason: text,
        );
        _expectLossless(text);
      }
    });

    test('8. brackets around a URL stay outside it; balanced ones inside '
        'stay in', () {
      expect(_links('(https://example.com)'), ['https://example.com']);
      expect(_links('[https://example.com]'), ['https://example.com']);
      expect(_links('{https://example.com}'), ['https://example.com']);
      expect(_links('(see https://example.com/a).'), ['https://example.com/a']);
      expect(_links('https://en.wikipedia.org/wiki/Mercury_(planet)'), [
        'https://en.wikipedia.org/wiki/Mercury_(planet)',
      ]);
      _expectLossless('(https://example.com)');
    });

    test('query strings, fragments and escapes are kept whole', () {
      const url =
          'https://www.example.com/path/to?id=123&utm_source=x&utm_medium=y'
          '#section-2%20b';
      expect(_links('Go: $url.'), [url]);
      expect(_links('https://example.com:8443/a/b/'), [
        'https://example.com:8443/a/b/',
      ]);
    });

    test('9 + 11. Arabic text, Arabic punctuation, a URL glued to Arabic', () {
      expect(_links('لمزيد من التفاصيل:\nhttps://example.com/product/123'), [
        'https://example.com/product/123',
      ]);
      expect(_links('اضغط هنا https://example.com للتفاصيل'), [
        'https://example.com',
      ]);
      expect(_links('الرابط https://example.com، شكرًا'), [
        'https://example.com',
      ]);
      expect(_links('هل رأيت https://example.com؟'), ['https://example.com']);
      // No space before the next Arabic word: the host stops at it.
      expect(_links('اضغط https://example.comللتفاصيل'), [
        'https://example.com',
      ]);
      // Arabic in the path is part of the link.
      expect(_links('https://ar.wikipedia.org/wiki/مصر'), [
        'https://ar.wikipedia.org/wiki/مصر',
      ]);
      expect(_links('Offer عرض https://example.com/offer now'), [
        'https://example.com/offer',
      ]);
      _expectLossless('اضغط https://example.comللتفاصيل');
    });

    test('10. English text with a URL', () {
      expect(_links('Our new offer: https://example.com/offer — enjoy'), [
        'https://example.com/offer',
      ]);
    });

    test('13. no URL: one plain part, same text', () {
      expect(splitTextLinks('Hello, how are you?'), [
        const TextLinkPart('Hello, how are you?'),
      ]);
      expect(splitTextLinks(''), isEmpty);
    });

    test('14. not links: no host, other schemes, bare domains, glued '
        'schemes', () {
      for (final text in [
        'https://',
        'http:// example.com',
        'ftp://example.com/file',
        'www.example.com',
        'example.com/path',
        'mail me at a@example.com',
        'xhttps://example.com',
      ]) {
        expect(_links(text), isEmpty, reason: text);
        expect(splitTextLinks(text), [TextLinkPart(text)], reason: text);
      }
    });

    test('15 + 16. javascript:, data:, file:, content:, intent: are never '
        'links', () {
      for (final text in [
        'javascript:alert(1)',
        'click javascript:fetch("https://evil.example")',
        'data:text/html;base64,PHNjcmlwdD4=',
        'file:///etc/passwd',
        'content://media/external/images/1',
        'intent://scan/#Intent;scheme=zxing;end',
      ]) {
        final parts = splitTextLinks(text);
        expect(
          parts.where((p) => p.isLink && p.uri!.scheme != 'https'),
          isEmpty,
          reason: text,
        );
      }
      // The https URL quoted *inside* a javascript: string is its own link,
      // not the javascript: call around it.
      expect(_links('click javascript:fetch("https://evil.example")'), [
        'https://evil.example',
      ]);
    });

    test('a URL with credentials in it is not a link', () {
      expect(_links('https://bank.example@evil.example/login'), isEmpty);
    });

    test('an upper-case scheme is still a link', () {
      expect(_links('HTTPS://EXAMPLE.COM/A'), ['HTTPS://EXAMPLE.COM/A']);
    });
  });

  group('SafeUrl.forLink', () {
    test('http and https with a host only', () {
      expect(SafeUrl.forLink('https://example.com'), isNotNull);
      expect(SafeUrl.forLink('http://example.com/a?b=1'), isNotNull);
      for (final url in [
        null,
        '',
        'https://',
        'javascript:alert(1)',
        'data:text/plain,hi',
        'file:///x',
        'intent://x',
        'mailto:a@example.com',
        'https://user:pass@example.com',
        '/relative/path',
      ]) {
        expect(SafeUrl.forLink(url), isNull, reason: '$url');
      }
    });
  });

  group('opening', () {
    test('17. a safe link goes to the platform launcher', () async {
      final launched = _captureLaunches();
      expect(
        await openExternalLink(Uri.parse('https://example.com/a')),
        isTrue,
      );
      expect(launched, [Uri.parse('https://example.com/a')]);
    });

    test('an unsafe link never reaches the launcher', () async {
      final launched = _captureLaunches();
      expect(await openExternalLink(Uri.parse('javascript:alert(1)')), isFalse);
      expect(await openExternalLink(Uri.parse('data:text/plain,x')), isFalse);
      expect(launched, isEmpty);
    });

    test(
      'no app to open it, or a platform error: false, never a throw',
      () async {
        _captureLaunches(result: () => false);
        expect(
          await openExternalLink(Uri.parse('https://example.com')),
          isFalse,
        );
        _captureLaunches(throws: PlatformException(code: 'ACTIVITY_NOT_FOUND'));
        expect(
          await openExternalLink(Uri.parse('https://example.com')),
          isFalse,
        );
      },
    );
  });

  group('in a message bubble', () {
    testWidgets('19 + 17. incoming: the URL is a primary-coloured, '
        'underlined link that opens through the shared launcher', (
      tester,
    ) async {
      final launched = _captureLaunches();
      await tester.pumpWidget(
        _bubble(_message('Visit https://example.com/product/123 for more.')),
      );

      final spans = _linkSpans(tester);
      expect(spans, hasLength(1));
      expect(spans.single.text, 'https://example.com/product/123');
      expect(spans.single.style?.color, AppTheme.light.colorScheme.primary);
      expect(spans.single.style?.decoration, TextDecoration.underline);

      await tester.tapOnText(
        find.textRange.ofSubstring('https://example.com/product/123'),
      );
      await tester.pump();
      expect(launched, [Uri.parse('https://example.com/product/123')]);
    });

    testWidgets('tapping the text around a link opens nothing', (tester) async {
      final launched = _captureLaunches();
      await tester.pumpWidget(
        _bubble(_message('Visit https://example.com for more information')),
      );
      await tester.tapOnText(find.textRange.ofSubstring('more information'));
      await tester.pump();
      expect(launched, isEmpty);
    });

    testWidgets('20. outgoing: the link keeps the bubble\'s white, '
        'underlined', (tester) async {
      final launched = _captureLaunches();
      await tester.pumpWidget(
        _bubble(
          _message('Check this:\nhttps://example.com', direction: 'OUTBOUND'),
        ),
      );
      final span = _linkSpans(tester).single;
      expect(span.style?.color, Colors.white);
      expect(span.style?.decoration, TextDecoration.underline);

      await tester.tapOnText(find.textRange.ofSubstring('https://example.com'));
      await tester.pump();
      expect(launched, [Uri.parse('https://example.com')]);
    });

    testWidgets('21. dark mode: the link uses the dark primary', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bubble(_message('See https://example.com'), theme: AppTheme.dark),
      );
      expect(
        _linkSpans(tester).single.style?.color,
        AppTheme.dark.colorScheme.primary,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('3 + 22. every URL in a message is its own link', (
      tester,
    ) async {
      final launched = _captureLaunches();
      await tester.pumpWidget(
        _bubble(
          _message(
            'Website: https://example.com\n'
            'Facebook: https://facebook.com/example\n'
            'Instagram: https://instagram.com/example',
          ),
        ),
      );
      expect(_linkSpans(tester).map((s) => s.text), [
        'https://example.com',
        'https://facebook.com/example',
        'https://instagram.com/example',
      ]);

      await tester.tapOnText(
        find.textRange.ofSubstring('https://facebook.com/example'),
      );
      await tester.tapOnText(
        find.textRange.ofSubstring('https://instagram.com/example'),
      );
      await tester.pump();
      expect(launched, [
        Uri.parse('https://facebook.com/example'),
        Uri.parse('https://instagram.com/example'),
      ]);
    });

    testWidgets('9 + 11. Arabic, RTL: the link is isolated left-to-right, '
        'opens the exact URL, and the text reads right-to-left', (
      tester,
    ) async {
      final launched = _captureLaunches();
      await tester.pumpWidget(
        _bubble(
          _message('اضغط هنا https://example.com/product/123 للتفاصيل'),
          locale: const Locale('ar'),
        ),
      );
      final span = _linkSpans(tester).single;
      expect(span.text, '\u2066https://example.com/product/123\u2069');
      expect(span.semanticsLabel, 'https://example.com/product/123');
      expect(
        Directionality.of(tester.element(find.byType(MessageBubble))),
        TextDirection.rtl,
      );

      await tester.tapOnText(
        find.textRange.ofSubstring('https://example.com/product/123'),
      );
      await tester.pump();
      expect(launched, [Uri.parse('https://example.com/product/123')]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. a sent template (an outbound message carrying the '
        'template body) gets the same links', (tester) async {
      final launched = _captureLaunches();
      await tester.pumpWidget(
        _bubble(
          _message(
            'عرضنا الجديد:\nhttps://example.com/offer\nOur new offer!',
            direction: 'OUTBOUND',
          ),
        ),
      );
      await tester.tapOnText(
        find.textRange.ofSubstring('https://example.com/offer'),
      );
      await tester.pump();
      expect(launched, [Uri.parse('https://example.com/offer')]);
    });

    testWidgets('13. no URL: plain text exactly as before', (tester) async {
      await tester.pumpWidget(_bubble(_message('Hello, how are you?')));
      expect(_linkSpans(tester), isEmpty);
      expect(find.text('Hello, how are you?'), findsOneWidget);
    });

    testWidgets('15 + 16. javascript: and data: text is not tappable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bubble(_message('javascript:alert(1) and data:text/html,<b>x</b>')),
      );
      expect(_linkSpans(tester), isEmpty);
      // Shown as the literal text — never interpreted as markup.
      expect(
        find.text('javascript:alert(1) and data:text/html,<b>x</b>'),
        findsOneWidget,
      );
    });

    testWidgets('18. long-press Copy copies the original text, URL included '
        '— and long-pressing the link itself opens the menu, not the link', (
      tester,
    ) async {
      final launched = _captureLaunches();
      final copied = _captureClipboard(tester);
      const text = 'اضغط هنا https://example.com/offer?id=5 للتفاصيل.';
      await tester.pumpWidget(_bubble(_message(text)));

      await tester.longPressAt(_centerOfText(tester, 'اضغط هنا'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.pumpAndSettle();
      // Exactly the message text: no direction marks, no markup.
      expect(copied, [text]);

      // Now hold down on the link itself.
      await tester.longPressAt(
        _centerOfText(tester, 'https://example.com/offer?id=5'),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a message with a file and text: only the text has links', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bubble(
          _message(
            'Invoice attached, details at https://example.com/i/9',
            attachments: const [
              {
                'id': 'att-1',
                'type': 'FILE',
                'url': 'https://cdn.example.com/invoice.pdf',
                'file_name': 'invoice.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 1024,
              },
            ],
          ),
        ),
      );
      expect(_linkSpans(tester).map((s) => s.text), [
        'https://example.com/i/9',
      ]);
    });

    testWidgets('the parsed links follow the text when the message changes', (
      tester,
    ) async {
      await tester.pumpWidget(_bubble(_message('old https://old.example')));
      expect(_linkSpans(tester).single.text, 'https://old.example');
      await tester.pumpWidget(_bubble(_message('now https://new.example/x')));
      expect(_linkSpans(tester).single.text, 'https://new.example/x');
      final recognizer =
          _linkSpans(tester).single.recognizer! as TapGestureRecognizer;
      expect(recognizer.onTap, isNotNull);
    });
  });
}
