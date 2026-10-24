/// The customer's number under their name in the conversation details sheet,
/// and the Call action beside Save to contacts.
///
/// Mocked, not real: the platform is faked (`UrlLauncherPlatform`,
/// `ContactSaver`), so these prove the right `tel:` link is handed to
/// `url_launcher` and that failures are reported — not that a dialer opens on
/// a phone. That needs a device.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/phone_dialer.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/directory/save_to_contacts.dart';
import 'package:scenario_mobile/features/messages/conversation_actions_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_ar.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations_en.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  final modes = <PreferredLaunchMode>[];
  bool succeeds = true;
  Object? throws;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    modes.add(options.mode);
    final error = throws;
    if (error != null) throw error;
    return succeeds;
  }
}

class _FakeSaver implements ContactSaver {
  final calls = <(String, String)>[];

  @override
  Future<ContactSaveOutcome> createContact({
    required String name,
    required String phone,
  }) async {
    calls.add((name, phone));
    return ContactSaveOutcome.saved;
  }
}

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

ApiClient _client({required String phone}) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter((options) {
    final path = options.path;
    if (path.endsWith('/conversations/1/')) {
      return _json('''{
        "id": 1,
        "customer": {
          "id": 1,
          "display_name": "Sarah Connor",
          "initials": "SC",
          "phone": "$phone",
          "email": "sarah@example.com"
        },
        "provider": "WHATSAPP",
        "channel_name": "Support Line",
        "status": "OPEN",
        "priority": "NORMAL",
        "unread_count": 0,
        "message_count": 5
      }''');
    }
    if (path.contains('/messages/')) {
      return _json('{"results": [], "count": 0}');
    }
    if (path.contains('/orders')) {
      return _json(
        '{"count": 0, "next": null, "previous": null, "results": []}',
      );
    }
    if (path.contains('/facts') ||
        path.contains('/conversions') ||
        path.contains('/events') ||
        path.contains('/notes')) {
      return _json('[]');
    }
    return _json('{}');
  });
  return client;
}

final _agent = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply},
  visibilityScope: 'ASSIGNED',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Widget _app({
  required String phone,
  required ContactSaver saver,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(_client(phone: phone)),
    currentEmployeeProvider.overrideWithValue(_agent),
    contactSaverProvider.overrideWithValue(saver),
  ],
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              showConversationActionsSheet(context, conversationId: 1),
          child: const Text('open actions'),
        ),
      ),
    ),
  ),
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open actions'));
  await tester.pumpAndSettle();
}

final _callButton = find.byKey(const Key('callCustomerButton'));
final _saveButton = find.byKey(const Key('saveToContactsButton'));
final _phoneLine = find.byKey(const Key('contactPhoneLine'));

void main() {
  late _FakeUrlLauncher launcher;

  setUp(() {
    launcher = _FakeUrlLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
  });

  // -------------------------------------------------------------------------
  group('what is dialable', () {
    test('digits with a leading + keep the country code', () {
      expect(dialableNumber('+201012345678'), '+201012345678');
      expect(dialableNumber('+20 101 234 5678'), '+201012345678');
      expect(dialableNumber('+20-101-234-5678'), '+201012345678');
      expect(dialableNumber('(+20) 101.234.5678'), '+201012345678');
      expect(dialableNumber('  +201012345678  '), '+201012345678');
      expect(dialableNumber('+1 (555) 010-9999'), '+15550109999');
    });

    test('a number without + is dialed as stored, nothing is added or '
        'removed', () {
      expect(dialableNumber('01012345678'), '01012345678');
      expect(dialableNumber('201012345678'), '201012345678');
      expect(dialableNumber('0020 101 234 5678'), '00201012345678');
    });

    test('invisible direction marks and no-break spaces are dropped', () {
      expect(
        dialableNumber('\u200E+20\u00A0101 234 5678\u200F'),
        '+201012345678',
      );
      expect(dialableNumber('\u202A+201012345678\u202C'), '+201012345678');
    });

    test('Arabic-Indic digits are read as the digits they are', () {
      expect(dialableNumber('+٢٠١٠١٢٣٤٥٦٧٨'), '+201012345678');
      expect(dialableNumber('۰۱۰۱۲۳۴۵۶۷۸'), '01012345678');
    });

    test('missing and blank are not numbers', () {
      expect(dialableNumber(null), isNull);
      expect(dialableNumber(''), isNull);
      expect(dialableNumber('   '), isNull);
    });

    test('anything that is not a phone number is refused', () {
      for (final bad in [
        'abc',
        '12ab345678',
        '+',
        '12345', // too short
        '1234567890123456', // 16 digits: longer than E.164
        '+20+1012345678', // a second +
        '20+1012345678', // + not first
        '*21*+201012345678#', // a call-forwarding code
        '#31#+201012345678', // a supplementary service code
        '*21*01012345678#', // call forwarding, without a +
        '#31#01012345678', // hide caller id, without a +
        '*0101234567', // starts with a code
        '01012345678#', // ends with one
        '*1234567#',
        '+201012345678;ext=1', // dial extension
        '+20101,2345678', // a pause
        'tel:+201012345678', // a link, not a number
        '+20 101 234 5678 ext 4',
        '١٢٣٤٥٦٧٨٩a',
      ]) {
        expect(dialableNumber(bad), isNull, reason: bad);
      }
    });

    test('the link is a tel: URI carrying exactly the normalized number', () {
      final uri = telUri('+20 101 234 5678');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'tel');
      expect(uri.path, '+201012345678');
      expect(uri.toString(), 'tel:+201012345678');
      expect(telUri('01012345678').toString(), 'tel:01012345678');
      expect(telUri('nope'), isNull);
      expect(telUri(null), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('opening the dialer', () {
    test('hands url_launcher the tel: link, to the phone\'s own app', () async {
      expect(await dialNumber('+20 101 234 5678'), DialOutcome.opened);
      expect(launcher.launched, ['tel:+201012345678']);
      expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
    });

    test('no number, or not a number: nothing is launched', () async {
      expect(await dialNumber(null), DialOutcome.noNumber);
      expect(await dialNumber('  '), DialOutcome.noNumber);
      expect(await dialNumber('abc'), DialOutcome.invalidNumber);
      expect(await dialNumber('*21*+201012345678#'), DialOutcome.invalidNumber);
      expect(launcher.launched, isEmpty);
    });

    test('a device with no phone app is reported, not thrown', () async {
      launcher.succeeds = false;
      expect(await dialNumber('+201012345678'), DialOutcome.unavailable);
    });

    test('a platform error is reported, not thrown', () async {
      launcher.throws = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      expect(await dialNumber('+201012345678'), DialOutcome.unavailable);
    });
  });

  // -------------------------------------------------------------------------
  group('the details sheet', () {
    testWidgets('the number sits under the name, once, with the channel '
        'still below it', (tester) async {
      await tester.pumpWidget(
        _app(phone: '+201012345678', saver: _FakeSaver()),
      );
      await _openSheet(tester);
      expect(tester.takeException(), isNull);

      final name = find.text('Sarah Connor');
      final phone = find.byKey(const Key('contactPhoneText'));
      final channel = find.text('Support Line');
      expect(name, findsOneWidget);
      expect(phone, findsOneWidget);
      // Shown once: the old row in the details list is gone.
      expect(find.text('+201012345678'), findsOneWidget);
      expect(find.text('Phone'), findsNothing);

      final nameBox = tester.getRect(name);
      final phoneBox = tester.getRect(_phoneLine);
      final channelBox = tester.getRect(channel);
      expect(phoneBox.top, greaterThanOrEqualTo(nameBox.bottom));
      expect(channelBox.top, greaterThanOrEqualTo(phoneBox.bottom));
      // Lined up with the name, not indented or centred.
      expect(phoneBox.left, nameBox.left);

      // Larger and heavier than the detail rows it used to be among.
      final style = tester.widget<Text>(phone).style!;
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontSize, greaterThanOrEqualTo(14));

      // The rest of the details are as they were.
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('sarah@example.com'), findsOneWidget);
    });

    testWidgets('no number: no phone line, and no empty row either', (
      tester,
    ) async {
      await tester.pumpWidget(_app(phone: '', saver: _FakeSaver()));
      await _openSheet(tester);
      expect(_phoneLine, findsNothing);
      expect(find.text('Phone'), findsNothing);
      expect(find.text('Sarah Connor'), findsOneWidget);
    });

    testWidgets('Call and Add to contacts are both there, Call first', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(phone: '+201012345678', saver: _FakeSaver()),
      );
      await _openSheet(tester);

      expect(_callButton, findsOneWidget);
      expect(_saveButton, findsOneWidget);
      expect(find.byTooltip('Call'), findsOneWidget);
      expect(find.byTooltip('Add to contacts'), findsOneWidget);
      expect(
        tester.getCenter(_callButton).dx,
        lessThan(tester.getCenter(_saveButton).dx),
      );
      // Easy to tap.
      expect(
        tester.getSize(_callButton).shortestSide,
        greaterThanOrEqualTo(32),
      );
    });

    testWidgets('Call opens the dialer on the number', (tester) async {
      await tester.pumpWidget(
        _app(phone: '+20 101 234 5678', saver: _FakeSaver()),
      );
      await _openSheet(tester);

      await tester.tap(_callButton);
      await tester.pumpAndSettle();

      expect(launcher.launched, ['tel:+201012345678']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Call with no number says so and opens nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_app(phone: '', saver: _FakeSaver()));
      await _openSheet(tester);

      await tester.tap(_callButton);
      await tester.pumpAndSettle();

      expect(launcher.launched, isEmpty);
      expect(
        find.text('This customer has no phone number to call.'),
        findsOneWidget,
      );
    });

    testWidgets('Call with something that is not a number says so', (
      tester,
    ) async {
      await tester.pumpWidget(_app(phone: 'not a number', saver: _FakeSaver()));
      await _openSheet(tester);

      await tester.tap(_callButton);
      await tester.pumpAndSettle();

      expect(launcher.launched, isEmpty);
      expect(find.text("This phone number can't be dialed."), findsOneWidget);
    });

    testWidgets('a dialer that will not open is reported', (tester) async {
      launcher.succeeds = false;
      await tester.pumpWidget(
        _app(phone: '+201012345678', saver: _FakeSaver()),
      );
      await _openSheet(tester);

      await tester.tap(_callButton);
      await tester.pumpAndSettle();

      expect(launcher.launched, ['tel:+201012345678']);
      expect(
        find.text("The phone app can't be opened on this device."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add to contacts still works beside it', (tester) async {
      final saver = _FakeSaver();
      await tester.pumpWidget(_app(phone: '+201012345678', saver: saver));
      await _openSheet(tester);

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(saver.calls, [('Sarah Connor', '+201012345678')]);
      expect(launcher.launched, isEmpty);
      expect(find.text('Contact saved.'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final arabic in [false, true]) {
        final label =
            '${dark ? 'dark' : 'light'} ${arabic ? 'Arabic RTL' : 'English LTR'}';
        final l10n = arabic ? AppLocalizationsAr() : AppLocalizationsEn();

        testWidgets('layout and labels — $label', (tester) async {
          await tester.pumpWidget(
            _app(
              phone: '+201012345678',
              saver: _FakeSaver(),
              locale: Locale(arabic ? 'ar' : 'en'),
              theme: dark ? AppTheme.dark : AppTheme.light,
            ),
          );
          await _openSheet(tester);
          expect(tester.takeException(), isNull);

          // The labels the agent is told, in their language.
          expect(find.byTooltip(l10n.callAction), findsOneWidget);
          expect(find.byTooltip(l10n.saveContactAction), findsOneWidget);
          if (arabic) {
            expect(l10n.callAction, 'اتصال');
            expect(l10n.saveContactAction, 'إضافة إلى جهات الاتصال');
          }

          // The number reads left to right in both, and stays under the name.
          final phone = tester.widget<Text>(
            find.byKey(const Key('contactPhoneText')),
          );
          expect(phone.textDirection, TextDirection.ltr);
          expect(
            tester.getRect(_phoneLine).top,
            greaterThanOrEqualTo(
              tester.getRect(find.text('Sarah Connor')).bottom,
            ),
          );
          // The first action follows the reading direction.
          final callX = tester.getCenter(_callButton).dx;
          final saveX = tester.getCenter(_saveButton).dx;
          expect(arabic ? callX > saveX : callX < saveX, isTrue);
        });
      }
    }

    testWidgets('a very long number on a narrow screen does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3.0, 640 * 3.0);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          phone: '+20 1012 3456 7890 1234 5678 9012 3456 7890',
          saver: _FakeSaver(),
          locale: const Locale('ar'),
        ),
      );
      await _openSheet(tester);

      expect(tester.takeException(), isNull);
      expect(_phoneLine, findsOneWidget);
      expect(_callButton, findsOneWidget);
      // Shortened inside the sheet's width, not beyond it.
      expect(tester.getRect(_phoneLine).right, lessThanOrEqualTo(320));
      expect(tester.getRect(_phoneLine).left, greaterThanOrEqualTo(0));
    });
  });
}
