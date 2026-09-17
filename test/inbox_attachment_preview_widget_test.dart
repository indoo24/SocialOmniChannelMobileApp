import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Conversation _makeConversation({
  String preview = '',
  List<MessageAttachment> attachments = const [],
  String lastMessageDirection = '',
  String lastMessageDeliveryStatus = '',
  int unreadCount = 0,
}) => Conversation(
  id: 1,
  customer: const CustomerBrief(id: 100, displayName: 'Sarah Connor'),
  provider: 'WHATSAPP',
  status: 'OPEN',
  priority: 'NORMAL',
  unreadCount: unreadCount,
  messageCount: 1,
  lastMessagePreview: preview,
  lastMessageAttachments: attachments,
  lastMessageDirection: lastMessageDirection,
  lastMessageDeliveryStatus: lastMessageDeliveryStatus,
);

Future<void> _pumpWidget(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('Inbox ConversationRow Attachment Previews', () {
    testWidgets(
      'displays "Photo" when latest message is [[media:IMAGE]] in English',
      (tester) async {
        final convo = _makeConversation(preview: '[[media:IMAGE]]');
        await _pumpWidget(
          tester,
          ConversationRow(conversation: convo, onTap: () {}),
        );

        expect(find.text('Photo'), findsOneWidget);
        expect(find.text('[[media:IMAGE]]'), findsNothing);
      },
    );

    testWidgets(
      'displays "صورة" when latest message is [[media:IMAGE]] in Arabic',
      (tester) async {
        final convo = _makeConversation(preview: '[[media:IMAGE]]');
        await _pumpWidget(
          tester,
          ConversationRow(conversation: convo, onTap: () {}),
          locale: const Locale('ar'),
        );

        expect(find.text('صورة'), findsOneWidget);
        expect(find.text('[[media:IMAGE]]'), findsNothing);
      },
    );

    testWidgets(
      'displays "Voice message" when structured voice attachment is present',
      (tester) async {
        final convo = _makeConversation(
          preview: '[[media:VOICE]]',
          attachments: [
            const MessageAttachment(type: 'VOICE', durationMs: 4000),
          ],
        );
        await _pumpWidget(
          tester,
          ConversationRow(conversation: convo, onTap: () {}),
        );

        expect(find.text('Voice message'), findsOneWidget);
        expect(find.text('[[media:VOICE]]'), findsNothing);
      },
    );

    testWidgets('displays "رسالة صوتية" for voice in Arabic', (tester) async {
      final convo = _makeConversation(
        preview: '[[media:VOICE]]',
        attachments: [const MessageAttachment(type: 'VOICE', durationMs: 4000)],
      );
      await _pumpWidget(
        tester,
        ConversationRow(conversation: convo, onTap: () {}),
        locale: const Locale('ar'),
      );

      expect(find.text('رسالة صوتية'), findsOneWidget);
      expect(find.text('[[media:VOICE]]'), findsNothing);
    });

    testWidgets('displays "Video" / "فيديو" for video message', (tester) async {
      final convo = _makeConversation(preview: '[[media:VIDEO]]');
      await _pumpWidget(
        tester,
        ConversationRow(conversation: convo, onTap: () {}),
      );
      expect(find.text('Video'), findsOneWidget);

      await _pumpWidget(
        tester,
        ConversationRow(conversation: convo, onTap: () {}),
        locale: const Locale('ar'),
      );
      expect(find.text('فيديو'), findsOneWidget);
    });

    testWidgets('displays actual filename for document when available', (
      tester,
    ) async {
      final convo = _makeConversation(
        attachments: [
          const MessageAttachment(type: 'FILE', fileName: 'contract.pdf'),
        ],
      );
      await _pumpWidget(
        tester,
        ConversationRow(conversation: convo, onTap: () {}),
      );

      expect(find.text('contract.pdf'), findsOneWidget);
    });

    testWidgets('displays "Document" / "مستند" when document has no filename', (
      tester,
    ) async {
      final convo = _makeConversation(preview: '[[media:FILE]]');
      await _pumpWidget(
        tester,
        ConversationRow(conversation: convo, onTap: () {}),
      );
      expect(find.text('Document'), findsOneWidget);

      await _pumpWidget(
        tester,
        ConversationRow(conversation: convo, onTap: () {}),
        locale: const Locale('ar'),
      );
      expect(find.text('مستند'), findsOneWidget);
    });

    testWidgets(
      'displays "Photos" for multiple images and "Attachments" for mixed',
      (tester) async {
        final photosConvo = _makeConversation(
          preview: '[[media:IMAGE]] [[media:IMAGE]]',
        );
        await _pumpWidget(
          tester,
          ConversationRow(conversation: photosConvo, onTap: () {}),
        );
        expect(find.text('Photos'), findsOneWidget);

        final mixedConvo = _makeConversation(
          preview: '[[media:IMAGE]] [[media:FILE]]',
        );
        await _pumpWidget(
          tester,
          ConversationRow(conversation: mixedConvo, onTap: () {}),
        );
        expect(find.text('Attachments'), findsOneWidget);
      },
    );

    testWidgets(
      'preserves outbound delivery ticks alongside formatted preview',
      (tester) async {
        final convo = _makeConversation(
          preview: '[[media:IMAGE]]',
          lastMessageDirection: 'OUTBOUND',
          lastMessageDeliveryStatus: 'DELIVERED',
        );
        await _pumpWidget(
          tester,
          ConversationRow(conversation: convo, onTap: () {}),
        );

        expect(find.text('Photo'), findsOneWidget);
        expect(find.byIcon(Icons.done_all), findsOneWidget);
      },
    );
  });

  group('Inbox GroupedConversationRow Attachment Previews', () {
    testWidgets('displays formatted preview for CustomerConversationGroup', (
      tester,
    ) async {
      final convo = _makeConversation(preview: '[[media:IMAGE]]');
      final group = CustomerConversationGroup(
        groupKey: 'WHATSAPP:100',
        customer: convo.customer,
        provider: 'WHATSAPP',
        conversations: [convo],
      );

      await _pumpWidget(
        tester,
        ConversationGroupRow(group: group, onTap: () {}),
      );

      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('[[media:IMAGE]]'), findsNothing);
    });
  });
}
