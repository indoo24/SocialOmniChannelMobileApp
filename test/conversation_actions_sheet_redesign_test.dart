/// The conversation actions sheet's Resolve button and its redesigned
/// Status / Priority / Category choices.
///
/// Resolve sits full width under Pin and Review and changes the status to
/// RESOLVED through the same `POST /conversations/{id}/status/` the Resolved
/// chip uses — never confirm-purchase. The chips keep their values and
/// endpoints; only their look changed: coloured by meaning, filled with a
/// check when selected.
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
import 'package:scenario_mobile/core/theme/app_palette.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_actions_sheet.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// The backend behind the sheet. [status] / [priority] are the
/// conversation's; [onWrite] may answer a status/priority/category POST
/// instead of the default 200.
class _Server implements HttpClientAdapter {
  _Server({this.status = 'OPEN'});

  String status;
  String priority = 'NORMAL';
  FutureOr<ResponseBody>? Function(RequestOptions options)? onWrite;

  final List<RequestOptions> requests = [];

  /// What the sheet changed — not the conversation marking itself read as
  /// it loads (`POST …/read/`).
  Iterable<RequestOptions> get writes =>
      requests.where((r) => r.method == 'POST' && !r.path.endsWith('/read/'));

  Iterable<RequestOptions> writesTo(String suffix) =>
      writes.where((r) => r.path.endsWith(suffix));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(options);
    final path = options.path;
    if (options.method == 'POST') {
      final answer = onWrite?.call(options);
      if (answer != null) return answer;
      final body = options.data as Map?;
      if (path.endsWith('/status/')) status = body?['status'] as String;
      if (path.endsWith('/priority/')) priority = body?['priority'] as String;
      return _json({});
    }
    if (path.endsWith('/conversations/1/')) {
      return _json({
        'id': 1,
        'customer': {'id': 1, 'display_name': 'Sarah Connor', 'initials': 'SC'},
        'provider': 'WHATSAPP',
        'status': status,
        'priority': priority,
        'unread_count': 0,
        'message_count': 5,
      });
    }
    if (path.endsWith('/categories/')) {
      return _json([
        {'id': 3, 'label': 'Billing', 'slug': 'billing', 'color': ''},
        {'id': 4, 'label': 'Delivery', 'slug': 'delivery', 'color': ''},
      ]);
    }
    if (path.contains('/intelligence/')) return _json(null);
    if (path.contains('/orders')) {
      return _json({'count': 0, 'next': null, 'previous': null, 'results': []});
    }
    if (path.contains('/messages/')) return _json({'results': [], 'count': 0});
    if (path.contains('/facts') ||
        path.contains('/conversions') ||
        path.contains('/events') ||
        path.contains('/notes')) {
      return _json([]);
    }
    return _json({});
  }

  @override
  void close({bool force = false}) {}
}

Employee _employee({bool canChangeStatus = true}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationChangePriority,
    Perm.conversationChangeCategory,
    Perm.conversationAssignAny,
    if (canChangeStatus) Perm.conversationChangeStatus,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
  teamTransferEnabled: true,
);

Future<void> _openSheet(
  WidgetTester tester,
  _Server server, {
  Employee? employee,
  Locale locale = const Locale('en'),
  Size size = const Size(430, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
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
    ),
  );
  await tester.tap(find.text('open actions'));
  await tester.pumpAndSettle();
}

Finder get _resolve =>
    find.byKey(const Key('conversation_actions_sheet_resolve_button'));

/// "Transfer to team" — in the place Pin had before it moved to the header.
Finder get _transfer =>
    find.byKey(const Key('conversation_actions_sheet_transfer_button'));
Finder get _review =>
    find.byKey(const Key('conversation_actions_sheet_review_button'));

Finder _chip(String key) => find.byKey(Key(key));

/// Scrolls the sheet until [finder] is on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

/// The chip's own state, as reported to assistive technology.
bool _selected(WidgetTester tester, String key) =>
    tester
        .widget<Semantics>(
          find
              .descendant(of: _chip(key), matching: find.byType(Semantics))
              .first,
        )
        .properties
        .selected ??
    false;

Color? _fill(WidgetTester tester, String key) => tester
    .widget<Material>(
      find.descendant(of: _chip(key), matching: find.byType(Material)).first,
    )
    .color;

void main() {
  group('Resolve', () {
    testWidgets('a full-width green button directly below Transfer and '
        'Review', (tester) async {
      await _openSheet(tester, _Server());

      expect(_transfer, findsOneWidget);
      expect(_review, findsOneWidget);
      expect(_resolve, findsOneWidget);
      // Pin is no longer in the sheet.
      expect(
        find.byKey(const Key('conversation_actions_sheet_pin_button')),
        findsNothing,
      );
      expect(find.text('Resolve'), findsOneWidget);
      expect(
        find.descendant(
          of: _resolve,
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );

      final pin = tester.getRect(_transfer);
      final review = tester.getRect(_review);
      final resolve = tester.getRect(_resolve);
      expect(resolve.top, greaterThanOrEqualTo(pin.bottom));
      expect(resolve.top - pin.bottom, lessThan(16));
      // Spans what Transfer and Review span together.
      expect(resolve.left, closeTo(pin.left, 1));
      expect(resolve.right, closeTo(review.right, 1));

      // Green, white label, readable.
      final button = tester.widget<FilledButton>(_resolve);
      final background = button.style!.backgroundColor!.resolve({});
      final success = AppColors.of(tester.element(_resolve)).success;
      expect(
        HSLColor.fromColor(background!).hue,
        closeTo(HSLColor.fromColor(success).hue, 2),
      );
      expect(button.style!.foregroundColor!.resolve({}), Colors.white);
      final contrast = 1.05 / (background.computeLuminance() + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });

    testWidgets('resolves through the status endpoint — RESOLVED, nothing '
        'else — closes the sheet and offers Undo', (tester) async {
      final server = _Server();
      await _openSheet(tester, server);

      await tester.tap(_resolve);
      await tester.pumpAndSettle();

      expect(server.writes, hasLength(1));
      final request = server.writes.single;
      expect(request.path, '/conversations/1/status/');
      expect(request.data, {'status': 'RESOLVED'});
      expect(
        server.requests.where((r) => r.path.contains('confirm-purchase')),
        isEmpty,
      );
      // The sheet closed; the resolve feedback, with Undo.
      expect(_resolve, findsNothing);
      expect(find.text('Conversation resolved'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(server.writesTo('/status/').last.data, {'status': 'OPEN'});
      expect(find.text('Conversation reopened'), findsOneWidget);
    });

    testWidgets('a refusal says why and leaves the sheet open, ready to try '
        'again', (tester) async {
      final server = _Server()
        ..onWrite = (_) => _json({
          'error': {'code': 'invalid', 'message': 'Cannot resolve now.'},
        }, 400);
      await _openSheet(tester, server);

      await tester.tap(_resolve);
      await tester.pumpAndSettle();
      expect(find.text('Cannot resolve now.'), findsOneWidget);
      expect(_resolve, findsOneWidget);
      expect(tester.widget<FilledButton>(_resolve).onPressed, isNotNull);
    });

    testWidgets('already resolved: says so and cannot be sent again', (
      tester,
    ) async {
      final server = _Server(status: 'RESOLVED');
      await _openSheet(tester, server);

      expect(
        find.descendant(of: _resolve, matching: find.text('Resolved')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _resolve,
          matching: find.byIcon(Icons.done_all_rounded),
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_resolve).onPressed, isNull);
      await tester.tap(_resolve, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
    });

    testWidgets('without conversation.change_status: no Resolve, no status '
        'choices', (tester) async {
      await _openSheet(
        tester,
        _Server(),
        employee: _employee(canChangeStatus: false),
      );
      expect(_transfer, findsOneWidget);
      expect(_resolve, findsNothing);
      await _reveal(tester, _chip('priority_chip_URGENT'));
      expect(_chip('status_chip_OPEN'), findsNothing);
    });

    testWidgets('reads "تم الحل" in Arabic', (tester) async {
      await _openSheet(tester, _Server(), locale: const Locale('ar'));
      expect(
        find.descendant(of: _resolve, matching: find.text('تم الحل')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Status', () {
    testWidgets('every status is offered; the current one is filled with a '
        'check; tapping another sends it', (tester) async {
      final server = _Server();
      await _openSheet(tester, server);
      await _reveal(tester, _chip('status_chip_CLOSED'));

      for (final s in [
        'OPEN',
        'WAITING_CUSTOMER',
        'WAITING_INTERNAL',
        'RESOLVED',
        'CLOSED',
      ]) {
        expect(_chip('status_chip_$s'), findsOneWidget);
      }
      expect(_selected(tester, 'status_chip_OPEN'), isTrue);
      expect(_selected(tester, 'status_chip_CLOSED'), isFalse);
      expect(
        find.descendant(
          of: _chip('status_chip_OPEN'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _chip('status_chip_WAITING_CUSTOMER'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );

      // Colour by meaning: open green (filled), waiting on the customer blue,
      // waiting internally amber — the theme's own status colours.
      final colors = AppColors.of(tester.element(_chip('status_chip_OPEN')));
      expect(
        HSLColor.fromColor(_fill(tester, 'status_chip_OPEN')!).hue,
        closeTo(HSLColor.fromColor(colors.success).hue, 2),
      );
      expect(_fill(tester, 'status_chip_WAITING_CUSTOMER'), colors.infoSurface);
      expect(
        _fill(tester, 'status_chip_WAITING_INTERNAL'),
        colors.warningSurface,
      );

      // The selected one is already the value: nothing is sent.
      await tester.tap(_chip('status_chip_OPEN'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);

      await tester.tap(_chip('status_chip_WAITING_CUSTOMER'));
      await tester.pumpAndSettle();
      expect(server.writes.single.path, '/conversations/1/status/');
      expect(server.writes.single.data, {'status': 'WAITING_CUSTOMER'});
      expect(find.text('Status updated'), findsOneWidget);
    });
  });

  group('Priority', () {
    testWidgets('every priority is offered, coloured by urgency; the current '
        'one is filled; tapping another sends it', (tester) async {
      final server = _Server();
      await _openSheet(tester, server);
      await _reveal(tester, _chip('priority_chip_LOW'));

      for (final p in ['URGENT', 'HIGH', 'NORMAL', 'LOW']) {
        expect(_chip('priority_chip_$p'), findsOneWidget);
      }
      expect(_selected(tester, 'priority_chip_NORMAL'), isTrue);
      expect(
        find.descendant(
          of: _chip('priority_chip_NORMAL'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      final colors = AppColors.of(
        tester.element(_chip('priority_chip_URGENT')),
      );
      expect(_fill(tester, 'priority_chip_URGENT'), colors.dangerSurface);
      expect(_fill(tester, 'priority_chip_HIGH'), colors.warningSurface);

      await tester.tap(_chip('priority_chip_URGENT'));
      await tester.pumpAndSettle();
      expect(server.writes.single.path, '/conversations/1/priority/');
      expect(server.writes.single.data, {'priority': 'URGENT'});
      expect(find.text('Priority updated'), findsOneWidget);
    });
  });

  group('Category', () {
    testWidgets('same pills; None selected; choosing one sends its id', (
      tester,
    ) async {
      final server = _Server();
      await _openSheet(tester, server);
      await _reveal(tester, _chip('category_chip_4'));

      expect(_selected(tester, 'category_chip_none'), isTrue);
      expect(_selected(tester, 'category_chip_3'), isFalse);
      await tester.tap(_chip('category_chip_3'));
      await tester.pumpAndSettle();
      expect(server.writes.single.path, '/conversations/1/category/');
      expect(server.writes.single.data, {'category_id': 3});
    });
  });

  group('layout', () {
    for (final locale in [const Locale('en'), const Locale('ar')]) {
      testWidgets('a small phone: everything wraps, nothing overflows — '
          '${locale.languageCode}', (tester) async {
        await _openSheet(
          tester,
          _Server(),
          locale: locale,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
        await _reveal(tester, _chip('category_chip_4'));
        expect(tester.takeException(), isNull);
        // Five statuses do not fit one 320-wide row: they wrap.
        final first = tester.getRect(_chip('status_chip_OPEN'));
        final last = tester.getRect(_chip('status_chip_CLOSED'));
        expect(last.top, greaterThan(first.top));
      });
    }

    testWidgets('right to left in Arabic: the first status sits on the right', (
      tester,
    ) async {
      await _openSheet(tester, _Server(), locale: const Locale('ar'));
      await _reveal(tester, _chip('status_chip_WAITING_CUSTOMER'));
      final open = tester.getRect(_chip('status_chip_OPEN'));
      final next = tester.getRect(_chip('status_chip_WAITING_CUSTOMER'));
      expect(open.center.dy, closeTo(next.center.dy, 1));
      expect(open.left, greaterThan(next.left));
    });
  });
}
