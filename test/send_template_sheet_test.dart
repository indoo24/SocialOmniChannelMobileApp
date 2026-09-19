/// Tests for the "Send template" flow on the Templates screen.
///
/// Covers the Send button on each template row, the recipient sheet (existing
/// customer vs. typed phone number), the preview, and the outbound send
/// itself — `POST /api/integrations/whatsapp/{channelId}/templates/send/`,
/// whose exact payload shape these tests pin down.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/directory.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/directory_providers.dart';
import 'package:scenario_mobile/features/templates/send_template_sheet.dart';
import 'package:scenario_mobile/features/templates/templates_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
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

Employee _agent() => const Employee(
  id: 1,
  email: 'agent@scenario.test',
  fullName: 'Jane Agent',
  initials: 'JA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: {'channel.view', 'channel.manage', 'conversation.reply'},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Scenario'),
);

const _channelA = ChannelConnection(
  id: 10,
  provider: 'WHATSAPP',
  displayName: 'Scenario DM',
  status: 'CONNECTED',
  isActive: true,
  externalAccountId: '1189064717633052',
);

const _channelB = ChannelConnection(
  id: 20,
  provider: 'WHATSAPP',
  displayName: 'Secondary Line',
  status: 'CONNECTED',
  isActive: true,
  externalAccountId: '9988776655443322',
);

/// Three approved templates plus one that the server says cannot be sent —
/// mirrors the web screenshot's list (ddds, ljkm, gad).
const _templatesResponse = '''
{
  "templates": [
    {
      "id": "1529333772567100",
      "name": "ddds",
      "language": "en_US",
      "category": "UTILITY",
      "status": "APPROVED",
      "body": "تم استلام طلبك بنجاح.",
      "rejected_reason": "",
      "variables": 0,
      "can_send": true,
      "unsupported": []
    },
    {
      "id": "1052821417517189",
      "name": "ljkm",
      "language": "en_US",
      "category": "UTILITY",
      "status": "APPROVED",
      "body": "Your order was received.",
      "rejected_reason": "",
      "variables": 0,
      "can_send": true,
      "unsupported": []
    },
    {
      "id": "2518243342008238",
      "name": "gad",
      "language": "en_US",
      "category": "MARKETING",
      "status": "APPROVED",
      "body": "حمو جاد",
      "rejected_reason": "",
      "variables": 0,
      "can_send": true,
      "unsupported": []
    },
    {
      "id": "9999999999999999",
      "name": "not_ready",
      "language": "en_US",
      "category": "MARKETING",
      "status": "PENDING",
      "body": "Still under review.",
      "rejected_reason": "",
      "variables": 0,
      "can_send": false,
      "unsupported": []
    }
  ]
}
''';

/// Two customers with a phone, one without — the "No phone number on file"
/// row in the web screenshot.
const _customersResponse = '''
{
  "count": 3,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 7,
      "display_name": "Indoo",
      "phone": "+201124868273",
      "email": "indoo@scenario.test",
      "lifecycle_stage": "CUSTOMER",
      "conversation_count": 2
    },
    {
      "id": 8,
      "display_name": "محمد جادالحق",
      "phone": "+201015959361",
      "email": "",
      "lifecycle_stage": "LEAD",
      "conversation_count": 1
    },
    {
      "id": 9,
      "display_name": "Unknown customer",
      "phone": "",
      "email": "",
      "lifecycle_stage": "UNKNOWN",
      "conversation_count": 0
    }
  ]
}
''';

const _sendSuccessResponse = '''
{
  "message": {"id": 501, "text": "تم استلام طلبك بنجاح.", "sender_type": "AGENT"},
  "conversation_id": 42,
  "conversation_created": true,
  "customer_id": 7,
  "customer_name": "Indoo",
  "wa_id": "201124868273"
}
''';

/// Serves templates, customers and the send POST. [onSend] sees the send
/// request and decides its response, so a test can assert the payload or
/// return an error.
_StubAdapter _adapter({
  ResponseBody Function(RequestOptions options)? onSend,
  String templates = _templatesResponse,
  String customers = _customersResponse,
}) {
  return _StubAdapter((options) {
    if (options.path.contains('/templates/send/')) {
      return onSend?.call(options) ?? _json(_sendSuccessResponse, 201);
    }
    if (options.path.contains('/templates/')) {
      return _json(templates, 200);
    }
    if (options.path.contains('/customers/')) {
      return _json(customers, 200);
    }
    return _json('{}', 200);
  });
}

ApiClient _clientFor(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Widget _harness(
  ApiClient client, {
  List<ChannelConnection> channels = const [_channelA],
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(_agent()),
      channelsProvider.overrideWith((ref) async => channels),
    ],
    child: MaterialApp(
      locale: locale,
      theme: theme ?? AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TemplatesScreen(),
    ),
  );
}

/// Scrolls [finder] into view inside the Templates list before tapping it.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView).first,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

/// Opens the send sheet for the named template.
Future<void> _openSheetFor(WidgetTester tester, String templateName) async {
  final button = find.byKey(Key('sendTemplateButton_$templateName'));
  await _scrollTo(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  // Tall viewport: the sheet plus an open keyboard needs the room, and these
  // tests scroll rather than rely on everything fitting at once.
  void useTallScreen(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
  }

  group('Send button on template rows', () {
    testWidgets('every template row renders its own Send button', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();

      // One per template in the response, keyed by that template's name.
      for (final name in ['ddds', 'ljkm', 'gad', 'not_ready']) {
        expect(
          find.byKey(Key('sendTemplateButton_$name')),
          findsOneWidget,
          reason: 'template $name should have its own Send button',
        );
      }
    });

    testWidgets('Send is disabled for a template the server cannot send', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();

      final sendable = tester.widget<OutlinedButton>(
        find.byKey(const Key('sendTemplateButton_ddds')),
      );
      expect(sendable.onPressed, isNotNull);

      // `can_send: false` (PENDING) — tapping would only earn a 400 from Meta.
      final pending = tester.widget<OutlinedButton>(
        find.byKey(const Key('sendTemplateButton_not_ready')),
      );
      expect(pending.onPressed, isNull);
    });

    testWidgets('the existing Templates list content is unchanged', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();

      // Names, statuses and metadata still render as before the Send button.
      expect(find.text('ddds'), findsOneWidget);
      expect(find.text('ljkm'), findsOneWidget);
      expect(find.text('APPROVED'), findsNWidgets(3));
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Create template'), findsOneWidget);
    });
  });

  group('Send sheet — opening and preview', () {
    testWidgets('tapping Send opens the sheet for that exact template', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();

      await _openSheetFor(tester, 'ljkm');

      expect(find.text('Send "ljkm"'), findsOneWidget);
      expect(
        find.text(
          'From Scenario DM. This opens a conversation if there isn\'t one already.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('preview shows that template\'s real body, not another\'s', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();

      await _openSheetFor(tester, 'gad');

      expect(find.text('PREVIEW'), findsOneWidget);
      // gad's body appears twice — once on the card behind, once in the
      // sheet's preview — so assert on the sheet's own copy.
      expect(
        find.descendant(
          of: find.byType(SendTemplateSheet),
          matching: find.text('حمو جاد'),
        ),
        findsOneWidget,
      );
      // And the sheet shows no other template's body — ljkm's card is still
      // on screen behind the sheet, so scope this to the sheet too.
      expect(
        find.descendant(
          of: find.byType(SendTemplateSheet),
          matching: find.text('Your order was received.'),
        ),
        findsNothing,
      );
    });

    testWidgets('each template opens its own sheet with its own body', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();

      await _openSheetFor(tester, 'ddds');
      expect(find.text('Send "ddds"'), findsOneWidget);
      expect(find.text('تم استلام طلبك بنجاح.'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await _openSheetFor(tester, 'ljkm');
      expect(find.text('Send "ljkm"'), findsOneWidget);
      expect(find.text('Your order was received.'), findsWidgets);
    });
  });

  group('Send sheet — recipient selection', () {
    testWidgets('Existing customer is the default and lists customers', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      expect(find.byKey(const Key('templateCustomerSearch')), findsOneWidget);
      expect(find.text('Indoo'), findsOneWidget);
      expect(find.text('+201124868273'), findsOneWidget);
      // A customer with no phone still lists, labelled as such.
      expect(find.text('No phone number on file'), findsOneWidget);
    });

    testWidgets('typing in the search field queries the customers endpoint', (
      tester,
    ) async {
      useTallScreen(tester);
      final adapter = _adapter();
      await tester.pumpWidget(_harness(_clientFor(adapter)));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.enterText(
        find.byKey(const Key('templateCustomerSearch')),
        'indoo',
      );
      // Past the 250ms debounce.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final searched = adapter.received.where(
        (r) =>
            r.path.contains('/customers/') &&
            r.queryParameters['search'] == 'indoo',
      );
      expect(searched, isNotEmpty);
    });

    testWidgets('debounce collapses fast keystrokes into one request', (
      tester,
    ) async {
      useTallScreen(tester);
      final adapter = _adapter();
      await tester.pumpWidget(_harness(_clientFor(adapter)));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      final before = adapter.received
          .where((r) => r.path.contains('/customers/'))
          .length;

      final field = find.byKey(const Key('templateCustomerSearch'));
      await tester.enterText(field, 'i');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(field, 'in');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(field, 'ind');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final added =
          adapter.received.where((r) => r.path.contains('/customers/')).length -
          before;
      // Only the settled term is fetched, not one request per character.
      expect(added, lessThanOrEqualTo(1));
    });

    testWidgets('selecting a customer marks the row and enables Send', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      // Nothing chosen yet.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the selected customer can be changed', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('محمد جادالحق'));
      await tester.pumpAndSettle();

      // Still exactly one selection marker, now on the other row.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('switching to New phone number shows only the phone input', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.byKey(const Key('recipientModePhone')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('templatePhoneInput')), findsOneWidget);
      expect(find.byKey(const Key('templateCustomerSearch')), findsNothing);
      expect(find.text('Phone number'), findsOneWidget);
    });

    testWidgets('Send stays disabled until a phone number is typed', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.byKey(const Key('recipientModePhone')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNull,
      );

      // Whitespace alone is not a recipient.
      await tester.enterText(
        find.byKey(const Key('templatePhoneInput')),
        '   ',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('templatePhoneInput')),
        '+201001234567',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('switching recipient mode clears the other mode\'s value', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recipientModePhone')));
      await tester.pumpAndSettle();
      // The customer no longer counts as the recipient, so Send is off again —
      // the body may carry only one of the two.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNull,
      );
    });
  });

  group('Send sheet — the send request', () {
    testWidgets('customer send posts customer_id and no phone', (tester) async {
      useTallScreen(tester);
      RequestOptions? sendRequest;
      final adapter = _adapter(
        onSend: (options) {
          sendRequest = options;
          return _json(_sendSuccessResponse, 201);
        },
      );

      await tester.pumpWidget(_harness(_clientFor(adapter)));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sendTemplateSubmit')));
      await tester.pumpAndSettle();

      expect(sendRequest, isNotNull);
      expect(sendRequest!.method, 'POST');
      // The channel selected on the screen is the {id} in the URL.
      expect(sendRequest!.path, '/integrations/whatsapp/10/templates/send/');

      final body = sendRequest!.data as Map<String, dynamic>;
      expect(body['customer_id'], 7);
      expect(body['template_name'], 'ddds');
      expect(body['language'], 'en_US');
      expect(body['parameters'], isEmpty);
      // Exactly one recipient: `phone` must not be sent alongside a customer.
      expect(body.containsKey('phone'), isFalse);
    });

    testWidgets('phone send posts the typed number verbatim and no customer', (
      tester,
    ) async {
      useTallScreen(tester);
      RequestOptions? sendRequest;
      final adapter = _adapter(
        onSend: (options) {
          sendRequest = options;
          return _json(_sendSuccessResponse, 201);
        },
      );

      await tester.pumpWidget(_harness(_clientFor(adapter)));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'gad');

      await tester.tap(find.byKey(const Key('recipientModePhone')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('templatePhoneInput')),
        '+20 100 000 0001',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sendTemplateSubmit')));
      await tester.pumpAndSettle();

      final body = sendRequest!.data as Map<String, dynamic>;
      // Passed through unmodified — normalising client-side risks a different
      // answer from the server's own rules.
      expect(body['phone'], '+20 100 000 0001');
      expect(body['template_name'], 'gad');
      expect(body.containsKey('customer_id'), isFalse);
    });

    testWidgets('send uses the WABA account selected on the screen', (
      tester,
    ) async {
      useTallScreen(tester);
      RequestOptions? sendRequest;
      final adapter = _adapter(
        onSend: (options) {
          sendRequest = options;
          return _json(_sendSuccessResponse, 201);
        },
      );

      await tester.pumpWidget(
        _harness(_clientFor(adapter), channels: [_channelA, _channelB]),
      );
      await tester.pumpAndSettle();

      // Switch to the second account before sending.
      await tester.tap(find.text('Scenario DM · 1189064717633052'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secondary Line · 9988776655443322').last);
      await tester.pumpAndSettle();

      await _openSheetFor(tester, 'ddds');
      expect(find.text('Send "ddds"'), findsOneWidget);
      // The sheet names the account it will send from. The dropdown behind it
      // names the same account, so match the sheet's own subtitle exactly.
      expect(
        find.text(
          'From Secondary Line. This opens a conversation if there isn\'t one already.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sendTemplateSubmit')));
      await tester.pumpAndSettle();

      // Channel 20, not the default 10.
      expect(sendRequest!.path, '/integrations/whatsapp/20/templates/send/');
    });

    testWidgets('a successful send closes the sheet and confirms', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sendTemplateSubmit')));
      await tester.pumpAndSettle();

      expect(find.text('Send "ddds"'), findsNothing);
      // Named from the server's own `customer_name`.
      expect(find.text('Template sent to Indoo'), findsOneWidget);
    });

    testWidgets('a backend error is shown verbatim and the sheet stays open', (
      tester,
    ) async {
      useTallScreen(tester);
      final adapter = _adapter(
        onSend: (_) => _json(
          '{"error": {"code": "invalid", "message": "Enter the number in international format, including the country code.", "details": {}}}',
          400,
        ),
      );

      await tester.pumpWidget(_harness(_clientFor(adapter)));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.byKey(const Key('recipientModePhone')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('templatePhoneInput')),
        '0100000001',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sendTemplateSubmit')));
      await tester.pumpAndSettle();

      // The server's own wording, not a client-invented message.
      expect(
        find.text(
          'Enter the number in international format, including the country code.',
        ),
        findsOneWidget,
      );
      // Still open, so the number can be corrected and retried.
      expect(find.text('Send "ddds"'), findsOneWidget);
    });

    testWidgets('a second tap while sending cannot double-send', (
      tester,
    ) async {
      useTallScreen(tester);
      final completer = Completer<ResponseBody>();
      var sendCount = 0;
      final adapter = _StubAdapter((options) {
        if (options.path.contains('/templates/send/')) {
          sendCount++;
          return completer.future;
        }
        if (options.path.contains('/templates/')) {
          return _json(_templatesResponse, 200);
        }
        if (options.path.contains('/customers/')) {
          return _json(_customersResponse, 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(_harness(_clientFor(adapter)));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.text('Indoo'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sendTemplateSubmit')));
      // Enough for the request to reach the adapter, but not for the
      // still-pending completer to resolve.
      await tester.pump(const Duration(milliseconds: 50));

      // In flight: spinner up, button disabled.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sendTemplateSubmit')))
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const Key('sendTemplateSubmit')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(sendCount, 1);

      completer.complete(_json(_sendSuccessResponse, 201));
      await tester.pumpAndSettle();
    });
  });

  group('Send sheet — presentation', () {
    testWidgets('renders in Arabic (RTL)', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _harness(_clientFor(_adapter()), locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      expect(find.text('المستلم'), findsOneWidget);
      expect(find.text('عميل حالي'), findsOneWidget);
      expect(find.text('رقم هاتف جديد'), findsOneWidget);
      expect(find.text('معاينة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _harness(_clientFor(_adapter()), theme: AppTheme.dark),
      );
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      expect(find.text('Send "ddds"'), findsOneWidget);
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keyboard does not cover the phone field or Send', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      await tester.tap(find.byKey(const Key('recipientModePhone')));
      await tester.pumpAndSettle();

      // Simulate the keyboard taking the bottom third of the screen.
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pumpAndSettle();

      final phone = find.byKey(const Key('templatePhoneInput'));
      final submit = find.byKey(const Key('sendTemplateSubmit'));
      await tester.dragUntilVisible(
        submit,
        find.byType(SingleChildScrollView).last,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      // Both reachable above the keyboard line.
      final keyboardTop =
          tester.view.physicalSize.height / tester.view.devicePixelRatio - 600;
      expect(tester.getTopLeft(submit).dy, lessThan(keyboardTop));
      expect(phone, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on a narrow screen without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_harness(_clientFor(_adapter())));
      await tester.pumpAndSettle();
      await _openSheetFor(tester, 'ddds');

      expect(find.text('Send "ddds"'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
