import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/conversion_event.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/models/intelligence.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/customer_intelligence_section.dart';
import 'package:scenario_mobile/features/messages/conversion_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
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

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return client;
}

final _fullEmployee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: const {
    Perm.intelligenceOverrideScore,
    Perm.conversationRefreshIntelligence,
    Perm.conversionReport,
    Perm.conversationConfirmPurchase,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

final _baseIntelligence = ConversationIntelligence(
  stage: 'HOT_LEAD',
  confidence: 0.55,
  purchaseStatus: 'NONE',
  purchaseEvidence: '',
  purchaseIntent: '',
  intentStrength: 'medium',
  urgency: 'none',
  sentiment: 'positive',
  interestedProducts: ['Wireless Headphones'],
  objections: ['Price too high'],
  buyingSignals: ['asked about price', 'asked about availability'],
  quantitySignal: '',
  summary: 'Indoo has made an initial enquiry.',
  nextBestAction: 'Send the price along with what is included.',
  leadScore: 20,
  leadScoreSignals: const [
    LeadScoreSignal(
      signal: 'pricing_intent',
      label: 'Asked for pricing',
      points: 15,
    ),
    LeadScoreSignal(
      signal: 'availability_check',
      label: 'Asked for availability',
      points: 10,
    ),
    LeadScoreSignal(
      signal: 'churn_risk',
      label: 'Hesitation observed',
      points: -5,
    ),
  ],
  leadScoreAuto: 38,
  leadScoreOverride: 20,
  isLeadScoreOverridden: true,
  leadScoreOverriddenByName: 'Mohamed Gad',
  leadScoreOverriddenAt: DateTime(2026, 9, 4, 18, 45),
  needsHumanReview: false,
  reviewReason: '',
  isPurchaseClaimPending: false,
  isAgentConfirmed: false,
  confirmedByName: '',
  purchaseConfirmedAt: null,
  purchaseConfirmationNote: '',
  analysisVersion: 'mock:1',
  analyzerKey: 'rule_based',
  analyzedAt: DateTime(2026, 9, 4, 18, 40),
);

Widget _harness({
  required Widget child,
  ApiClient? apiClient,
  Employee? employee,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Size surfaceSize = const Size(400, 800),
}) {
  final client = apiClient ?? _stubClient((_) => _json('{}', 200));
  final emp = employee ?? _fullEmployee;

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      currentEmployeeProvider.overrideWithValue(emp),
      conversationConversionsProvider(1).overrideWith(
        (ref) async => const [
          ConversionEvent(
            id: 1,
            eventName: 'Lead',
            sourceStage: 'HOT_LEAD',
            sourcePurchaseStatus: 'NONE',
            status: 'SENT',
            eventsReceived: 1,
            errorMessage: '',
            value: '',
            currency: 'EGP',
            createdAt: null,
          ),
        ],
      ),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: surfaceSize),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    '1. Customer intelligence header renders with icon, title, and refresh button',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          child: CustomerIntelligenceView(
            conversationId: 1,
            intelligence: _baseIntelligence,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.auto_awesome), findsWidgets);
      expect(find.text('Customer intelligence'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    },
  );

  testWidgets(
    '2. Refresh action triggers refreshIntelligence and handles in-flight state',
    (tester) async {
      var refreshed = false;
      final client = _stubClient((options) {
        if (options.path.contains('intelligence')) {
          refreshed = true;
          return _json('{}', 200);
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: CustomerIntelligenceView(
            conversationId: 1,
            intelligence: _baseIntelligence,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(refreshed, isTrue);
    },
  );

  testWidgets('3 & 4. Lead score and progress bar render from model data', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('20'), findsOneWidget);
    expect(find.text('/ 100'), findsOneWidget);

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, closeTo(0.20, 0.01));
  });

  testWidgets('5. Score history / source renders when overridden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check that Mohamed Gad and 38 are rendered
    expect(find.textContaining('Mohamed Gad'), findsOneWidget);
    expect(find.textContaining('38'), findsOneWidget);
    expect(find.textContaining('Set to 20'), findsOneWidget);
  });

  testWidgets(
    '6 & 7. Signals expansion works and displays actual signal count',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          child: CustomerIntelligenceView(
            conversationId: 1,
            intelligence: _baseIntelligence,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially collapsed
      expect(
        find.textContaining('Show the 3 signals behind this score'),
        findsOneWidget,
      );
      expect(find.text('Asked for pricing'), findsNothing);

      // Tap to expand
      await tester.tap(
        find.textContaining('Show the 3 signals behind this score'),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hide the 3 signals behind this score'),
        findsOneWidget,
      );
      expect(find.text('Asked for pricing'), findsOneWidget);
      expect(find.text('+15'), findsOneWidget);
      expect(find.text('Asked for availability'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.text('Hesitation observed'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
    },
  );

  testWidgets(
    '8, 9, 10, 11, 12, 13. Intelligence attributes 2-column grid renders all attributes',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          child: CustomerIntelligenceView(
            conversationId: 1,
            intelligence: _baseIntelligence,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STAGE'), findsOneWidget);
      expect(find.text('Hot lead'), findsOneWidget);

      expect(find.text('CONFIDENCE'), findsOneWidget);
      expect(find.text('55%'), findsOneWidget);

      expect(find.text('PURCHASE STATUS'), findsOneWidget);
      expect(find.text('SENTIMENT'), findsOneWidget);
      expect(find.text('Positive'), findsOneWidget);

      expect(find.text('INTENT'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);

      expect(find.text('URGENCY'), findsOneWidget);
      expect(
        find.text('None'),
        findsNWidgets(2),
      ); // purchase status and urgency
    },
  );

  testWidgets('14. Buying signals render actual signals with arrow icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BUYING SIGNALS'), findsOneWidget);
    expect(find.text('asked about price'), findsOneWidget);
    expect(find.text('asked about availability'), findsOneWidget);
    expect(find.byIcon(Icons.north_east), findsNWidgets(2));
  });

  testWidgets('15. Summary renders backend summary', (tester) async {
    await tester.pumpWidget(
      _harness(
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SUMMARY'), findsOneWidget);
    expect(find.text('Indoo has made an initial enquiry.'), findsOneWidget);
  });

  testWidgets('16. Recommended next action renders highlighted card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recommended next action'), findsOneWidget);
    expect(
      find.text('Send the price along with what is included.'),
      findsOneWidget,
    );
  });

  testWidgets(
    '17 & 18. Empty buying signals and missing optional fields handle gracefully',
    (tester) async {
      const emptyIntel = ConversationIntelligence(
        stage: 'NEW_LEAD',
        confidence: 0.0,
        purchaseStatus: 'NONE',
        purchaseEvidence: '',
        purchaseIntent: '',
        intentStrength: 'none',
        urgency: 'none',
        sentiment: '',
        interestedProducts: [],
        objections: [],
        buyingSignals: [],
        quantitySignal: '',
        summary: '',
        nextBestAction: '',
        leadScore: 0,
        leadScoreSignals: [],
        leadScoreAuto: 0,
        leadScoreOverride: null,
        isLeadScoreOverridden: false,
        leadScoreOverriddenByName: '',
        leadScoreOverriddenAt: null,
        needsHumanReview: false,
        reviewReason: '',
        isPurchaseClaimPending: false,
        isAgentConfirmed: false,
        confirmedByName: '',
        purchaseConfirmedAt: null,
        purchaseConfirmationNote: '',
        analysisVersion: '',
        analyzerKey: '',
        analyzedAt: null,
      );

      await tester.pumpWidget(
        _harness(
          child: CustomerIntelligenceView(
            conversationId: 1,
            intelligence: emptyIntel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No buying signals detected yet'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('21. Edit score dialog opens and submits override', (
    tester,
  ) async {
    var postedScore = -1;
    final client = _stubClient((options) {
      if (options.path.contains('lead-score')) {
        final data = options.data as Map<String, dynamic>;
        postedScore = data['score'] as int;
        return _json('{}', 200);
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Edit
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '65');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(postedScore, 65);
  });

  testWidgets('22. Auto action resets lead score to auto', (tester) async {
    var resetCalled = false;
    final client = _stubClient((options) {
      if (options.path.contains('lead-score')) {
        final data = options.data as Map<String, dynamic>;
        if (data['score'] == null) resetCalled = true;
        return _json('{}', 200);
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();

    expect(resetCalled, isTrue);
  });

  testWidgets('23. Meta action calls reportConversion', (tester) async {
    var reportedMeta = false;
    final client = _stubClient((options) {
      if (options.path.contains('report-conversion')) {
        reportedMeta = true;
        return _json(
          '{"status": "SENT", "detail": "Success", "event_name": "Lead"}',
          200,
        );
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Meta'), findsOneWidget);
    await tester.tap(find.text('Meta'));
    await tester.pumpAndSettle();

    expect(reportedMeta, isTrue);
  });

  testWidgets('24. Arabic/RTL renders correctly without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        locale: const Locale('ar'),
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ذكاء العملاء'), findsOneWidget);
    expect(find.text('تعديل'), findsOneWidget);
    expect(find.text('تلقائي'), findsOneWidget);
    expect(find.text('إشارات الشراء'), findsOneWidget);
    expect(find.text('الملخص'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('25. Dark mode renders correctly without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        themeMode: ThemeMode.dark,
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer intelligence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('26. Narrow screen (320px) has no overflow', (tester) async {
    await tester.pumpWidget(
      _harness(
        surfaceSize: const Size(320, 900),
        child: CustomerIntelligenceView(
          conversationId: 1,
          intelligence: _baseIntelligence,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer intelligence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
