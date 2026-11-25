/// Pin / unpin in the conversation header (moved out of the conversation
/// sheet), "Transfer to team" in the sheet's top row in its place, and the
/// sheet's details table — flexible, so long values are never cut.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/widgets/key_value_row.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

const _sales = {'id': 1, 'name': 'Sales', 'color': '#2563EB'};
const _support = {'id': 2, 'name': 'Support', 'color': '#16A34A'};
const _ahmed = {'id': 11, 'full_name': 'Ahmed ElQasaby', 'initials': 'AE'};

class _Server implements HttpClientAdapter {
  _Server({this.pinned = false});

  bool pinned;
  int unread = 2;
  String name = 'Indoo';
  String email = 'yaso.kandeel11@gmail.com';
  Map<String, dynamic> team = _sales;
  Map<String, dynamic>? assignee = _ahmed;

  /// Holds pin requests until completed.
  Completer<void>? pinGate;

  /// Answers pin requests with this status instead.
  int? pinFailure;

  final requests = <RequestOptions>[];

  List<String> get pinRequests => [
    for (final r in requests)
      if (r.path == '/conversations/42/pin/') '${r.method} ${r.path}',
  ];

  Iterable<RequestOptions> get transfers => requests.where(
    (r) => r.method == 'POST' && r.path == '/conversations/42/transfer-team/',
  );

  Map<String, dynamic> conversation() => {
    'id': 42,
    'customer': {
      'id': 7,
      'display_name': name,
      'phone': '01124868273',
      'email': email,
      'city': 'طنطا',
      'country': 'مصر',
      'lifecycle_stage': 'EXISTING_CUSTOMER',
      'preferred_language': 'ar',
    },
    'provider': 'WHATSAPP',
    'channel_name': 'Scenario DM',
    'status': 'OPEN',
    'priority': 'NORMAL',
    'unread_count': unread,
    'message_count': 399,
    'is_pinned': pinned,
    'started_at': '2026-08-18T11:56:00Z',
    'last_message_at': '2026-11-25T16:12:00Z',
    'first_response_at': '2026-08-18T11:56:00Z',
    'last_agent_message_at': '2026-11-18T15:55:00Z',
    'last_customer_message_at': DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 2))
        .toIso8601String(),
    'assigned_to': ?assignee,
    'assigned_team': team,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;
    if (path == '/conversations/42/pin/') {
      if (pinGate case final gate?) await gate.future;
      if (pinFailure case final status?) {
        return _json({
          'error': {'code': 'error', 'message': ''},
        }, status);
      }
      pinned = options.method == 'POST';
      return _json({'is_pinned': pinned});
    }
    if (options.method == 'POST' &&
        path == '/conversations/42/transfer-team/') {
      final body = Map<String, dynamic>.from(options.data as Map);
      team = body['team_id'] == 2 ? _support : _sales;
      assignee = null;
      return _json(conversation());
    }
    if (path == '/teams/') {
      return _json({
        'count': 2,
        'next': null,
        'results': [
          {'id': 1, 'name': 'Sales', 'is_active': true, 'member_count': 4},
          {'id': 2, 'name': 'Support', 'is_active': true, 'member_count': 3},
        ],
      });
    }
    if (path == '/conversations/42/') return _json(conversation());
    if (path.contains('/messages/')) return _json({'results': []});
    if (path.contains('/notes/')) return _json(<Object>[]);
    if (path.contains('/orders/')) return _json({'results': []});
    if (path.contains('/facts/')) return _json(<Object>[]);
    if (path.contains('/fields/')) return _json(<Object>[]);
    if (path.contains('/categories/')) return _json(<Object>[]);
    if (path.contains('/conversations/')) return _json({'results': []});
    return _json(<String, dynamic>{});
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

Employee _employee({bool canTransfer = true}) => Employee(
  id: 1,
  email: 'boss@acme.test',
  fullName: 'Sara Supervisor',
  initials: 'SS',
  role: 'ADMIN',
  roleDisplay: 'Admin',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationView,
    Perm.conversationReply,
    Perm.conversationChangeStatus,
    Perm.conversationChangeCategory,
    Perm.conversationConfirmPurchase,
    if (canTransfer) Perm.conversationAssignAny,
    Perm.teamView,
  },
  visibilityScope: 'ALL',
  teamTransferEnabled: canTransfer,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  Employee? me,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(me ?? _employee()),
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

final _pin = find.byKey(const Key('conversation_header_pin_button'));
final _transfer = find.byKey(
  const Key('conversation_actions_sheet_transfer_button'),
);
final _review = find.byKey(
  const Key('conversation_actions_sheet_review_button'),
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation_header_customer_area')));
  await tester.pumpAndSettle();
}

bool _pinFilled(WidgetTester tester) => find
    .descendant(of: _pin, matching: find.byIcon(Icons.push_pin))
    .evaluate()
    .isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Header pin', () {
    testWidgets('an unpinned conversation: an outlined pin, "Pin '
        'conversation"', (tester) async {
      await _pump(tester, _Server());
      expect(_pin, findsOneWidget);
      expect(_pinFilled(tester), isFalse);
      expect(
        find.descendant(
          of: _pin,
          matching: find.byIcon(Icons.push_pin_outlined),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Pin conversation'), findsOneWidget);
      expect(tester.widget<IconButton>(_pin).isSelected, isFalse);
    });

    testWidgets('a pinned conversation: a filled, tinted pin, "Unpin '
        'conversation"', (tester) async {
      await _pump(tester, _Server(pinned: true));
      expect(_pinFilled(tester), isTrue);
      expect(find.byTooltip('Unpin conversation'), findsOneWidget);
      expect(tester.widget<IconButton>(_pin).isSelected, isTrue);
      expect(
        tester.getSemantics(_pin).flagsCollection.isToggled,
        Tristate.isTrue,
      );
    });

    testWidgets('toggling waits for the server, takes one tap at a time, '
        'and shows what it confirmed', (tester) async {
      final server = _Server()..pinGate = Completer<void>();
      await _pump(tester, server);

      await tester.tap(_pin);
      await tester.pump();
      expect(
        find.byKey(const Key('conversation_header_pin_busy')),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(_pin).onPressed, isNull);
      await tester.tap(_pin, warnIfMissed: false);
      await tester.tap(_pin, warnIfMissed: false);
      await tester.pump();

      server.pinGate!.complete();
      server.pinGate = null;
      await tester.pumpAndSettle();
      expect(server.pinRequests, ['POST /conversations/42/pin/']);
      expect(_pinFilled(tester), isTrue);
      expect(find.text('Conversation pinned'), findsOneWidget);

      await tester.tap(_pin);
      await tester.pumpAndSettle();
      expect(server.pinRequests.last, 'DELETE /conversations/42/pin/');
      expect(_pinFilled(tester), isFalse);
    });

    testWidgets('a failure says so, offers to try again, and leaves the pin '
        'as it was', (tester) async {
      final server = _Server()..pinFailure = 500;
      await _pump(tester, server);
      await tester.tap(_pin);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't update the pin. Please try again."), findsOne);
      expect(find.text('Try again'), findsOneWidget);
      expect(_pinFilled(tester), isFalse);
      expect(tester.widget<IconButton>(_pin).onPressed, isNotNull);
    });

    testWidgets('without permission, the server\'s refusal is explained', (
      tester,
    ) async {
      final server = _Server()..pinFailure = 403;
      await _pump(tester, server);
      await tester.tap(_pin);
      await tester.pumpAndSettle();
      expect(
        find.text("You don't have permission to pin conversations."),
        findsOneWidget,
      );
      expect(_pinFilled(tester), isFalse);
    });

    testWidgets('a refresh shows the pin the server holds', (tester) async {
      final server = _Server();
      final container = await _pump(tester, server);
      expect(_pinFilled(tester), isFalse);

      // Pinned elsewhere (the inbox, another device).
      server.pinned = true;
      unawaited(
        container
            .read(conversationControllerProvider(42).notifier)
            .refreshFromServer(),
      );
      await tester.pumpAndSettle();
      expect(_pinFilled(tester), isTrue);
    });

    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label at 320px: the pin fits beside every other action, '
          'none overlapping', (tester) async {
        await _pump(
          tester,
          _Server(),
          locale: locale,
          size: const Size(320, 640),
        );
        expect(tester.takeException(), isNull);
        final keys = [
          'markAsReadButton',
          'conversation_sold_button',
          'conversation_header_pin_button',
          'conversation_header_assign_button',
          'conversation_header_more_button',
        ];
        final rects = [
          for (final k in keys) tester.getRect(find.byKey(ValueKey(k))),
          tester.getRect(
            find.ancestor(
              of: find.byIcon(Icons.flag_outlined),
              matching: find.byType(IconButton),
            ),
          ),
        ];
        for (final r in rects) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(320));
        }
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].intersect(rects[j]).width,
              lessThanOrEqualTo(0.5),
              reason: 'action $i overlaps action $j',
            );
          }
        }
        // And the identity rows below are all still there.
        expect(
          find.byKey(const ValueKey('conversationTeamPill')),
          findsOneWidget,
        );
      });
    }
  });

  group('Sheet: Transfer to team in Pin\'s place', () {
    testWidgets('the top row is Transfer to team and Review; no pin', (
      tester,
    ) async {
      await _pump(tester, _Server());
      await _openSheet(tester);
      expect(
        find.byKey(const Key('conversation_actions_sheet_pin_button')),
        findsNothing,
      );
      expect(_transfer, findsOneWidget);
      expect(
        find.descendant(of: _transfer, matching: find.text('Transfer to team')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _transfer,
          matching: find.byIcon(Icons.groups_2_outlined),
        ),
        findsOneWidget,
      );
      // Side by side, the same size.
      final t = tester.getRect(_transfer);
      final r = tester.getRect(_review);
      expect(t.center.dy, closeTo(r.center.dy, 1));
      expect(t.width, closeTo(r.width, 1));
    });

    testWidgets('it opens the existing transfer sheet, and a transfer shows '
        'the new team in the header', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _openSheet(tester);

      await tester.tap(_transfer);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transferTeamSheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('transferTeamField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transferTeamSubmit')));
      await tester.pumpAndSettle();

      expect(server.transfers, hasLength(1));
      expect((server.transfers.single.data as Map)['team_id'], 2);
      final pill = find.byKey(const ValueKey('conversationTeamPill'));
      expect(
        find.descendant(of: pill, matching: find.text('Support')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pill, matching: find.text('Sales')),
        findsNothing,
      );
    });

    testWidgets('without the right to transfer it is not offered, and Review '
        'takes the row', (tester) async {
      await _pump(tester, _Server(), me: _employee(canTransfer: false));
      await _openSheet(tester);
      expect(_transfer, findsNothing);
      expect(_review, findsOneWidget);
      final resolve = find.byKey(
        const Key('conversation_actions_sheet_resolve_button'),
      );
      expect(
        tester.getRect(_review).width,
        closeTo(tester.getRect(resolve).width, 1),
      );
    });

    testWidgets('Arabic: "تحويل إلى فريق", whole, beside "طلب مراجعة"', (
      tester,
    ) async {
      await _pump(tester, _Server(), locale: const Locale('ar'));
      await _openSheet(tester);
      final label = tester.widget<Text>(
        find.descendant(of: _transfer, matching: find.text('تحويل إلى فريق')),
      );
      expect(label.maxLines, 2);
      expect(tester.takeException(), isNull);
      // In right-to-left the first of the pair is on the right.
      expect(
        tester.getRect(_transfer).center.dx,
        greaterThan(tester.getRect(_review).center.dx),
      );
    });
  });

  group('Sheet details', () {
    for (final (label, locale) in [
      ('English', const Locale('en')),
      ('Arabic', const Locale('ar')),
    ]) {
      testWidgets('$label, 320px, large text: long values wrap instead of '
          'being cut, and the sheet scrolls to the end', (tester) async {
        final server = _Server()
          ..name = 'Abdelrahman Mohamed Abdelaziz El-Sayed Ibrahim Kandeel'
          ..email =
              'abdelrahman.mohamed.abdelaziz.elsayed.kandeel@example-mail.com'
          ..team = const {
            'id': 1,
            'name': 'Arabic Customer Service — Riyadh Night Shift',
            'color': '#2563EB',
          }
          ..assignee = const {
            'id': 11,
            'full_name': 'Ahmed Mohamed ElQasaby Abdelrahman',
            'initials': 'AE',
          };
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, server, locale: locale, size: const Size(320, 640));
        await _openSheet(tester);
        expect(tester.takeException(), isNull);

        final email = find.text(server.email);
        await tester.scrollUntilVisible(
          email,
          150,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        final emailText = tester.widget<Text>(email);
        expect(emailText.maxLines, isNull);
        expect(emailText.overflow, isNot(TextOverflow.ellipsis));
        expect(emailText.textDirection, TextDirection.ltr);
        // Wrapped onto more than one line rather than cut at the edge.
        expect(tester.getRect(email).height, greaterThan(20));
        expect(tester.getRect(email).right, lessThanOrEqualTo(320));

        for (final value in [
          'Arabic Customer Service — Riyadh Night Shift',
          'Ahmed Mohamed ElQasaby Abdelrahman',
        ]) {
          final f = find.descendant(
            of: find.byType(KeyValueRow),
            matching: find.text(value),
          );
          expect(f, findsOneWidget, reason: value);
          expect(tester.widget<Text>(f).maxLines, isNull);
        }

        // The label never overlaps its value.
        for (final row in tester.widgetList<KeyValueRow>(
          find.byType(KeyValueRow),
        )) {
          final rowFinder = find.byWidget(row);
          final l = tester.getRect(
            find.descendant(
              of: rowFinder,
              matching: find.byKey(const ValueKey('keyValueRowLabel')),
            ),
          );
          final v = tester.getRect(
            find.descendant(
              of: rowFinder,
              matching: find.byKey(const ValueKey('keyValueRowValue')),
            ),
          );
          expect(
            l.intersect(v).width <= 0 || l.intersect(v).height <= 0,
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the phone is shown whole, shrunk to fit if it must', (
      tester,
    ) async {
      await _pump(tester, _Server(), size: const Size(320, 640));
      await _openSheet(tester);
      final phone = find.byKey(const Key('contactPhoneText'));
      final text = tester.widget<Text>(phone);
      expect(text.data, '01124868273');
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(
        find.ancestor(of: phone, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });
  });

  group('KeyValueRow', () {
    Future<void> row(WidgetTester tester, double width) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const KeyValueRow(
                label: 'Last message from the employee',
                value: 'someone.with.a.long.address@example.com',
                ltr: true,
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('side by side, the label taking a share of the row', (
      tester,
    ) async {
      await row(tester, 360);
      final l = tester.getRect(find.byKey(const ValueKey('keyValueRowLabel')));
      final v = tester.getRect(find.byKey(const ValueKey('keyValueRowValue')));
      expect(l.width, closeTo(360 * KeyValueRow.labelShare, 1));
      expect(v.left, greaterThan(l.right));
      expect(l.top, v.top);
    });

    testWidgets('stacked on a very narrow row', (tester) async {
      await row(tester, 220);
      final l = tester.getRect(find.byKey(const ValueKey('keyValueRowLabel')));
      final v = tester.getRect(find.byKey(const ValueKey('keyValueRowValue')));
      expect(v.top, greaterThanOrEqualTo(l.bottom));
      expect(tester.takeException(), isNull);
    });
  });
}
