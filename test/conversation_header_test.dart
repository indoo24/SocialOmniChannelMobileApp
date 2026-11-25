/// The conversation header: back and actions on the app bar row; the
/// customer (avatar, name, phone) and the conversation's channel, account,
/// team and assignee on the rows under it — all visible on a narrow phone,
/// in either direction, with nothing clipped or silently dropped.
library;

import 'dart:async';
import 'dart:convert';
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
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Server {
  _Server({
    this.name = 'Indoo Customer',
    this.phone = '+201094680929',
    this.provider = 'WHATSAPP',
    this.account = 'Scenario DM',
    this.team = const {'id': 3, 'name': 'Support', 'color': '#0F766E'},
    this.assignee = const {
      'id': 9,
      'full_name': 'Mona Agent',
      'initials': 'MA',
    },
    this.unread = 2,
  });

  String name;
  String phone;
  String provider;
  String account;
  Map<String, dynamic>? team;
  Map<String, dynamic>? assignee;
  int unread;

  final requests = <RequestOptions>[];

  Map<String, dynamic> conversation() => {
    'id': 42,
    'customer': {'id': 7, 'display_name': name, 'phone': phone},
    'provider': provider,
    'channel_name': account,
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': unread,
    'message_count': 1,
    'last_customer_message_at': DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 3))
        .toIso8601String(),
    'assigned_to': ?assignee,
    'assigned_team': ?team,
  };

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _Adapter((o) async {
      requests.add(o);
      final path = o.path;
      if (path == '/conversations/42/') return _json(conversation());
      if (path.startsWith('/conversations/42/messages/')) {
        return _json({
          'count': 1,
          'next': null,
          'results': [
            {
              'id': 500,
              'direction': 'INBOUND',
              'sender_type': 'CUSTOMER',
              'text': 'Hello there',
              'delivery_status': 'DELIVERED',
              'sent_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        });
      }
      if (path.contains('/notes/')) return _json(<Object>[]);
      return _json(<String, dynamic>{});
    });
    return client;
  }
}

Employee _agent() => Employee(
  id: 1,
  email: 'sam@acme.test',
  fullName: 'Sam Admin',
  initials: 'SA',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: const {
    Perm.conversationView,
    Perm.conversationReply,
    Perm.conversationAssignAny,
    Perm.conversationChangeCategory,
    Perm.conversationConfirmPurchase,
  },
  visibilityScope: 'ALL',
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  Locale locale = const Locale('en'),
  Size size = const Size(320, 640),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(server.client()),
        currentEmployeeProvider.overrideWithValue(_agent()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ConversationScreen)),
  );
}

Finder _k(String key) => find.byKey(ValueKey(key));
final _area = find.byKey(const Key('conversation_header_customer_area'));
final _teamPill = _k('conversationTeamPill');

String _chipText(WidgetTester tester, Finder chip) => tester
    .widget<Text>(find.descendant(of: chip, matching: find.byType(Text)))
    .data!;

/// Fully on screen: inside the window horizontally, and not clipped by it.
void _onScreen(WidgetTester tester, Finder finder, double width) {
  final r = tester.getRect(finder);
  expect(r.left, greaterThanOrEqualTo(0), reason: '$finder left');
  expect(r.right, lessThanOrEqualTo(width), reason: '$finder right');
  expect(r.width, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Narrow phone', () {
    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label at 320px: every action and every item of metadata '
          'is shown, without overflow', (tester) async {
        const width = 320.0;
        await _pump(tester, _Server(), locale: locale);
        expect(tester.takeException(), isNull);

        // Row 1: navigation and actions.
        for (final key in [
          'markAsReadButton',
          'conversation_sold_button',
          'conversation_header_assign_button',
          'conversation_header_more_button',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
          _onScreen(tester, find.byKey(ValueKey(key)), width);
        }
        expect(find.byIcon(Icons.flag_outlined), findsOneWidget);

        // Rows 2–3: identity and metadata.
        expect(find.text('Indoo Customer'), findsOneWidget);
        expect(find.text('+201094680929'), findsOneWidget);
        for (final key in [
          'conversationHeaderName',
          'conversationHeaderPhone',
          'conversationHeaderChannel',
          'conversationHeaderAccount',
          'conversationTeamPill',
          'conversationHeaderAssignee',
        ]) {
          expect(_k(key), findsOneWidget, reason: key);
          _onScreen(tester, _k(key), width);
        }
        expect(
          _chipText(tester, _k('conversationHeaderAccount')),
          'Scenario DM',
        );
        expect(_chipText(tester, _teamPill), 'Support');
        expect(
          _chipText(tester, _k('conversationHeaderAssignee')),
          'Mona Agent',
        );

        // The thread starts below the header — never under it.
        expect(
          tester.getRect(find.text('Hello there')).top,
          greaterThanOrEqualTo(tester.getRect(_area).bottom),
        );
      });
    }

    testWidgets('a long name takes two lines at most, and the rest of the '
        'header still shows', (tester) async {
      await _pump(
        tester,
        _Server(
          name:
              'Abdelrahman Mohamed Abdelaziz El-Sayed Ibrahim Mostafa '
              'Hassan Kandeel',
        ),
      );
      expect(tester.takeException(), isNull);
      final name = tester.widget<Text>(_k('conversationHeaderName'));
      expect(name.maxLines, 2);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(_k('conversationHeaderName')).height,
        lessThanOrEqualTo(2 * 1.25 * 16 + 2),
      );
      expect(_k('conversationHeaderPhone'), findsOneWidget);
      expect(_teamPill, findsOneWidget);
    });

    testWidgets('a long phone number is shown whole — shrunk to fit, never '
        'cut', (tester) async {
      const longPhone = '+201094680929 ext. 123456789012';
      await _pump(tester, _Server(phone: longPhone));
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(
        find.descendant(
          of: _k('conversationHeaderPhone'),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, longPhone);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.textDirection, TextDirection.ltr);
      expect(
        find.ancestor(
          of: find.text(longPhone),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
      _onScreen(tester, _k('conversationHeaderPhone'), 320);
    });

    testWidgets('many long chips wrap onto more lines instead of '
        'overflowing', (tester) async {
      await _pump(
        tester,
        _Server(
          account: 'Scenario Cosmetics — Official WhatsApp Business Line',
          team: const {
            'id': 3,
            'name': 'Arabic Customer Service — Riyadh Night Shift',
            'color': '#0F766E',
          },
          assignee: const {
            'id': 9,
            'full_name': 'Mona Abdelrahman El-Sayed',
            'initials': 'MA',
          },
        ),
      );
      expect(tester.takeException(), isNull);
      final channelTop = tester.getRect(_k('conversationHeaderChannel')).top;
      final lowest = [
        _k('conversationHeaderAccount'),
        _teamPill,
        _k('conversationHeaderAssignee'),
      ].map((f) => tester.getRect(f).top).reduce((a, b) => a > b ? a : b);
      expect(lowest, greaterThan(channelTop));
      for (final f in [
        _k('conversationHeaderAccount'),
        _teamPill,
        _k('conversationHeaderAssignee'),
      ]) {
        _onScreen(tester, f, 320);
      }
    });
  });

  group('Keyboard open', () {
    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label: the details fold to one line so the reply box '
          'fits, and come back when the keyboard closes', (tester) async {
        await _pump(
          tester,
          _Server(),
          locale: locale,
          size: const Size(360, 640),
        );
        expect(_k('conversationHeaderCompact'), findsNothing);
        expect(_teamPill, findsOneWidget);

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_k('conversationHeaderCompact'), findsOneWidget);
        // Name and phone stay in view…
        expect(find.text('Indoo Customer'), findsOneWidget);
        expect(find.text('+201094680929'), findsOneWidget);
        _onScreen(tester, _k('conversationHeaderPhone'), 360);
        // …the chips are folded away, but still read out, and one tap away.
        expect(_teamPill, findsNothing);
        final spoken = tester.getSemantics(_area).label;
        expect(spoken, contains('Support'));
        expect(spoken, contains('Mona Agent'));
        expect(
          find.byKey(const ValueKey('composer_reply_input')),
          findsOneWidget,
        );

        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(_k('conversationHeaderCompact'), findsNothing);
        expect(_teamPill, findsOneWidget);
        expect(_k('conversationHeaderAssignee'), findsOneWidget);
      });
    }
  });

  group('What is shown', () {
    testWidgets('without a team, an assignee, a phone or an account, only '
        'the channel chip remains — and nothing is left empty', (tester) async {
      await _pump(
        tester,
        _Server(phone: '', account: '', team: null, assignee: null),
      );
      expect(_teamPill, findsNothing);
      expect(_k('conversationHeaderAssignee'), findsNothing);
      expect(_k('conversationHeaderPhone'), findsNothing);
      expect(_k('conversationHeaderAccount'), findsNothing);
      expect(_k('conversationHeaderChannel'), findsOneWidget);
      expect(find.text('Indoo Customer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (provider, label) in [
      ('WHATSAPP', 'WhatsApp'),
      ('INSTAGRAM', 'Instagram'),
      ('FACEBOOK', 'Messenger'),
      ('TIKTOK', 'TikTok'),
    ]) {
      testWidgets('$provider shows its channel chip', (tester) async {
        await _pump(tester, _Server(provider: provider));
        expect(_chipText(tester, _k('conversationHeaderChannel')), label);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the team and the assignee are told apart, and the row '
        'reads as one labelled button', (tester) async {
      await _pump(tester, _Server());
      final label = tester.getSemantics(_area).label;
      for (final part in [
        'Indoo Customer',
        'Phone +201094680929',
        'Channel: WhatsApp',
        'Account: Scenario DM',
        'Team: Support',
        'Assigned to Mona Agent',
      ]) {
        expect(label, contains(part));
      }
      // The avatar's initials are not read out on top of the name.
      expect(label, isNot(startsWith('IC')));
      expect(
        find.descendant(
          of: _k('conversationHeaderAssignee'),
          matching: find.byIcon(Icons.person_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _teamPill,
          matching: find.byIcon(Icons.groups_2_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Arabic: right-to-left, with the phone kept left-to-right', (
      tester,
    ) async {
      await _pump(tester, _Server(), locale: const Locale('ar'));
      expect(Directionality.of(tester.element(_area)), TextDirection.rtl);
      // The avatar leads on the right; the name sits to its left.
      final avatarRight = tester
          .getRect(
            find
                .descendant(
                  of: _area,
                  matching: find.byKey(
                    const ValueKey('conversationHeaderName'),
                  ),
                )
                .first,
          )
          .right;
      expect(avatarRight, lessThan(320 - 40));
      final phone = tester.widget<Text>(find.text('+201094680929'));
      expect(phone.textDirection, TextDirection.ltr);
      expect(
        tester.getSemantics(_area).label,
        contains('الهاتف +201094680929'),
      );
    });
  });

  group('Actions and updates', () {
    testWidgets('the customer row and More actions both open the '
        'conversation details', (tester) async {
      await _pump(tester, _Server(), size: const Size(390, 844));

      await tester.tap(
        find.byKey(const Key('conversation_header_more_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      await tester.tap(_area);
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    });

    testWidgets('the assign action still opens the assignment picker', (
      tester,
    ) async {
      await _pump(tester, _Server(), size: const Size(390, 844));
      await tester.tap(
        find.byKey(const Key('conversation_header_assign_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a transfer shows the new team at once; the old one is '
        'gone', (tester) async {
      final server = _Server();
      final container = await _pump(tester, server);
      expect(_chipText(tester, _teamPill), 'Support');

      server.team = const {'id': 4, 'name': 'Sales', 'color': '#2563EB'};
      server.assignee = null;
      unawaited(
        container
            .read(conversationControllerProvider(42).notifier)
            .refreshFromServer(),
      );
      await tester.pumpAndSettle();

      expect(_chipText(tester, _teamPill), 'Sales');
      expect(find.text('Support'), findsNothing);
      expect(_k('conversationHeaderAssignee'), findsNothing);
    });

    testWidgets('a conversation with no unread messages has no mark-read '
        'action, and the rest of the row is unchanged', (tester) async {
      await _pump(tester, _Server(unread: 0));
      expect(find.byKey(const ValueKey('markAsReadButton')), findsNothing);
      expect(
        find.byKey(const Key('conversation_header_more_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('conversation_sold_button')), findsOneWidget);
    });
  });
}
