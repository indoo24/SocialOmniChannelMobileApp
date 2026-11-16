/// The header's "تم البيع" button: same look as the Resolved button it
/// replaces; one tap confirms the purchase —
/// `POST /conversations/{id}/confirm-purchase/` with
/// `{confirmed: true, note: ""}` — with no question first, a spinner while it
/// is in flight, and Customer Information showing the confirmed banner from
/// the server's answer. It never changes the conversation's status.
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
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/conversation_sold_button.dart';
import 'package:scenario_mobile/features/messages/intelligence_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

typedef Json = Map<String, dynamic>;

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _error(int status, String code, String message) => _json({
  'error': {'code': code, 'message': message},
}, status);

/// The intelligence for a conversation whose customer says they paid, not
/// yet ruled on.
Json _pendingClaim() => {
  'stage': 'PURCHASE_INTENT',
  'confidence': 0.82,
  'purchase_status': 'CUSTOMER_SAYS_PAID',
  'purchase_evidence': 'I transferred the money this morning',
  'is_purchase_claim_pending': true,
  'is_agent_confirmed': false,
  'needs_human_review': true,
};

/// No AI claim, no intent, no signals, zero confidence.
Json _noClaim() => {
  'stage': 'NEW_LEAD',
  'confidence': 0,
  'purchase_status': 'NONE',
  'purchase_intent': 'none',
  'purchase_evidence': '',
  'buying_signals': <String>[],
  'is_purchase_claim_pending': false,
  'is_agent_confirmed': false,
};

/// What `confirm-purchase` answers on success.
Json _confirmedAnswer() => {
  'stage': 'PURCHASED',
  'confidence': 0.82,
  'purchase_status': 'AGENT_CONFIRMED',
  'is_purchase_claim_pending': false,
  'is_agent_confirmed': true,
  'confirmed_by_name': 'Sam Agent',
  'purchase_confirmed_at': '2026-11-16T10:00:00Z',
  'purchase_confirmation_note': '',
  'needs_human_review': false,
};

/// A conversation-screen backend. [intelligence] is what
/// `GET …/intelligence/` returns (JSON null: not analyzed yet);
/// [onConfirm] answers `POST …/confirm-purchase/`, by default with
/// [_confirmedAnswer] — after which the intelligence read says the same.
/// [holdReads], when set, holds every intelligence read made after a
/// confirmation until it completes.
class _Server implements HttpClientAdapter {
  _Server({Object? intelligence})
    : intelligence = intelligence ?? _pendingClaim();

  Object? intelligence;
  FutureOr<ResponseBody> Function(RequestOptions options)? onConfirm;
  Completer<void>? holdReads;

  final List<RequestOptions> requests = [];

  Iterable<RequestOptions> get confirms =>
      requests.where((r) => r.path.endsWith('/confirm-purchase/'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(options);
    final path = options.path;
    if (path.endsWith('/conversations/42/confirm-purchase/')) {
      final answer = onConfirm;
      if (answer != null) return answer(options);
      intelligence = _confirmedAnswer();
      return _json(intelligence);
    }
    if (path.endsWith('/conversations/42/intelligence/')) {
      final hold = holdReads;
      if (hold != null && confirms.isNotEmpty) await hold.future;
      return _json(intelligence);
    }
    if (path.endsWith('/conversations/42/purchase-confirmations/')) {
      return _json([]);
    }
    if (path.endsWith('/conversations/42/messages/')) {
      return _json({'results': []});
    }
    if (path.endsWith('/conversations/42/')) {
      return _json({
        'id': 42,
        'customer': {'id': 7, 'display_name': 'Sarah Connor', 'initials': 'SC'},
        'assigned_to': {'id': 1, 'full_name': 'Sam Agent', 'initials': 'SA'},
        'provider': 'WHATSAPP',
        'status': 'OPEN',
        'is_follow_up': false,
      });
    }
    if (path.contains('/orders/') || path.contains('/conversions/')) {
      return _json({'results': []});
    }
    if (path.contains('/categories/') ||
        path.contains('/facts/') ||
        path.contains('/notes/') ||
        path.contains('/events/')) {
      return _json([]);
    }
    return _json({});
  }

  @override
  void close({bool force = false}) {}
}

Employee _employee({bool canConfirm = true}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {
    Perm.conversationReply,
    Perm.conversationChangeStatus,
    if (canConfirm) Perm.conversationConfirmPurchase,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  Employee? employee,
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1400);
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
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _button => find.byKey(const Key('conversation_sold_button'));

Finder _icon(IconData icon) => find.descendant(
  of: find.byType(ConversationSoldButton),
  matching: find.byIcon(icon),
);

Finder get _spinner => find.byKey(const Key('conversation_sold_busy'));

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(_button);
  await tester.pumpAndSettle();
}

/// Lets responses land without waiting for anything held.
Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConversationScreen)));

void main() {
  group('looks as the header button always has', () {
    testWidgets('a mint 38×38 square with a green ✓ in the app bar, '
        'tooltip "Sold"', (tester) async {
      await _pump(tester, _Server());

      final inHeader = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(ConversationSoldButton),
      );
      expect(inHeader, findsOneWidget);
      expect(_icon(Icons.check_rounded), findsOneWidget);
      expect(_spinner, findsNothing);
      expect(tester.getSize(_button), const Size(38, 38));
      final body = tester.widget<Material>(
        find.ancestor(of: _button, matching: find.byType(Material)).first,
      );
      expect(body.color, const Color(0xFFD1FAE5));
      expect(body.borderRadius, BorderRadius.circular(10));
      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: inHeader, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, 'Sold');
    });

    testWidgets('reads "تم البيع" in Arabic', (tester) async {
      await _pump(tester, _Server(), locale: const Locale('ar'));
      final tooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byType(ConversationSoldButton),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'تم البيع');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an already confirmed purchase shows the dark ✓✓', (
      tester,
    ) async {
      await _pump(tester, _Server(intelligence: _confirmedAnswer()));
      expect(_icon(Icons.done_all_rounded), findsOneWidget);
    });
  });

  group('one tap confirms', () {
    testWidgets('sends confirm-purchase for this conversation with '
        'confirmed: true and an empty note — no question first — and never '
        'touches its status', (tester) async {
      final server = _Server();
      await _pump(tester, server);

      await _tap(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(server.confirms, hasLength(1));
      final request = server.confirms.single;
      expect(request.method, 'POST');
      expect(request.path, '/conversations/42/confirm-purchase/');
      expect(request.data, {'confirmed': true, 'note': ''});
      // No status change, no order, nothing else written.
      expect(
        server.requests.where(
          (r) =>
              r.path.contains('/status/') ||
              r.method == 'PATCH' ||
              r.method == 'POST' &&
                  !r.path.endsWith('/confirm-purchase/') &&
                  // Opening a conversation marks it read.
                  !r.path.endsWith('/read/'),
        ),
        isEmpty,
      );

      expect(_icon(Icons.done_all_rounded), findsOneWidget);
      expect(find.text('Purchase confirmed'), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.descendant(
          of: find.byType(ConversationSoldButton),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Purchase confirmed');
    });

    testWidgets('while in flight: a spinner, disabled, nothing shown as '
        'confirmed, and further taps send nothing more', (tester) async {
      final gate = Completer<void>();
      final server = _Server();
      server.onConfirm = (options) async {
        await gate.future;
        server.intelligence = _confirmedAnswer();
        return _json(server.intelligence);
      };
      await _pump(tester, server);

      await tester.tap(_button);
      await _frames(tester, 3);
      expect(server.confirms, hasLength(1));
      expect(_spinner, findsOneWidget);
      expect(_icon(Icons.check_rounded), findsNothing);
      expect(_icon(Icons.done_all_rounded), findsNothing);
      expect(tester.widget<InkWell>(_button).onTap, isNull);

      await tester.tap(_button, warnIfMissed: false);
      await tester.pump();
      await tester.tap(_button, warnIfMissed: false);
      await tester.pump();
      expect(server.confirms, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
      expect(server.confirms, hasLength(1));
      expect(_spinner, findsNothing);
      expect(_icon(Icons.done_all_rounded), findsOneWidget);
      expect(tester.widget<InkWell>(_button).onTap, isNotNull);
    });

    testWidgets('Customer Information shows the confirmed banner straight '
        'from the answer — before any fresh read comes back', (tester) async {
      final server = _Server()..holdReads = Completer<void>();
      await _pump(tester, server);

      await tester.tap(_button);
      await _frames(tester);
      expect(server.confirms, hasLength(1));
      // The intelligence everyone reads is the server's answer already.
      final intel = _container(
        tester,
      ).read(conversationIntelligenceProvider(42)).value;
      expect(intel?.isAgentConfirmed, isTrue);
      expect(intel?.purchaseStatus, 'AGENT_CONFIRMED');
      expect(intel?.confirmedByName, 'Sam Agent');

      // Customer Information, opened while the fresh read is still held.
      await tester.tap(
        find.byKey(const Key('conversation_header_customer_area')),
      );
      await _frames(tester, 30);
      expect(
        find.byKey(
          const ValueKey('purchaseConfirmedCard'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      // And the purchase card's own prompt is gone with the claim.
      expect(
        find.byKey(const ValueKey('purchaseAlert'), skipOffstage: false),
        findsNothing,
      );

      server.holdReads!.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('purchaseConfirmedCard'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });

    testWidgets('an answer missing optional fields still works', (
      tester,
    ) async {
      final server = _Server()
        ..onConfirm = (_) => _json({'is_agent_confirmed': true});
      await _pump(tester, server);
      await _tap(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Purchase confirmed'), findsOneWidget);
    });
  });

  group('a manual sale, with no AI claim', () {
    testWidgets('no claim, no intent, no signals, zero confidence: one tap '
        'still sends', (tester) async {
      final server = _Server(intelligence: _noClaim());
      await _pump(tester, server);
      await _tap(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(server.confirms.single.data, {'confirmed': true, 'note': ''});
      expect(_icon(Icons.done_all_rounded), findsOneWidget);
    });

    testWidgets('not analyzed yet (intelligence null): the same', (
      tester,
    ) async {
      final server = _Server()..intelligence = null;
      await _pump(tester, server);
      await _tap(tester);
      expect(server.confirms, hasLength(1));
      expect(_icon(Icons.done_all_rounded), findsOneWidget);
    });

    testWidgets('while the server still requires a claim, its 400 is shown '
        'as it says it and nothing shows as sold', (tester) async {
      final server = _Server(intelligence: _noClaim())
        ..onConfirm = (_) =>
            _error(400, 'invalid', 'There is no purchase claim to rule on.');
      await _pump(tester, server);
      await _tap(tester);
      expect(server.confirms, hasLength(1));
      expect(
        find.text('There is no purchase claim to rule on.'),
        findsOneWidget,
      );
      expect(_icon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('nothing is sent', () {
    testWidgets('already confirmed: says by whom', (tester) async {
      final server = _Server(intelligence: _confirmedAnswer());
      await _pump(tester, server);
      await _tap(tester);
      expect(find.text('Confirmed by Sam Agent.'), findsOneWidget);
      expect(server.confirms, isEmpty);
    });

    testWidgets('without conversation.confirm_purchase: says so', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, employee: _employee(canConfirm: false));
      await _tap(tester);
      expect(
        find.text("You don't have permission to confirm purchases."),
        findsOneWidget,
      );
      expect(server.confirms, isEmpty);
    });
  });

  group('refusals', () {
    Future<_Server> confirmAnswering(
      WidgetTester tester,
      ResponseBody Function() answer,
    ) async {
      final server = _Server()..onConfirm = (_) => answer();
      await _pump(tester, server);
      await _tap(tester);
      return server;
    }

    testWidgets('400: the server\'s own explanation, still unconfirmed', (
      tester,
    ) async {
      await confirmAnswering(
        tester,
        () => _error(400, 'invalid', 'Ensure this field has no more than 255.'),
      );
      expect(
        find.text('Ensure this field has no more than 255.'),
        findsOneWidget,
      );
      expect(_icon(Icons.check_rounded), findsOneWidget);
      expect(_spinner, findsNothing);
    });

    testWidgets('403: a permission message', (tester) async {
      await confirmAnswering(
        tester,
        () => _error(403, 'permission_denied', 'Not allowed.'),
      );
      expect(
        find.text("You don't have permission to confirm purchases."),
        findsOneWidget,
      );
      expect(_icon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('404: the conversation is no longer available', (tester) async {
      await confirmAnswering(
        tester,
        () => _error(404, 'not_found', 'Not found.'),
      );
      expect(
        find.text('This conversation is no longer available to you.'),
        findsWidgets,
      );
    });

    testWidgets('401: left to the app\'s sign-in handling — no error of '
        'its own, nothing confirmed', (tester) async {
      await confirmAnswering(
        tester,
        () => _error(401, 'not_authenticated', 'Sign in.'),
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(_icon(Icons.check_rounded), findsOneWidget);
    });
  });
}
