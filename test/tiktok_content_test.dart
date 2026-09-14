/// TikTok content the app cannot show as text or a file, and failure copy.
///
/// A shared post is a notice with an "Open on TikTok" action, a question card
/// shows its question, anything else says it cannot be shown — never an empty
/// bubble. A failed send shows a translated reason keyed on the server's
/// stable code, falling back to the server's own text for an unknown code.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Widget _harness(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: child),
    );

Message _message(Map<String, dynamic> extra) => Message.fromJson({
  'id': 1,
  'direction': 'INBOUND',
  'sender_type': 'CUSTOMER',
  'message_type': 'TEXT',
  'text': '',
  'sent_at': '2026-09-01T10:00:00Z',
  ...extra,
});

void main() {
  group('content notice parsing', () {
    test('reads the server notice', () {
      final message = _message({
        'content_notice': {
          'kind': 'share_post',
          'provider_type': '',
          'url': 'https://www.tiktok.com/embed/v2/1',
          'title': '',
          'video_id': '1',
        },
      });
      expect(message.contentNotice?.kind, 'share_post');
      expect(message.contentNotice?.url, 'https://www.tiktok.com/embed/v2/1');
    });

    test('an ordinary message has no notice', () {
      expect(_message({'content_notice': null}).contentNotice, isNull);
      expect(_message({}).contentNotice, isNull);
    });
  });

  group('content notice rendering', () {
    testWidgets('a shared post offers to open it on TikTok', (tester) async {
      await tester.pumpWidget(
        _harness(
          const ContentNoticeView(
            notice: ContentNotice(
              kind: 'share_post',
              url: 'https://www.tiktok.com/embed/v2/1',
            ),
            color: Colors.black,
          ),
        ),
      );
      expect(find.text('Shared a TikTok post'), findsOneWidget);
      expect(find.text('Open on TikTok'), findsOneWidget);
    });

    testWidgets('no open action without a safe link', (tester) async {
      await tester.pumpWidget(
        _harness(
          const ContentNoticeView(
            notice: ContentNotice(kind: 'share_post', url: 'javascript:x'),
            color: Colors.black,
          ),
        ),
      );
      expect(find.text('Shared a TikTok post'), findsOneWidget);
      expect(find.text('Open on TikTok'), findsNothing);
    });

    testWidgets('a question card shows its question', (tester) async {
      await tester.pumpWidget(
        _harness(
          const ContentNoticeView(
            notice: ContentNotice(kind: 'template', title: 'Which size?'),
            color: Colors.black,
          ),
        ),
      );
      expect(find.text('Question card: Which size?'), findsOneWidget);
    });

    testWidgets('unsupported content says so, in Arabic', (tester) async {
      await tester.pumpWidget(
        _harness(
          const ContentNoticeView(
            notice: ContentNotice(kind: 'unsupported', providerType: 'OTHER'),
            color: Colors.black,
          ),
          locale: const Locale('ar'),
        ),
      );
      expect(
        find.text(
          'لا يمكن عرض رسالة TikTok هذه هنا. افتح المحادثة في TikTok لرؤيتها.',
        ),
        findsOneWidget,
      );
    });
  });

  group('delivery error copy', () {
    testWidgets('translates a known code and falls back otherwise', (
      tester,
    ) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
          locale: const Locale('ar'),
        ),
      );

      final limited = _message({
        'delivery_status': 'FAILED',
        'delivery_error': 'TikTok reply limit reached.',
        'delivery_error_code': 'tiktok_messaging_limit',
      });
      expect(
        deliveryErrorText(l10n, limited),
        l10n.deliveryErrorTiktokMessagingLimit,
      );

      final unknown = _message({
        'delivery_status': 'FAILED',
        'delivery_error': 'Something new',
        'delivery_error_code': 'brand_new_code',
      });
      expect(deliveryErrorText(l10n, unknown), 'Something new');

      final blank = _message({'delivery_status': 'FAILED'});
      expect(deliveryErrorText(l10n, blank), l10n.notDeliveredFallback);
    });
  });
}
