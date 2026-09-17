/// `ConversationRow` renders the delivery tick icon only for an outbound
/// last message, and never for an inbound one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Conversation _makeConversation({
  String lastMessageDirection = '',
  String lastMessageDeliveryStatus = '',
}) => Conversation.fromJson({
  'id': 1,
  'customer': {'id': 100, 'display_name': 'Sarah Connor'},
  'provider': 'WHATSAPP',
  'status': 'OPEN',
  'priority': 'NORMAL',
  'unread_count': 0,
  'message_count': 1,
  'last_message_preview': 'Hello there',
  'last_message_direction': lastMessageDirection,
  'last_message_delivery_status': lastMessageDeliveryStatus,
});

Future<void> _pumpRow(WidgetTester tester, Conversation conversation) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationRow(conversation: conversation, onTap: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('an outbound DELIVERED last message shows the double-tick icon', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      _makeConversation(
        lastMessageDirection: 'OUTBOUND',
        lastMessageDeliveryStatus: 'DELIVERED',
      ),
    );

    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an outbound FAILED last message shows the error icon', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      _makeConversation(
        lastMessageDirection: 'OUTBOUND',
        lastMessageDeliveryStatus: 'FAILED',
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('an inbound last message shows no delivery tick at all', (
    tester,
  ) async {
    await _pumpRow(tester, _makeConversation(lastMessageDirection: 'INBOUND'));

    expect(find.byIcon(Icons.done_all), findsNothing);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets(
    'no direction at all (conversation with no messages yet) shows no tick',
    (tester) async {
      await _pumpRow(tester, _makeConversation());

      expect(find.byIcon(Icons.done_all), findsNothing);
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    },
  );
}
