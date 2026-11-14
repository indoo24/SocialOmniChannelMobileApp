/// Customer intelligence laid out like the web client's conversation panel:
/// extraction banner, "Possible purchase detected" with Confirm purchase /
/// Not yet / Add note, the lead score and its bar, the signals behind it,
/// and the two-column grid — in English and Arabic, on a narrow phone, and
/// through the panel's loading and error states.
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
import 'package:scenario_mobile/core/models/intelligence.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/widgets/states.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversion_providers.dart';
import 'package:scenario_mobile/features/messages/customer_intelligence_section.dart';
import 'package:scenario_mobile/features/messages/intelligence_panel.dart';
import 'package:scenario_mobile/features/messages/intelligence_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

class _Backend implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Completer<void>? hold;
  bool failDecision = false;

  /// What `GET /conversations/1/intelligence/` answers: a JSON body, or an
  /// error status.
  Object? intelligenceBody;
  int intelligenceStatus = 200;

  Iterable<RequestOptions> get decisions =>
      requests.where((r) => r.path.endsWith('/confirm-purchase/'));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/confirm-purchase/')) {
      if (hold case final h?) await h.future;
      if (failDecision) {
        return _json({
          'error': {'code': 'conflict', 'message': 'Already decided.'},
        }, 409);
      }
      return _json({
        'stage': 'LEAD',
        'purchase_status': 'AGENT_CONFIRMED',
        'is_purchase_claim_pending': false,
        'is_agent_confirmed': true,
      });
    }
    if (options.path.endsWith('/intelligence/')) {
      return _json(intelligenceBody, intelligenceStatus);
    }
    return _json(<String, Object>{});
  }

  static ResponseBody _json(Object? body, [int status = 200]) =>
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

Employee _employee({bool canConfirm = true}) => Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: {
    Perm.intelligenceOverrideScore,
    Perm.conversationRefreshIntelligence,
    Perm.conversionReport,
    if (canConfirm) Perm.conversationConfirmPurchase,
  },
  visibilityScope: 'ALL',
);

/// The web screenshot's case: a lead at 25, one signal, a customer who says
/// they ordered.
ConversationIntelligence _intel({
  String purchaseStatus = 'CUSTOMER_SAYS_ORDERED',
  bool pending = true,
  int score = 25,
  List<LeadScoreSignal> signals = const [
    LeadScoreSignal(
      signal: 'order_claim',
      label: 'Customer says they ordered',
      points: 25,
    ),
  ],
}) => ConversationIntelligence(
  stage: 'LEAD',
  confidence: 0.35,
  purchaseStatus: purchaseStatus,
  purchaseEvidence: 'I sent the order yesterday',
  purchaseIntent: '',
  intentStrength: 'medium',
  urgency: 'low',
  sentiment: 'neutral',
  interestedProducts: const [],
  objections: const [],
  buyingSignals: const [],
  quantitySignal: '',
  summary: '',
  nextBestAction: '',
  leadScore: score,
  leadScoreSignals: signals,
  leadScoreAuto: score,
  leadScoreOverride: null,
  isLeadScoreOverridden: false,
  leadScoreOverriddenByName: '',
  leadScoreOverriddenAt: null,
  needsHumanReview: false,
  reviewReason: '',
  isPurchaseClaimPending: pending,
  isAgentConfirmed: false,
  confirmedByName: '',
  purchaseConfirmedAt: null,
  purchaseConfirmationNote: '',
  analysisVersion: 'rules:2',
  analyzerKey: 'rule_based',
  analyzedAt: null,
);

var _changes = 0;

Future<void> _pump(
  WidgetTester tester, {
  _Backend? backend,
  ConversationIntelligence? intelligence,
  String? customerName = 'Mona Adel',
  Employee? employee,
  Locale locale = const Locale('en'),
  double width = 400,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);
  _changes = 0;
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = backend ?? _Backend();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(employee ?? _employee()),
        conversationConversionsProvider(1).overrideWith((ref) async => []),
        purchaseConfirmationsProvider(1).overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CustomerIntelligenceView(
              conversationId: 1,
              intelligence: intelligence ?? _intel(),
              customerName: customerName,
              onChanged: () => _changes++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder matching) =>
    find.descendant(of: _key(key), matching: matching);

double _top(WidgetTester tester, String key) => tester.getTopLeft(_key(key)).dy;

void main() {
  testWidgets('the sections come in the web order', (tester) async {
    await _pump(tester);
    final order = [
      'intelExtractionBanner',
      'purchaseAlert',
      'leadScoreSection',
      'insightsGrid',
    ].map((k) => _top(tester, k)).toList();
    expect(order, orderedEquals([...order]..sort()));
  });

  group('extraction banner', () {
    testWidgets('says where the read came from, and to verify it', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        _in(
          'intelExtractionBanner',
          find.text(
            'Generated from conversation text by rules:2. Treat this as a '
            'suggestion — verify before acting.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        _in('intelExtractionBanner', find.byIcon(Icons.info_outline)),
        findsOneWidget,
      );
    });
  });

  group('possible purchase alert', () {
    testWidgets('who claims what, the quote, the actions, the footnote', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        _in('purchaseAlert', find.text('Possible purchase detected')),
        findsOneWidget,
      );
      expect(
        _in('purchaseAlert', find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(_key('purchaseAlertExplanation')).data,
        'Mona Adel says they have placed an order. Scenario has no access '
        'to payment records, so this is unverified.',
      );
      expect(
        _in('purchaseAlertQuote', find.text('“I sent the order yesterday”')),
        findsOneWidget,
      );
      expect(_key('confirmPurchaseButton'), findsOneWidget);
      expect(
        _in('confirmPurchaseButton', find.text('Confirm purchase')),
        findsOneWidget,
      );
      expect(_in('rejectPurchaseButton', find.text('Not yet')), findsOneWidget);
      expect(
        _in('addPurchaseNoteButton', find.text('Add note')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(_key('purchaseAlertFootnote')).data,
        'Confirming records your name and the time. It does not charge or '
        'verify any payment.',
      );
      // Not shown while nothing is pending.
      await _pump(tester, intelligence: _intel(pending: false));
      expect(_key('purchaseAlert'), findsNothing);
    });

    testWidgets('a paid claim, and no customer name', (tester) async {
      await _pump(
        tester,
        intelligence: _intel(purchaseStatus: 'CUSTOMER_SAYS_PAID'),
        customerName: null,
      );
      expect(
        tester.widget<Text>(_key('purchaseAlertExplanation')).data,
        'The customer says they have paid. Scenario has no access to '
        'payment records, so this is unverified.',
      );
    });

    testWidgets('without confirmation rights: who must review, no actions', (
      tester,
    ) async {
      await _pump(tester, employee: _employee(canConfirm: false));
      expect(
        tester.widget<Text>(_key('purchaseAlertNoRights')).data,
        'An employee with confirmation rights needs to review this claim.',
      );
      expect(_key('confirmPurchaseButton'), findsNothing);
      expect(_key('rejectPurchaseButton'), findsNothing);
      expect(_key('addPurchaseNoteButton'), findsNothing);
    });

    testWidgets('Confirm purchase: one request, a spinner while it runs, '
        'then the result', (tester) async {
      final backend = _Backend()..hold = Completer<void>();
      await _pump(tester, backend: backend);

      await tester.tap(_key('confirmPurchaseButton'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(backend.decisions.single.data, {'confirmed': true, 'note': ''});
      expect(
        _in('confirmPurchaseButton', find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      // Both decisions locked until the server answers.
      expect(
        tester.widget<ButtonStyleButton>(_key('rejectPurchaseButton')).enabled,
        isFalse,
      );
      await tester.tap(_key('confirmPurchaseButton'), warnIfMissed: false);
      await tester.pump();
      expect(backend.decisions, hasLength(1));

      backend.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Purchase confirmed'), findsOneWidget);
      expect(_changes, 1);
    });

    testWidgets('Not yet records the ruling; the claim is not deleted here', (
      tester,
    ) async {
      final backend = _Backend();
      await _pump(tester, backend: backend);
      await tester.tap(_key('rejectPurchaseButton'));
      await tester.pumpAndSettle();
      expect(backend.decisions.single.data, {'confirmed': false, 'note': ''});
      expect(backend.decisions.single.method, 'POST');
      expect(find.text('Recorded as not confirmed'), findsOneWidget);
      expect(_changes, 1);
    });

    testWidgets('a refused decision says why and leaves the claim to decide', (
      tester,
    ) async {
      final backend = _Backend()..failDecision = true;
      await _pump(tester, backend: backend);
      await tester.tap(_key('confirmPurchaseButton'));
      await tester.pumpAndSettle();
      expect(find.text('Already decided.'), findsOneWidget);
      expect(_changes, 0);
      expect(
        tester.widget<ButtonStyleButton>(_key('confirmPurchaseButton')).enabled,
        isTrue,
      );
    });

    testWidgets('Add note opens a note that goes with the decision', (
      tester,
    ) async {
      final backend = _Backend();
      await _pump(tester, backend: backend);
      expect(_key('purchaseNoteField'), findsNothing);

      await tester.tap(_key('addPurchaseNoteButton'));
      await tester.pumpAndSettle();
      expect(_key('purchaseNoteField'), findsOneWidget);
      expect(_key('addPurchaseNoteButton'), findsNothing);
      expect(
        tester.widget<TextField>(_key('purchaseNoteField')).maxLength,
        255,
      );

      await tester.enterText(_key('purchaseNoteField'), '  Not paid yet  ');
      await tester.tap(_key('rejectPurchaseButton'));
      await tester.pumpAndSettle();
      expect(backend.decisions.single.data, {
        'confirmed': false,
        'note': 'Not paid yet',
      });
    });
  });

  group('lead score', () {
    testWidgets('the score, out of 100, and a bar that far along', (
      tester,
    ) async {
      await _pump(tester);
      expect(_in('leadScoreSection', find.text('LEAD SCORE')), findsOneWidget);
      expect(_in('leadScoreValue', find.text('25')), findsOneWidget);
      expect(_in('leadScoreValue', find.text('/ 100')), findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(_key('leadScoreBar')).value,
        closeTo(0.25, 0.001),
      );
      // The number at the start, "/ 100" at the end.
      expect(
        tester.getTopLeft(_in('leadScoreValue', find.text('25'))).dx,
        lessThan(
          tester.getTopLeft(_in('leadScoreValue', find.text('/ 100'))).dx,
        ),
      );
      expect(_key('leadScoreEdit'), findsOneWidget);
      expect(_key('leadScoreMeta'), findsOneWidget);
      // Comfortably tappable.
      expect(
        tester.getSize(_key('leadScoreEdit')).height,
        greaterThanOrEqualTo(36),
      );

      for (final (score, bar) in [(0, 0.02), (100, 1.0), (73, 0.73)]) {
        await _pump(tester, intelligence: _intel(score: score));
        expect(
          tester.widget<LinearProgressIndicator>(_key('leadScoreBar')).value,
          closeTo(bar, 0.001),
          reason: 'score $score',
        );
        expect(_in('leadScoreValue', find.text('$score')), findsOneWidget);
      }
    });

    testWidgets('the signals behind it expand and collapse', (tester) async {
      await _pump(tester);
      expect(
        _in(
          'scoreSignalsToggle',
          find.text('Show the 1 signals behind this score'),
        ),
        findsOneWidget,
      );
      expect(_key('scoreSignalsList'), findsNothing);

      await tester.tap(_key('scoreSignalsToggle'));
      await tester.pumpAndSettle();
      expect(
        _in('scoreSignal_order_claim', find.text('Customer says they ordered')),
        findsOneWidget,
      );
      expect(_in('scoreSignal_order_claim', find.text('+25')), findsOneWidget);
      expect(
        _in(
          'scoreSignalsToggle',
          find.text('Hide the 1 signals behind this score'),
        ),
        findsOneWidget,
      );

      await tester.tap(_key('scoreSignalsToggle'));
      await tester.pumpAndSettle();
      expect(_key('scoreSignalsList'), findsNothing);

      // No signals, no toggle.
      await _pump(tester, intelligence: _intel(signals: const []));
      expect(_key('scoreSignalsToggle'), findsNothing);
    });
  });

  testWidgets('the grid: two columns, the model values, badges', (
    tester,
  ) async {
    await _pump(tester);
    expect(_in('insight_stage', find.text('STAGE')), findsOneWidget);
    expect(_in('insight_stage', find.text('Lead')), findsOneWidget);
    expect(_in('insight_confidence', find.text('35%')), findsOneWidget);
    expect(_in('insight_purchase', find.text('Says ordered')), findsOneWidget);
    expect(_in('insight_sentiment', find.text('Neutral')), findsOneWidget);
    expect(_in('insight_intent', find.text('Medium')), findsOneWidget);
    expect(_in('insight_urgency', find.text('Low')), findsOneWidget);

    // Pairs share a row; in English the first of each pair is on the left.
    for (final (a, b) in [
      ('insight_stage', 'insight_confidence'),
      ('insight_purchase', 'insight_sentiment'),
      ('insight_intent', 'insight_urgency'),
    ]) {
      expect(_top(tester, a), _top(tester, b));
      expect(
        tester.getTopLeft(_key(a)).dx,
        lessThan(tester.getTopLeft(_key(b)).dx),
      );
    }
    expect(
      _top(tester, 'insight_stage'),
      lessThan(_top(tester, 'insight_purchase')),
    );
  });

  testWidgets('Arabic: right to left, Arabic labels and values', (
    tester,
  ) async {
    await _pump(tester, locale: const Locale('ar'), customerName: 'منى عادل');
    expect(tester.takeException(), isNull);
    expect(find.text('رُصدت عملية شراء محتملة'), findsOneWidget);
    expect(
      tester.widget<Text>(_key('purchaseAlertExplanation')).data,
      startsWith('منى عادل يقول إنه أرسل طلبًا.'),
    );
    expect(find.text('تأكيد الشراء'), findsOneWidget);
    expect(find.text('ليس بعد'), findsOneWidget);
    expect(find.text('إضافة ملاحظة'), findsOneWidget);
    expect(find.text('تقييم العميل المحتمل'), findsOneWidget);
    expect(
      find.text('إظهار الـ 1 إشارات التي وراء هذه الدرجة'),
      findsOneWidget,
    );
    expect(_in('insight_stage', find.text('المرحلة')), findsOneWidget);
    expect(_in('insight_stage', find.text('عميل محتمل')), findsOneWidget);
    expect(_in('insight_confidence', find.text('درجة الثقة')), findsOneWidget);
    expect(_in('insight_purchase', find.text('يقول إنه طلب')), findsOneWidget);
    expect(_in('insight_sentiment', find.text('محايد')), findsOneWidget);
    expect(
      Directionality.of(tester.element(_key('purchaseAlert'))),
      TextDirection.rtl,
    );
    // Right to left: the first of each pair sits on the right.
    expect(
      tester.getTopLeft(_key('insight_stage')).dx,
      greaterThan(tester.getTopLeft(_key('insight_confidence')).dx),
    );
    // The quote's accent border is on the start (right) side.
    final quote = tester.widget<Container>(_key('purchaseAlertQuote'));
    final border =
        (quote.decoration! as BoxDecoration).border! as BorderDirectional;
    expect(border.start.width, 2);
  });

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('a 320px phone (${locale.languageCode}): nothing overflows, '
        'the note open, the signals out', (tester) async {
      await _pump(tester, locale: locale, width: 320);
      await tester.tap(_key('addPurchaseNoteButton'));
      await tester.pumpAndSettle();
      await tester.tap(_key('scoreSignalsToggle'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Every action still a full-size target, inside the screen.
      for (final key in ['confirmPurchaseButton', 'rejectPurchaseButton']) {
        final rect = tester.getRect(_key(key));
        expect(rect.height, greaterThanOrEqualTo(40), reason: key);
        expect(rect.left, greaterThanOrEqualTo(0), reason: key);
        expect(rect.right, lessThanOrEqualTo(320), reason: key);
      }
    });
  }

  group('panel loading and error', () {
    Future<void> openPanel(WidgetTester tester, _Backend backend) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = backend;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            apiClientProvider.overrideWithValue(client),
            currentEmployeeProvider.overrideWithValue(_employee()),
            conversationConversionsProvider(1).overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showIntelligencePanel(context, conversationId: 1),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
    }

    testWidgets('loading, then the redesigned content', (tester) async {
      final backend = _Backend()
        ..intelligenceBody = {
          'stage': 'LEAD',
          'confidence': 0.35,
          'purchase_status': 'NONE',
          'lead_score': 25,
          'analysis_version': 'rules:2',
        };
      await openPanel(tester, backend);
      expect(find.byType(LoadingState), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(LoadingState), findsNothing);
      expect(_key('intelExtractionBanner'), findsOneWidget);
      expect(_key('leadScoreSection'), findsOneWidget);
      expect(_key('insightsGrid'), findsOneWidget);
    });

    testWidgets('an error, with a retry', (tester) async {
      final backend = _Backend()
        ..intelligenceStatus = 500
        ..intelligenceBody = {
          'error': {'code': 'server_error', 'message': 'Analyzer down.'},
        };
      await openPanel(tester, backend);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(_key('leadScoreSection'), findsNothing);
    });
  });
}
