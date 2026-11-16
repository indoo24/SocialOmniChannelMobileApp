/// Notification text (notification_content.dart): English and Arabic,
/// right-to-left marking, the previews-off privacy mode, channel labels and
/// tap payloads.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/notifications/notification_content.dart';
import 'package:scenario_mobile/core/notifications/notification_grouping.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

final at = DateTime.utc(2026, 11, 15, 9, 30);

ConversationEntry entry(
  int id, {
  String name = 'Sara Ahmed',
  List<String> previews = const ['Is it in stock?'],
  int? count,
  String provider = 'WHATSAPP',
  String channel = '',
}) => ConversationEntry(
  conversationId: id,
  customerName: name,
  provider: provider,
  channelName: channel,
  messageCount: count ?? previews.length,
  previews: [for (final p in previews) MessagePreview(text: p, at: at)],
  lastMessageAt: at,
  postedAt: at,
);

NotificationContentBuilder builder(String lang, {bool previews = true}) =>
    NotificationContentBuilder(
      l10n: lookupAppLocalizations(Locale(lang)),
      showPreviews: previews,
    );

ShowSummary summary({int messages = 15, int conversations = 10}) {
  final recent = [
    entry(1, name: 'Sara Ahmed', previews: ['Is it in stock?']),
    entry(2, name: 'محمد علي', previews: ['هل يوجد توصيل؟']),
  ];
  return ShowSummary(
    messageCount: messages,
    conversationCount: conversations,
    latest: recent.first,
    recent: recent,
  );
}

void main() {
  group('Conversation notification — previews on', () {
    test('customer name is the title, newest message the body', () {
      final c = builder(
        'en',
      ).conversation(entry(42, previews: ['Hi', 'Is it in stock?']));
      expect(c.title, 'Sara Ahmed');
      expect(c.body, 'Is it in stock?');
      expect(c.senderName, 'Sara Ahmed');
      expect(c.messages.map((m) => m.text), ['Hi', 'Is it in stock?']);
      expect(c.initials, 'SA');
      expect(c.channelLabel, 'WhatsApp');
      expect(c.when, at);
      expect(c.messageCount, 2);
      expect(c.showsPreview, isTrue);
      expect(c.notificationId, 42);
      expect(c.tapTarget, const OpenConversation(42));
    });

    test('Arabic: Arabic channel label and fallbacks', () {
      final c = builder(
        'ar',
      ).conversation(entry(7, name: '', previews: [''], provider: 'INSTAGRAM'));
      expect(c.title, 'عميل');
      expect(c.body, 'رسالة جديدة');
      expect(c.channelLabel, 'إنستغرام');
    });

    test('header shows the channel, plus the count once there are several', () {
      expect(builder('en').conversation(entry(1)).headerText, 'WhatsApp');
      expect(
        builder(
          'en',
        ).conversation(entry(1, previews: ['a', 'b', 'c'])).headerText,
        'WhatsApp · 3 new messages',
      );
      expect(
        builder('ar').conversation(entry(1, previews: ['a', 'b'])).headerText,
        'واتساب · رسالتان جديدتان',
      );
      // Unknown channel: just the count.
      expect(
        builder(
          'en',
        ).conversation(entry(1, previews: ['a', 'b'], provider: '')).headerText,
        '2 new messages',
      );
    });

    test('channel account name is shown next to the platform', () {
      final c = builder('en').conversation(entry(1, channel: 'Main store'));
      expect(c.channelLabel, 'WhatsApp · ${Bidi.isolate('Main store')}');
    });

    test('unknown provider falls back to the account name, or nothing', () {
      final b = builder('en');
      expect(b.channelLabel('SMS', 'Shop line'), 'Shop line');
      expect(b.channelLabel('', ''), '');
      expect(b.channelLabel('FACEBOOK', ''), 'Messenger');
    });
  });

  group('Conversation notification — previews off (privacy)', () {
    for (final lang in ['en', 'ar']) {
      test('$lang: no name, no message text anywhere', () {
        final c = builder(lang, previews: false).conversation(
          entry(42, name: 'Sara Ahmed', previews: ['secret 1', 'secret 2']),
        );
        final everything = [
          c.title,
          c.body,
          c.senderName,
          c.initials,
          ...c.messages.map((m) => m.text),
        ].join(' ');
        expect(everything, isNot(contains('Sara')));
        expect(everything, isNot(contains('secret')));
        expect(c.showsPreview, isFalse);
        expect(c.messages, isEmpty);
        // The tap still opens the right conversation.
        expect(c.tapTarget, const OpenConversation(42));
      });
    }

    test('generic wording, with the count', () {
      final en = builder(
        'en',
        previews: false,
      ).conversation(entry(1, previews: ['a', 'b', 'c']));
      expect(en.title, 'New message');
      expect(en.body, '3 new messages');

      final ar = builder(
        'ar',
        previews: false,
      ).conversation(entry(1, previews: ['a', 'b', 'c']));
      expect(ar.title, 'رسالة جديدة');
      expect(ar.body, '3 رسائل جديدة');
    });
  });

  group('Summary notification', () {
    test('English: counts, latest sender and one line per conversation', () {
      final s = builder('en').summary(summary());
      expect(s.title, '15 new messages');
      expect(s.summaryText, 'From 10 conversations');
      expect(s.body, contains('From 10 conversations'));
      expect(s.body, contains('Latest: ${Bidi.isolate('Sara Ahmed')}'));
      expect(s.lines, hasLength(2));
      expect(
        s.lines.first,
        '${Bidi.lrm}${Bidi.isolate('Sara Ahmed')}: '
        '${Bidi.isolate('Is it in stock?')}',
      );
      expect(s.tapTarget, const OpenUnreadInbox());
    });

    test('Arabic: Arabic plurals and right-to-left lines', () {
      final s = builder('ar').summary(summary());
      expect(s.title, '15 رسالة جديدة');
      expect(s.summaryText, 'من 10 محادثات');
      expect(s.body, startsWith(Bidi.rlm));
      expect(s.body, contains('الأحدث: '));
      // Every line is marked RTL, and each name/preview is isolated so an
      // English name cannot reorder around the colon.
      for (final line in s.lines) {
        expect(line, startsWith(Bidi.rlm));
      }
      expect(
        s.lines[1],
        '${Bidi.rlm}${Bidi.isolate('محمد علي')}: '
        '${Bidi.isolate('هل يوجد توصيل؟')}',
      );
    });

    test('Arabic dual and singular forms', () {
      final b = builder('ar');
      expect(
        b.summary(summary(messages: 2, conversations: 2)).title,
        'رسالتان جديدتان',
      );
      expect(
        b.summary(summary(messages: 2, conversations: 2)).summaryText,
        'من محادثتين',
      );
      expect(
        b.summary(summary(messages: 1, conversations: 1)).title,
        'رسالة جديدة واحدة',
      );
    });

    test('English singular forms', () {
      final s = builder('en').summary(summary(messages: 1, conversations: 1));
      expect(s.title, '1 new message');
      expect(s.summaryText, 'From 1 conversation');
    });

    test('previews off: counts only, no names or text', () {
      for (final lang in ['en', 'ar']) {
        final s = builder(lang, previews: false).summary(summary());
        final everything = [s.title, s.body, s.summaryText, ...s.lines].join();
        expect(s.lines, isEmpty);
        expect(everything, isNot(contains('Sara')));
        expect(everything, isNot(contains('stock')));
        expect(everything, isNot(contains('محمد')));
      }
      expect(
        builder('en', previews: false).summary(summary()).body,
        'From 10 conversations',
      );
    });
  });

  group('Initials', () {
    test('one or two letters, grapheme-safe', () {
      expect(NotificationContentBuilder.initialsOf('sara ahmed'), 'SA');
      expect(NotificationContentBuilder.initialsOf('Sara'), 'S');
      expect(NotificationContentBuilder.initialsOf('محمد علي'), 'مع');
      expect(NotificationContentBuilder.initialsOf('👩‍💻 Dev'), '👩‍💻D');
      expect(NotificationContentBuilder.initialsOf('   '), '');
    });
  });

  group('Tap payloads', () {
    test('round trip', () {
      for (final target in const [OpenConversation(306), OpenUnreadInbox()]) {
        expect(NotificationTapTarget.decode(target.encode()), target);
      }
    });

    test('foreign or malformed payloads are ignored', () {
      for (final payload in [
        null,
        '',
        'not json',
        '[]',
        '{"open":"conversation","id":"306"}',
        '{"open":"conversation","id":-1}',
        '{"open":"settings"}',
      ]) {
        expect(NotificationTapTarget.decode(payload), isNull, reason: payload);
      }
    });

    test('payloads carry ids only, never message text', () {
      final c = builder('en').conversation(entry(5, previews: ['private']));
      expect(c.tapTarget.encode(), isNot(contains('private')));
      expect(c.tapTarget.encode(), isNot(contains('Sara')));
    });
  });
}
