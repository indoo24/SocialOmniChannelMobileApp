/// The inbox and conversation presentation: rows, filter pills, empty states
/// and message bubbles render in light and dark themes, in Arabic, on a
/// narrow phone with large text, without overflowing — and keep the states
/// they show readable without relying on colour.
library;

import 'dart:ui' show Tristate;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/theme/tokens.dart';
import 'package:scenario_mobile/core/widgets/avatar.dart';
import 'package:scenario_mobile/core/widgets/badges.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';
import 'package:scenario_mobile/features/conversations/inbox_quick_filter_bar.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

const _longName =
    'Mohamed Abdelrahman Elsayed Abdelaziz Mostafa Elnewehy Customer Account';
const _longUrl =
    'https://www.instagram.com/reel/DdEPLEbo1234567890abcdefghijklmnop/?igsh=MWQ1ZGUxMzBkMA==';

Map<String, Object?> _conversationJson({
  int id = 1,
  String name = 'Sarah Connor',
  String preview = 'Hello there',
  String provider = 'WHATSAPP',
  int unread = 0,
  Map<String, Object?>? assignedTo,
  bool withMetadata = false,
}) => {
  'id': id,
  'customer': {
    'id': 100 + id,
    'display_name': name,
    if (withMetadata) 'lifecycle_stage': 'NEW_LEAD',
  },
  'provider': provider,
  'status': 'OPEN',
  'priority': withMetadata ? 'URGENT' : 'NORMAL',
  'unread_count': unread,
  'message_count': 3,
  'last_message_preview': preview,
  'last_message_at': '2026-09-28T10:00:00Z',
  'assigned_to': assignedTo,
  if (withMetadata)
    'category': {'id': 3, 'label': 'Wholesale enquiries', 'slug': 'wholesale'},
};

Widget _app(
  Widget child, {
  ThemeData? theme,
  Locale locale = const Locale('en'),
  double width = 320,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  ),
);

/// Every combination the brief asks to be checked: both themes, both
/// languages, at the narrowest common phone width and the largest text size
/// the app allows.
final _variants = [
  for (final dark in [false, true])
    for (final arabic in [false, true])
      (
        label: '${dark ? 'dark' : 'light'} · ${arabic ? 'Arabic' : 'English'}',
        theme: dark ? AppTheme.dark : AppTheme.light,
        locale: Locale(arabic ? 'ar' : 'en'),
      ),
];

void main() {
  group('Inbox row', () {
    for (final v in _variants) {
      testWidgets('long name, URL preview and every badge fit — ${v.label}', (
        tester,
      ) async {
        final conversation = Conversation.fromJson(
          _conversationJson(
            name: _longName,
            preview: _longUrl,
            unread: 128,
            withMetadata: true,
            assignedTo: {'id': 7, 'full_name': 'Basma Abd Allatif Elsayed'},
          ),
        );
        await tester.pumpWidget(
          _app(
            ConversationRow(
              conversation: conversation,
              currentEmployeeId: 42,
              onTap: () {},
            ),
            theme: v.theme,
            locale: v.locale,
            textScale: 1.4,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('99+'), findsOneWidget);
        expect(find.textContaining('Basma'), findsOneWidget);
      });
    }

    testWidgets('someone else holding it is plain text, not a filled badge', (
      tester,
    ) async {
      final conversation = Conversation.fromJson(
        _conversationJson(assignedTo: {'id': 7, 'full_name': 'Tarek Lead'}),
      );
      await tester.pumpWidget(
        _app(
          ConversationRow(
            conversation: conversation,
            currentEmployeeId: 42,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Tarek Lead'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Tarek Lead'),
          matching: find.byType(StatusBadge),
        ),
        findsNothing,
      );
    });

    testWidgets('the agent\'s own conversation is marked "You"', (
      tester,
    ) async {
      final conversation = Conversation.fromJson(
        _conversationJson(assignedTo: {'id': 42, 'full_name': 'Me Agent'}),
      );
      await tester.pumpWidget(
        _app(
          ConversationRow(
            conversation: conversation,
            currentEmployeeId: 42,
            onTap: () {},
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('You'),
        ),
        findsOneWidget,
      );
      expect(find.text('Me Agent'), findsNothing);
    });

    testWidgets('a grouped row names its own channel, not always WhatsApp', (
      tester,
    ) async {
      final group = CustomerConversationGroup.fromJson({
        'group_key': 'INSTAGRAM_customer_9',
        'customer': {'id': 9, 'display_name': 'Ali Elnewehy'},
        'providers': ['INSTAGRAM'],
        'conversations': [
          _conversationJson(id: 1, provider: 'INSTAGRAM'),
          _conversationJson(id: 2, provider: 'INSTAGRAM'),
        ],
      });
      await tester.pumpWidget(
        _app(ConversationGroupRow(group: group, onTap: () {})),
      );

      expect(find.textContaining('Instagram ·'), findsOneWidget);
      expect(find.textContaining('WhatsApp'), findsNothing);
    });
  });

  group('Avatar', () {
    testWidgets('initials stay inside the circle at the largest text size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Center(
            child: InitialsAvatar(
              initials: 'I✌️',
              provider: 'WHATSAPP',
              size: Sizes.rowAvatar,
            ),
          ),
          textScale: 1.4,
        ),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text('I✌️'));
      expect(text.textScaler, TextScaler.noScaling);
      final textBox = tester.getRect(find.text('I✌️'));
      final avatarBox = tester.getRect(find.byType(InitialsAvatar));
      expect(avatarBox.contains(textBox.topLeft), isTrue);
      expect(avatarBox.contains(textBox.bottomRight), isTrue);
    });

    testWidgets('the channel glyph is named for screen readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const Center(
            child: InitialsAvatar(initials: 'AE', provider: 'INSTAGRAM'),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Instagram'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('Quick filters', () {
    for (final v in _variants) {
      testWidgets('selection moves with a tap and is not colour-only — '
          '${v.label}', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            const InboxQuickFilterBar(),
            theme: v.theme,
            locale: v.locale,
            textScale: 1.4,
          ),
        );
        expect(tester.takeException(), isNull);

        bool selected(String key) =>
            tester
                .getSemantics(find.byKey(Key(key)))
                .flagsCollection
                .isSelected ==
            Tristate.isTrue;

        expect(selected('quick_filter_all'), isTrue);
        expect(selected('quick_filter_mine'), isFalse);
        // The selected pill carries a check, so it is told apart without
        // relying on its colour.
        expect(
          find.descendant(
            of: find.byKey(const Key('quick_filter_all')),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('quick_filter_mine')));
        await tester.pump();

        expect(selected('quick_filter_mine'), isTrue);
        expect(selected('quick_filter_all'), isFalse);
        expect(
          find.descendant(
            of: find.byKey(const Key('quick_filter_mine')),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(InboxQuickFilterBar)),
        );
        expect(
          container.read(inboxFiltersProvider).activeQuickFilter,
          InboxQuickFilter.mine,
        );
        semantics.dispose();
      });
    }

    testWidgets('pills are at least the shared pill height', (tester) async {
      await tester.pumpWidget(_app(const InboxQuickFilterBar()));

      expect(
        tester.getSize(find.byKey(const Key('quick_filter_open'))).height,
        greaterThanOrEqualTo(Sizes.pill),
      );
    });
  });

  group('Inbox empty state', () {
    Future<void> pumpEmpty(
      WidgetTester tester,
      ConversationFilters filters, {
      VoidCallback? onClearSearch,
      VoidCallback? onClearFilters,
    }) => tester.pumpWidget(
      _app(
        SizedBox(
          height: 500,
          child: InboxEmptyState(
            filters: filters,
            onClearSearch: onClearSearch ?? () {},
            onClearFilters: onClearFilters ?? () {},
          ),
        ),
      ),
    );

    testWidgets('a search with no matches says so and offers to clear it', (
      tester,
    ) async {
      var cleared = 0;
      await pumpEmpty(
        tester,
        const ConversationFilters(search: 'zzz'),
        onClearSearch: () => cleared++,
      );

      expect(find.byKey(const ValueKey('inboxNoSearchResults')), findsOne);
      expect(find.textContaining('zzz'), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      expect(cleared, 1);
    });

    testWidgets('filters with no matches offer to clear the filters', (
      tester,
    ) async {
      var cleared = 0;
      await pumpEmpty(
        tester,
        const ConversationFilters(unread: true),
        onClearFilters: () => cleared++,
      );

      expect(find.byKey(const ValueKey('inboxNoFilterMatches')), findsOne);
      await tester.tap(find.text('Clear filters'));
      expect(cleared, 1);
    });

    testWidgets('an empty, unfiltered inbox has nothing to clear', (
      tester,
    ) async {
      await pumpEmpty(tester, const ConversationFilters());

      expect(find.byKey(const ValueKey('inboxEmpty')), findsOne);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('Message bubble', () {
    Message message(
      String text, {
      String direction = 'INBOUND',
      List<Map<String, Object?>> attachments = const [],
    }) => Message.fromJson({
      'id': 1,
      'text': text,
      'direction': direction,
      'sender_name': direction == 'INBOUND' ? 'Sarah' : 'Yousef Kandeel',
      'sent_at': '2026-09-28T10:00:00Z',
      'delivery_status': 'DELIVERED',
      'attachments': attachments,
    });

    for (final v in _variants) {
      for (final direction in ['INBOUND', 'OUTBOUND']) {
        testWidgets('long mixed-language text with a URL wraps — '
            '$direction, ${v.label}', (tester) async {
          await tester.pumpWidget(
            _app(
              MessageBubble(
                message: message(
                  'تؤتترنترنترن $_longUrl نرنرنرنشششششن نر and more English',
                  direction: direction,
                ),
              ),
              theme: v.theme,
              locale: v.locale,
              textScale: 1.4,
            ),
          );

          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('text runs in its own direction, whatever the app language', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(MessageBubble(message: message('اهلا وسهلا بيك يا فندم'))),
      );
      final arabic = tester.widget<Text>(find.text('اهلا وسهلا بيك يا فندم'));
      expect(arabic.textDirection, TextDirection.rtl);

      await tester.pumpWidget(
        _app(
          MessageBubble(message: message('Hello, how can I help?')),
          locale: const Locale('ar'),
        ),
      );
      final english = tester.widget<Text>(find.text('Hello, how can I help?'));
      expect(english.textDirection, TextDirection.ltr);
    });

    testWidgets('a picture-only bubble is a thin frame, not a wide margin', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(
            message: message(
              '',
              direction: 'OUTBOUND',
              attachments: [
                {
                  'id': 5,
                  'type': 'IMAGE',
                  'url': 'https://example.com/a.jpg',
                  'mime_type': 'image/jpeg',
                  'file_name': 'a.jpg',
                },
              ],
            ),
          ),
          // The image request carries the session cookie.
          overrides: [cookieJarProvider.overrideWithValue(CookieJar())],
        ),
      );

      final frame = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.padding == const EdgeInsets.all(3));
      expect(frame, hasLength(1));
    });

    testWidgets('a text bubble keeps its comfortable padding', (tester) async {
      await tester.pumpWidget(_app(MessageBubble(message: message('Hi'))));

      final frame = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Container),
            ),
          )
          .where((c) => c.padding == const EdgeInsets.all(3));
      expect(frame, isEmpty);
    });

    testWidgets('dark mode: white text on the agent bubble stays legible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(message: message('Thanks!', direction: 'OUTBOUND')),
          theme: AppTheme.dark,
        ),
      );

      final bubble = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color == ScenarioColors.darkOutgoingBubble);
      final background = bubble.color!;
      // WCAG contrast of white on the bubble.
      final ratio = 1.05 / (background.computeLuminance() + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });
}
