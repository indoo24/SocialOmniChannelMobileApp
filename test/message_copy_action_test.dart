/// Regression tests for the long-press Copy action:
///
/// 1. Long-press text message → Copy action appears.
/// 2. Tapping Copy places the exact message text in the clipboard.
/// 3. Copy closes the action menu.
/// 4. Text + attachment copies only the text.
/// 5. Image-only message does not show Copy.
/// 6. Internal note can be copied.
/// 7. Reply message copies its own text, not the quoted message.
/// 8. Existing Reply behavior remains unchanged.
/// Plus: Arabic RTL labels.
library;

import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _messagesJson = '''
{
  "results": [
    {
      "id": 1,
      "text": "Plain text message",
      "direction": "INBOUND",
      "sender_name": "Sarah",
      "sent_at": "2026-09-02T14:10:00Z",
      "delivery_status": "DELIVERED"
    },
    {
      "id": 2,
      "text": "Caption with file",
      "direction": "INBOUND",
      "sender_name": "Sarah",
      "sent_at": "2026-09-02T14:11:00Z",
      "delivery_status": "DELIVERED",
      "attachments": [
        {
          "id": "att-77",
          "type": "FILE",
          "url": "https://cdn.example.com/invoice.pdf",
          "file_name": "invoice.pdf",
          "mime_type": "application/pdf",
          "size_bytes": 1048576
        }
      ]
    },
    {
      "id": 3,
      "text": "Original question",
      "direction": "INBOUND",
      "sender_name": "Sarah",
      "sent_at": "2026-09-02T14:12:00Z",
      "delivery_status": "DELIVERED"
    },
    {
      "id": 4,
      "text": "My own reply text",
      "direction": "OUTBOUND",
      "sender_name": "Sam Agent",
      "sent_at": "2026-09-02T14:13:00Z",
      "delivery_status": "DELIVERED",
      "reply_to": {
        "id": 3,
        "text": "Original question",
        "message_type": "TEXT",
        "direction": "INBOUND",
        "sender_name": "Sarah",
        "sent_at": "2026-09-02T14:12:00Z",
        "is_deleted": false,
        "available": true
      }
    }
  ]
}
''';

const _notesJson = '''
[
  {
    "id": 101,
    "body": "Customer prefers evening delivery.",
    "author_name": "Yousef Kandeel",
    "author_initials": "YK",
    "created_at": "2026-09-02T14:14:00Z"
  }
]
''';

ApiClient _client() {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    if (options.path.contains('/conversations/42/messages/')) {
      return _json(_messagesJson, 200);
    }
    if (options.path.contains('/conversations/42/notes/')) {
      return _json(_notesJson, 200);
    }
    if (options.path.contains('/conversations/42/')) {
      return _json('''
{
  "id": 42,
  "customer": {"id": 7, "display_name": "Sarah", "avatar_url": "", "initials": "S", "phone": "+201124868273"},
  "provider": "WHATSAPP",
  "channel_name": "Scenario Sales",
  "status": "OPEN",
  "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
}''', 200);
    }
    if (options.path.contains('/saved-replies/')) {
      return _json('{"results": []}', 200);
    }
    if (options.path.contains('/facts') ||
        options.path.contains('/orders') ||
        options.path.contains('/channels/')) {
      return _json('[]', 200);
    }
    return _json('{}', 200);
  });
  return client;
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationNote},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

Widget _harness({Locale? locale, ThemeData? theme}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(_client()),
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

/// Records every `Clipboard.setData` the app makes.
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

/// Tall enough that every message and the note are built at once — the
/// timeline is a lazy list anchored to the newest message.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// [finder] inside the open long-press menu — "Reply" alone also matches the
/// composer's mode pill.
Finder _inMenu(Finder finder) => find.descendant(
  of: find.byType(PopupMenuItem<VoidCallback>),
  matching: finder,
);

Future<void> _longPressAndCopy(WidgetTester tester, Finder target) async {
  await tester.longPress(target);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.copy_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('1. Long-pressing a text message shows Copy', (tester) async {
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Plain text message'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(_inMenu(find.text('Reply')), findsOneWidget);
  });

  testWidgets('2. Tapping Copy puts the exact text on the clipboard and '
      'confirms with a snackbar', (tester) async {
    final copied = _captureClipboard(tester);
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await _longPressAndCopy(tester, find.text('Plain text message'));

    expect(copied, ['Plain text message']);
    expect(find.widgetWithText(SnackBar, 'Copied'), findsOneWidget);
  });

  testWidgets('3. Copy closes the action menu', (tester) async {
    _captureClipboard(tester);
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await _longPressAndCopy(tester, find.text('Plain text message'));

    expect(find.byType(PopupMenuItem<VoidCallback>), findsNothing);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
    expect(_inMenu(find.text('Reply')), findsNothing);
  });

  testWidgets('4. Text + attachment copies only the text', (tester) async {
    final copied = _captureClipboard(tester);
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await _longPressAndCopy(tester, find.text('Caption with file'));

    expect(copied, ['Caption with file']);
    expect(copied.single, isNot(contains('invoice.pdf')));
    expect(copied.single, isNot(contains('att-77')));
  });

  testWidgets('6. An internal note can be copied', (tester) async {
    final copied = _captureClipboard(tester);
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Customer prefers evening delivery.'));
    await tester.pumpAndSettle();
    // Only Copy — a note has no Reply/Delete in this menu.
    expect(_inMenu(find.text('Reply')), findsNothing);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, ['Customer prefers evening delivery.']);
    expect(find.widgetWithText(SnackBar, 'Copied'), findsOneWidget);
  });

  testWidgets('7. A reply copies its own text, not the quoted message', (
    tester,
  ) async {
    final copied = _captureClipboard(tester);
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await _longPressAndCopy(tester, find.text('My own reply text'));

    expect(copied, ['My own reply text']);
  });

  testWidgets('8. Reply still works exactly as before', (tester) async {
    _useTallScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Plain text message'));
    await tester.pumpAndSettle();
    await tester.tap(_inMenu(find.byIcon(Icons.reply_outlined)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Replying to Sarah'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });

  testWidgets('Arabic RTL: Copy and its confirmation are localized', (
    tester,
  ) async {
    final copied = _captureClipboard(tester);
    _useTallScreen(tester);
    await tester.pumpWidget(
      _harness(locale: const Locale('ar'), theme: AppTheme.dark),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Plain text message'));
    await tester.pumpAndSettle();
    expect(find.text('نسخ'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('نسخ'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('نسخ'));
    await tester.pumpAndSettle();

    expect(copied, ['Plain text message']);
    expect(find.widgetWithText(SnackBar, 'تم النسخ'), findsOneWidget);
  });

  group('5. Media-only messages', () {
    Widget bubble(Message message) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: MessageBubble(message: message, onReply: () {}),
          ),
        ),
      ),
    );

    testWidgets('an image-only message offers Reply but not Copy', (
      tester,
    ) async {
      // The `[media: …]` marker is the only text the backend sent.
      final message = Message.fromJson(const {
        'id': 9,
        'text': '[media: image name=photo.jpg]',
        'direction': 'INBOUND',
        'sender_name': 'Sarah',
        'sent_at': '2026-09-02T14:10:00Z',
      });
      expect(message.text, isEmpty);

      await tester.pumpWidget(bubble(message));
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onLongPressStart != null,
        ),
      );
      await tester.pumpAndSettle();

      expect(_inMenu(find.text('Reply')), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });

    test('copyableMessageText rejects empty and whitespace-only text', () {
      expect(copyableMessageText(''), isNull);
      expect(copyableMessageText('   \n '), isNull);
      expect(copyableMessageText('  hi there '), 'hi there');
    });
  });
}
