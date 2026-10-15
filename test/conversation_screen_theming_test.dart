/// The whole conversation screen — header, thread and composer — renders
/// without overflow in light and dark themes, in English and Arabic, on a
/// small phone with large text and with the keyboard open, and its composer
/// modes still switch.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _longUrl =
    'https://bekia-egypt.com/careers/apply/flutter-developer/with/a/very/long/path?ref=whatsapp';

final _messages = [
  for (final (i, m) in [
    ('INBOUND', 'اهلا وسهلا بيك يا فندم', '2026-09-27T17:34:00Z'),
    ('INBOUND', _longUrl, '2026-09-27T17:35:00Z'),
    ('OUTBOUND', 'تؤتترنترنترن $_longUrl نرنرنرن', '2026-09-27T18:10:00Z'),
    ('OUTBOUND', 'Thanks — we will get back to you', '2026-09-28T17:52:00Z'),
    ('INBOUND', 'تقتقع', '2026-09-28T17:53:00Z'),
  ].indexed)
    '''{
      "id": ${i + 1},
      "direction": "${m.$1}",
      "text": "${m.$2}",
      "sender_name": "${m.$1 == 'OUTBOUND' ? 'Yousef Kandeel Abdelrahman Elsayed' : 'Indoo'}",
      "sent_at": "${m.$3}",
      "delivery_status": "READ",
      "attachments": []
    }''',
];

ApiClient _client() {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    final path = options.path;
    if (path.contains('/conversations/42/messages/')) {
      return _json('{"results": [${_messages.join(',')}]}');
    }
    if (path.contains('/conversations/42/notes/')) return _json('[]');
    if (path.contains('/conversations/42/')) {
      // The customer wrote just now, so WhatsApp's 24-hour window is open
      // and the composer offers a free-text reply.
      return _json('''{
        "id": 42,
        "customer": {
          "id": 7,
          "display_name": "Mohamed Abdelrahman Elsayed Abdelaziz Elnewehy",
          "initials": "ME",
          "phone": "+201124868273123"
        },
        "assigned_to": {"id": 2, "full_name": "John Doe", "initials": "JD"},
        "provider": "WHATSAPP",
        "channel_name": "WhatsApp Sales Egypt",
        "status": "OPEN",
        "is_follow_up": false,
        "last_customer_message_at": "${DateTime.now().toUtc().toIso8601String()}"
      }''');
    }
    return _json('{}');
  });
  return client;
}

Employee _employee() => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationNote,
    Perm.conversationChangeCategory,
    Perm.conversationChangeStatus,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ThemeData theme,
  required Locale locale,
}) async {
  // A small Android phone, with the largest text size the app allows.
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_client()),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        theme: theme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.4,
          maxScaleFactor: 1.4,
          child: child!,
        ),
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    for (final arabic in [false, true]) {
      final label =
          '${dark ? 'dark' : 'light'} · ${arabic ? 'Arabic' : 'English'}';
      final theme = dark ? AppTheme.dark : AppTheme.light;
      final locale = Locale(arabic ? 'ar' : 'en');

      testWidgets('header, thread and composer fit — $label', (tester) async {
        await _pumpScreen(tester, theme: theme, locale: locale);

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Mohamed Abdelrahman'), findsOneWidget);
        expect(find.textContaining('WhatsApp'), findsWidgets);
        expect(find.textContaining('تقتقع'), findsOneWidget);
        expect(find.byKey(const ValueKey('composer_reply_input')), findsOne);
      });

      testWidgets('keyboard open: the composer still fits — $label', (
        tester,
      ) async {
        await _pumpScreen(tester, theme: theme, locale: locale);

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('composer_reply_input')), findsOne);
      });
    }
  }

  for (final arabicUi in [false, true]) {
    testWidgets('the reply field runs in the direction of what is typed — '
        '${arabicUi ? 'Arabic' : 'English'} app', (tester) async {
      await _pumpScreen(
        tester,
        theme: AppTheme.light,
        locale: Locale(arabicUi ? 'ar' : 'en'),
      );
      final input = find.byKey(const ValueKey('composer_reply_input'));
      TextDirection? direction() =>
          tester.widget<TextField>(input).textDirection;

      // Empty: the app's own direction, so the hint sits where expected.
      expect(direction(), isNull);

      await tester.enterText(input, 'مرحبا، كيف أساعدك؟');
      await tester.pump();
      expect(direction(), TextDirection.rtl);

      await tester.enterText(input, 'Hello, how can I help?');
      await tester.pump();
      expect(direction(), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('composer modes switch and the active one is announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpScreen(
      tester,
      theme: AppTheme.light,
      locale: const Locale('en'),
    );

    await tester.tap(find.text('Internal note'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('composer_internal_note_input')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Internal note')),
      isSemantics(isSelected: true, isButton: true, hasTapAction: true),
    );

    // On a narrow phone at this text size the mode row scrolls sideways.
    await tester.ensureVisible(find.text('Template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Template'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSemantics(find.text('Template')),
      isSemantics(isSelected: true, isButton: true),
    );

    await tester.ensureVisible(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer_reply_input')), findsOne);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
