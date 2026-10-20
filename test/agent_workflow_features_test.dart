/// Saved replies grouped by category, Save to contacts, and WhatsApp's
/// `*bold*` — what each shows, and that each keeps to the data the backend
/// gave (no invented categories, numbers or formatting).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/whatsapp_format.dart';
import 'package:scenario_mobile/core/widgets/linkified_text.dart';
import 'package:scenario_mobile/features/directory/save_to_contacts.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/features/saved_replies/saved_replies_providers.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply_picker.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

SavedReply _reply(int id, String title, {String category = ''}) => SavedReply(
  id: id,
  title: title,
  body: 'Body of $title',
  category: category,
);

/// Every visible run of text in [finder]'s rich text, with whether it is bold.
List<(String, bool)> _runs(WidgetTester tester, Finder finder) {
  final runs = <(String, bool)>[];
  final rich = tester.widget<RichText>(
    find.descendant(of: finder, matching: find.byType(RichText)).first,
  );
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      runs.add((span.text!, span.style?.fontWeight == FontWeight.w700));
    }
    return true;
  });
  return runs;
}

class _FakeContactSaver implements ContactSaver {
  _FakeContactSaver(this.outcome);

  final ContactSaveOutcome outcome;
  final calls = <(String, String)>[];

  @override
  Future<ContactSaveOutcome> createContact({
    required String name,
    required String phone,
  }) async {
    calls.add((name, phone));
    return outcome;
  }
}

void main() {
  // -------------------------------------------------------------------------
  group('Saved replies by category', () {
    test('grouped alphabetically, uncategorized last, server order kept', () {
      final groups = groupSavedRepliesByCategory([
        _reply(1, 'Refund policy', category: 'Returns'),
        _reply(2, 'Hello'),
        _reply(3, 'Prices', category: 'Billing'),
        _reply(4, 'Exchange', category: 'returns '),
        _reply(5, 'Bye'),
      ]);

      expect([for (final g in groups) g.category], ['Billing', 'Returns', '']);
      // "Returns" and "returns " are one category; the server's order of
      // replies inside it is kept.
      expect([for (final r in groups[1].replies) r.id], [1, 4]);
      expect([for (final r in groups[2].replies) r.id], [2, 5]);
    });

    test('no replies, no groups', () {
      expect(groupSavedRepliesByCategory(const []), isEmpty);
    });

    Future<SavedReply?> openPicker(
      WidgetTester tester,
      List<SavedReply> replies, {
      Locale locale = const Locale('en'),
    }) async {
      SavedReply? picked;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showSavedReplyPicker(context),
              child: const Text('open'),
            ),
          ),
          locale: locale,
          overrides: [
            savedRepliesProvider.overrideWith((ref, search) async => replies),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return picked;
    }

    final replies = [
      _reply(1, 'Refund policy', category: 'Returns'),
      _reply(2, 'Opening hours'),
      _reply(3, 'Prices', category: 'Billing'),
    ];

    testWidgets('chips for each category; headings group the list', (
      tester,
    ) async {
      await openPicker(tester, replies);

      for (final key in ['*', 'Billing', 'Returns', '']) {
        expect(find.byKey(Key('savedReplyCategory-$key')), findsOneWidget);
      }
      // "Uncategorized" is both a chip and a heading.
      expect(find.text('Uncategorized'), findsNWidgets(2));
      expect(find.byKey(const Key('savedReply-1')), findsOneWidget);
      expect(find.byKey(const Key('savedReply-2')), findsOneWidget);
      expect(find.byKey(const Key('savedReply-3')), findsOneWidget);
    });

    testWidgets('choosing a category shows only its replies', (tester) async {
      await openPicker(tester, replies);

      await tester.tap(find.byKey(const Key('savedReplyCategory-Billing')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('savedReply-3')), findsOneWidget);
      expect(find.byKey(const Key('savedReply-1')), findsNothing);
      expect(find.byKey(const Key('savedReply-2')), findsNothing);

      await tester.tap(find.byKey(const Key('savedReplyCategory-')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('savedReply-2')), findsOneWidget);
      expect(find.byKey(const Key('savedReply-3')), findsNothing);

      await tester.tap(find.byKey(const Key('savedReplyCategory-*')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('savedReply-1')), findsOneWidget);
    });

    testWidgets('tapping a reply hands it back to the composer', (
      tester,
    ) async {
      SavedReply? picked;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showSavedReplyPicker(context),
              child: const Text('open'),
            ),
          ),
          overrides: [
            savedRepliesProvider.overrideWith((ref, search) async => replies),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('savedReply-3')));
      await tester.pumpAndSettle();

      expect(picked?.id, 3);
    });

    testWidgets('no category anywhere: no chips, no headings', (tester) async {
      await openPicker(tester, [_reply(1, 'A'), _reply(2, 'B')]);

      expect(find.byKey(const Key('savedReplyCategory-*')), findsNothing);
      expect(find.text('Uncategorized'), findsNothing);
      expect(find.byKey(const Key('savedReply-1')), findsOneWidget);
    });

    testWidgets('Arabic: localized labels, Arabic category names', (
      tester,
    ) async {
      await openPicker(tester, [
        _reply(1, 'سياسة الاسترجاع', category: 'المرتجعات'),
        _reply(2, 'مواعيد العمل'),
      ], locale: const Locale('ar'));

      expect(tester.takeException(), isNull);
      expect(find.text('المرتجعات'), findsNWidgets(2));
      expect(find.text('بدون تصنيف'), findsNWidgets(2));
      expect(find.text('الكل'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Save to contacts', () {
    Future<_FakeContactSaver> tapSave(
      WidgetTester tester, {
      required String phone,
      ContactSaveOutcome outcome = ContactSaveOutcome.saved,
    }) async {
      final saver = _FakeContactSaver(outcome);
      await tester.pumpWidget(
        _app(
          Center(
            child: SaveToContactsButton(name: 'Sarah Connor', phone: phone),
          ),
          overrides: [contactSaverProvider.overrideWithValue(saver)],
        ),
      );
      await tester.tap(find.byKey(const Key('saveToContactsButton')));
      await tester.pumpAndSettle();
      return saver;
    }

    testWidgets('opens the contact screen with the backend name and number', (
      tester,
    ) async {
      final saver = await tapSave(tester, phone: ' +201124868273 ');

      expect(saver.calls, [('Sarah Connor', '+201124868273')]);
      expect(find.text('Contact saved.'), findsOneWidget);
    });

    testWidgets('no number: explains, and opens nothing', (tester) async {
      final saver = await tapSave(tester, phone: '');

      expect(saver.calls, isEmpty);
      expect(
        find.text('This customer has no phone number to save.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelled in the system screen: nothing to report', (
      tester,
    ) async {
      await tapSave(
        tester,
        phone: '+201124868273',
        outcome: ContactSaveOutcome.cancelled,
      );

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('no contacts screen on the device: says so', (tester) async {
      await tapSave(
        tester,
        phone: '+201124868273',
        outcome: ContactSaveOutcome.unavailable,
      );

      expect(
        find.text("Contacts can't be opened on this device."),
        findsOneWidget,
      );
    });

    testWidgets('the real saver reports a missing platform as unavailable', (
      tester,
    ) async {
      // No plugin is registered under test, as on an unsupported platform.
      final outcome = await const NativeContactSaver().createContact(
        name: 'Sarah',
        phone: '+201124868273',
      );
      expect(outcome, ContactSaveOutcome.unavailable);
    });
  });

  // -------------------------------------------------------------------------
  group('WhatsApp bold', () {
    test('finds bold runs the way WhatsApp does', () {
      expect(whatsappBoldSpans('*Important*'), [const BoldSpan(0, 10)]);
      expect(whatsappBoldSpans('a *b* c *d e*'), [
        const BoldSpan(2, 4),
        const BoldSpan(8, 12),
      ]);
      expect(whatsappBoldSpans('*مهم جدا* شكرا'), [const BoldSpan(0, 8)]);
      expect(whatsappBoldSpans('(*note*)'), [const BoldSpan(1, 6)]);
    });

    test('leaves asterisks that are not markup alone', () {
      for (final text in [
        '2*3*4',
        '* not bold *',
        '*not closed',
        '**',
        '*across\nlines*',
        'a*b*',
        'price: 5 * 3',
      ]) {
        expect(whatsappBoldSpans(text), isEmpty, reason: text);
      }
    });

    Widget linkified(String text, {required bool bold}) => _app(
      Center(
        child: LinkifiedText(text, linkColor: Colors.blue, whatsappBold: bold),
      ),
    );

    testWidgets('drawn bold without its asterisks', (tester) async {
      await tester.pumpWidget(linkified('Hi *Sarah*, thanks', bold: true));

      expect(_runs(tester, find.byType(LinkifiedText)), [
        ('Hi ', false),
        ('Sarah', true),
        (', thanks', false),
      ]);
    });

    testWidgets('off: the text is drawn exactly as written', (tester) async {
      await tester.pumpWidget(linkified('Hi *Sarah*', bold: false));

      expect(find.text('Hi *Sarah*'), findsOneWidget);
    });

    testWidgets('a link inside bold stays a tappable link, and bold', (
      tester,
    ) async {
      await tester.pumpWidget(
        linkified('*See https://example.com/a* now', bold: true),
      );

      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(LinkifiedText),
              matching: find.byType(RichText),
            )
            .first,
      );
      TextSpan? link;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          link = span;
        }
        return true;
      });
      expect(link?.text, 'https://example.com/a');
      expect(link?.style?.fontWeight, FontWeight.w700);
      expect(link?.style?.decoration, TextDecoration.underline);
      expect(
        _runs(tester, find.byType(LinkifiedText)).map((r) => r.$1).join(),
        'See https://example.com/a now',
      );
    });

    testWidgets('asterisks inside a link are not markup', (tester) async {
      await tester.pumpWidget(
        linkified('https://example.com/*x* end', bold: true),
      );

      expect(
        _runs(tester, find.byType(LinkifiedText)).map((r) => r.$1).join(),
        'https://example.com/*x* end',
      );
    });

    Message message(String text) => Message.fromJson({
      'id': 1,
      'text': text,
      'direction': 'INBOUND',
      'sender_name': 'Sarah',
      'sent_at': '2026-09-28T10:00:00Z',
      'delivery_status': 'DELIVERED',
      'attachments': const [],
    });

    testWidgets('a WhatsApp bubble shows bold; others show asterisks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MessageBubble(
            message: message('Please send *the invoice*'),
            provider: 'WHATSAPP',
          ),
        ),
      );
      expect(
        _runs(tester, find.byType(LinkifiedText)),
        contains(('the invoice', true)),
      );

      await tester.pumpWidget(
        _app(
          MessageBubble(
            message: message('Please send *the invoice*'),
            provider: 'INSTAGRAM',
          ),
        ),
      );
      expect(find.text('Please send *the invoice*'), findsOneWidget);
    });

    testWidgets('Copy keeps the asterisks — the message text is unchanged', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        _app(
          MessageBubble(
            message: message('Please send *the invoice*'),
            provider: 'WHATSAPP',
          ),
        ),
      );
      await tester.longPress(find.byType(LinkifiedText));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, ['Please send *the invoice*']);
    });
  });
}
