/// Sharing a phone contact (`message_type: CONTACT`, `contacts: [...]`) and
/// showing shared contacts as cards — on the real conversation screen against
/// a stub backend, with the platform picker faked at its provider.
library;

import 'dart:async';
import 'dart:convert';

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
import 'package:scenario_mobile/features/messages/contact_share.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

DateTime _at(int minute) => DateTime.utc(2026, 11, 18, 9, minute);

Map<String, dynamic> _text(int id) => {
  'id': id,
  'direction': 'INBOUND',
  'sender_type': 'CUSTOMER',
  'sender_name': 'Customer',
  'message_type': 'TEXT',
  'text': 'Hello $id',
  'attachments': <Object>[],
  'delivery_status': 'DELIVERED',
  'sent_at': _at(id).toIso8601String(),
};

/// A received contact, as history serialises it.
Map<String, dynamic> _receivedContact() => {
  'id': 30,
  'direction': 'INBOUND',
  'sender_type': 'CUSTOMER',
  'sender_name': 'Customer',
  'message_type': 'CONTACT',
  'text': '👤 سارة أحمد\n+20 100 123 4567',
  'attachments': <Object>[],
  'contacts': [
    {
      'name': {'formatted_name': 'سارة أحمد'},
      'phones': [
        {'phone': '+20 100 123 4567', 'type': 'CELL', 'wa_id': '201001234567'},
        {'phone': '+971 4 555 0000', 'type': 'WORK', 'wa_id': ''},
      ],
    },
  ],
  'contact_delivery': null,
  'delivery_status': 'DELIVERED',
  'sent_at': _at(30).toIso8601String(),
};

class _Server implements HttpClientAdapter {
  bool withReceivedContact = false;
  bool replyFails = false;
  final replies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final path = options.path;
    if (path == '/conversations/42/reply/' && options.method == 'POST') {
      final body = Map<String, dynamic>.from(options.data as Map);
      replies.add(body);
      if (replyFails) {
        return _json({
          'error': {'code': 'provider_error', 'message': 'Refused by Meta.'},
        }, 400);
      }
      return _json({
        'id': 100 + replies.length,
        'direction': 'OUTBOUND',
        'sender_type': 'AGENT',
        'sender_name': 'Sam Agent',
        'message_type': 'CONTACT',
        'text': 'summary',
        'attachments': <Object>[],
        'contacts': body['contacts'],
        'contact_delivery': {'mode': 'whatever-the-server-says'},
        'client_message_id': body['client_message_id'],
        'delivery_status': 'SENT',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      }, 201);
    }
    if (path == '/conversations/42/messages/') {
      return _json({
        'count': 2,
        'next': null,
        'results': [_text(1), if (withReceivedContact) _receivedContact()],
      });
    }
    if (path.contains('/notes/')) return _json([]);
    if (path.contains('/saved-replies/')) return _json({'results': []});
    if (path == '/conversations/42/') {
      return _json({
        'id': 42,
        'customer': {'id': 42, 'display_name': 'Customer', 'initials': 'C'},
        'provider': 'WHATSAPP',
        'status': 'OPEN',
        'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return _json({});
  }

  static ResponseBody _json(Object body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// The platform picker: hands back the queued picks in turn (null = the user
/// backed out), or throws when [unavailable].
class _FakePicker extends ContactPhonePicker {
  _FakePicker(this.picks);

  final List<PickedContact?> picks;
  bool unavailable = false;
  int calls = 0;

  @override
  Future<PickedContact?> pickPhone() async {
    calls++;
    if (unavailable) throw PlatformException(code: 'unavailable');
    return picks.isEmpty ? null : picks.removeAt(0);
  }
}

const _sara = PickedContact(
  name: 'سارة أحمد',
  phone: '+20 100 123 4567',
  type: 'CELL',
  label: 'Mobile',
);
const _omar = PickedContact(
  name: 'Omar Khaled',
  phone: '+44 20 7946 0958',
  type: 'WORK',
  label: 'Work',
);

const _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply, Perm.conversationView},
  visibilityScope: 'ALL',
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
  WidgetTester tester,
  _Server server,
  _FakePicker picker, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee),
        contactPhonePickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await _frames(tester, 20);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.attach_file_rounded));
  await _frames(tester, 8);
}

/// Attachment sheet → Contact → (the fake picker answers) → preview.
Future<void> _chooseContact(WidgetTester tester) async {
  await _openSheet(tester);
  await tester.tap(find.byKey(const ValueKey('attachContactOption')));
  await _frames(tester, 10);
}

final _preview = find.byKey(const ValueKey('contactSharePreview'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the contact on the wire', () {
    test('parses names in any script, every number, and the read-only '
        'wa_id', () {
      final message = Message.fromJson(_receivedContact());
      expect(message.isContact, isTrue);
      final card = message.contacts.single;
      expect(card.displayName, 'سارة أحمد');
      expect(card.phones.map((p) => p.phone), [
        '+20 100 123 4567',
        '+971 4 555 0000',
      ]);
      expect(card.phones.first.type, 'CELL');
      expect(card.phones.first.waId, '201001234567');
    });

    test('sends formatted_name and phone/type — never wa_id', () {
      final card = _sara.toCard();
      final json = card.toJson();
      expect(json, {
        'name': {'formatted_name': 'سارة أحمد'},
        'phones': [
          {'phone': '+20 100 123 4567', 'type': 'CELL'},
        ],
      });
    });

    test('a contact with no name is sent under its number', () {
      const unnamed = PickedContact(name: '  ', phone: '+1 202 555 0101');
      expect(unnamed.toCard().displayName, '+1 202 555 0101');
    });

    test('contact_delivery is kept as sent, whatever its shape', () {
      final message = Message.fromJson({
        ..._receivedContact(),
        'contact_delivery': {'channel': 'x', 'nested': true},
      });
      expect(message.contactDelivery, {'channel': 'x', 'nested': true});
    });

    test('a CONTACT message without contacts is not shown as a card', () {
      final message = Message.fromJson({
        ..._receivedContact(),
        'contacts': <Object>[],
      });
      expect(message.isContact, isFalse);
      expect(message.text, isNotEmpty);
    });
  });

  test('the picker channel: one number, as the platform returns it', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('scenario/contact_picker');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickPhone');
      return {
        'name': 'Omar Khaled',
        'phone': '+44 20 7946 0958',
        'type': 'WORK',
        'label': 'Work',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final picked = await const ContactPhonePicker().pickPhone();
    expect(picked?.name, 'Omar Khaled');
    expect(picked?.phone, '+44 20 7946 0958');
    expect(picked?.type, 'WORK');

    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await const ContactPhonePicker().pickPhone(), isNull);
  });

  testWidgets('"Contact" sits beside the other attachment options', (
    tester,
  ) async {
    await _open(tester, _Server(), _FakePicker([]));
    await _openSheet(tester);
    expect(find.byKey(const ValueKey('attachContactOption')), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    // The existing options are untouched.
    expect(find.byIcon(Icons.insert_drive_file_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
  });

  testWidgets('picking shows a preview: initials, name, number, label', (
    tester,
  ) async {
    final picker = _FakePicker([_sara]);
    await _open(tester, _Server(), picker);
    await _chooseContact(tester);

    expect(picker.calls, 1);
    expect(_preview, findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('contactPreviewName')))
          .data,
      'سارة أحمد',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('contactPreviewPhone')),
        matching: find.text('+20 100 123 4567'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('contactPreviewLabel')), findsOneWidget);
  });

  testWidgets('send: CONTACT with the picked number, no text, no files — '
      'and the card appears in the thread', (tester) async {
    final server = _Server();
    await _open(tester, server, _FakePicker([_sara]));
    await _chooseContact(tester);
    await tester.tap(find.byKey(const ValueKey('contactPreviewSend')));
    await _frames(tester, 12);

    expect(server.replies, hasLength(1));
    final body = server.replies.single;
    expect(body['message_type'], 'CONTACT');
    expect(body['text'], '');
    expect(body.containsKey('attachment_ids'), isFalse);
    expect(body['contacts'], [
      {
        'name': {'formatted_name': 'سارة أحمد'},
        'phones': [
          {'phone': '+20 100 123 4567', 'type': 'CELL'},
        ],
      },
    ]);
    expect(find.byKey(const ValueKey('contactMessageCard')), findsOneWidget);
    expect(find.text('سارة أحمد'), findsOneWidget);
    // The server's text summary is not shown beside the card.
    expect(find.text('summary'), findsNothing);
  });

  testWidgets('Change picks again and the new contact replaces the old', (
    tester,
  ) async {
    final server = _Server();
    final picker = _FakePicker([_sara, _omar]);
    await _open(tester, server, picker);
    await _chooseContact(tester);
    await tester.tap(find.byKey(const ValueKey('contactPreviewChange')));
    await _frames(tester, 12);

    expect(picker.calls, 2);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('contactPreviewName')))
          .data,
      'Omar Khaled',
    );
    await tester.tap(find.byKey(const ValueKey('contactPreviewSend')));
    await _frames(tester, 12);
    final phones = (server.replies.single['contacts'] as List).single['phones'];
    expect(phones, [
      {'phone': '+44 20 7946 0958', 'type': 'WORK'},
    ]);
  });

  testWidgets('Cancel, or backing out of the picker, sends nothing', (
    tester,
  ) async {
    final server = _Server();
    final picker = _FakePicker([_sara, null]);
    await _open(tester, server, picker);
    await _chooseContact(tester);
    await tester.tap(find.byKey(const ValueKey('contactPreviewCancel')));
    await _frames(tester, 10);
    expect(_preview, findsNothing);

    await _chooseContact(tester); // the picker returns nothing
    expect(_preview, findsNothing);
    expect(server.replies, isEmpty);
  });

  testWidgets('a contact without a phone number is refused before preview', (
    tester,
  ) async {
    final server = _Server();
    await _open(
      tester,
      server,
      _FakePicker([const PickedContact(name: 'No Number', phone: ' ')]),
    );
    await _chooseContact(tester);
    expect(_preview, findsNothing);
    expect(
      find.text('This contact has no phone number to share.'),
      findsOneWidget,
    );
    expect(server.replies, isEmpty);
  });

  testWidgets('a picker that cannot open says so', (tester) async {
    await _open(tester, _Server(), _FakePicker([])..unavailable = true);
    await _chooseContact(tester);
    expect(find.text("Couldn't open your contacts."), findsOneWidget);
    expect(_preview, findsNothing);
  });

  testWidgets('a refused send keeps the card with a retry that resends the '
      'same contact', (tester) async {
    final server = _Server()..replyFails = true;
    await _open(tester, server, _FakePicker([_sara]));
    await _chooseContact(tester);
    await tester.tap(find.byKey(const ValueKey('contactPreviewSend')));
    await _frames(tester, 12);

    expect(find.text('Refused by Meta.'), findsWidgets);
    expect(find.byKey(const ValueKey('contactMessageCard')), findsOneWidget);

    server.replyFails = false;
    // The failed bubble's own retry.
    await tester.tap(find.text('Retry').first);
    await _frames(tester, 12);
    expect(server.replies, hasLength(2));
    expect(server.replies.last['contacts'], server.replies.first['contacts']);
    expect(
      server.replies.last['client_message_id'],
      server.replies.first['client_message_id'],
    );
  });

  testWidgets('a received contact from history: card, every number, Call '
      'and Copy', (tester) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _open(tester, _Server()..withReceivedContact = true, _FakePicker([]));
    final card = find.byKey(const ValueKey('contactMessageCard'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('سارة أحمد')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('+20 100 123 4567')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('+971 4 555 0000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Mobile')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Work')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('callCustomerButton')),
      ),
      findsNWidgets(2),
    );
    // The server's text summary is not repeated under the card.
    expect(find.textContaining('👤'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('contactCopy_+20 100 123 4567')),
    );
    await _frames(tester, 4);
    expect(copied, ['+20 100 123 4567']);
    expect(find.text('Number copied'), findsOneWidget);
  });

  testWidgets('Arabic: the option and the card read right to left; numbers '
      'stay left to right', (tester) async {
    await _open(
      tester,
      _Server()..withReceivedContact = true,
      _FakePicker([]),
      locale: const Locale('ar'),
    );
    final number = find.text('+20 100 123 4567');
    expect(tester.widget<Text>(number).textDirection, TextDirection.ltr);
    expect(find.text('جوال'), findsOneWidget);

    await _openSheet(tester);
    expect(find.text('جهة اتصال'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
