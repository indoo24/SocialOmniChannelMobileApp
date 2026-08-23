/// Reproduction harness for the reported crash: editing the lead score in
/// the Intelligence panel and pressing Save.
///
/// `_LeadScoreSectionState._editScore()` (intelligence_panel.dart) creates a
/// `TextEditingController`, hands it to a `TextField` inside a `showDialog`
/// `AlertDialog`, and — once `showDialog`'s Future resolves — disposes that
/// controller immediately:
///
///     final entered = await showDialog<int>(...);
///     controller.dispose();
///
/// `showDialog`'s Future resolves the instant `Navigator.pop(value)` runs
/// inside the Save button's `onPressed`, which is *before* the dialog's own
/// exit transition (`AlertDialog`'s default fade/scale) has finished
/// animating the still-mounted `TextField` off screen. Disposing a
/// `TextEditingController` while a live `TextField` is still bound to it is
/// a well-known Flutter crash: `FlutterError: A TextEditingController was
/// used after being disposed.` This file drives the exact same real,
/// unmodified `showIntelligencePanel` entry point through that timing
/// window, pumping frame-by-frame across the exit transition rather than
/// `pumpAndSettle()`-ing past it, so the assertion (if it fires) is not
/// swallowed by settling too far in one step.
library;

import 'dart:async';
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
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/intelligence_panel.dart';
import 'package:scenario_mobile/features/messages/intelligence_providers.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ignore: library_private_types_in_public_api
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

final _employee = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'SUPERVISOR',
  roleDisplay: 'Supervisor',
  availability: 'ONLINE',
  permissions: const {
    Perm.intelligenceOverrideScore,
    Perm.conversationConfirmPurchase,
  },
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme Retail'),
);

const _intelligence = ConversationIntelligence(
  stage: 'QUALIFIED_LEAD',
  confidence: 0.8,
  purchaseStatus: 'NONE',
  purchaseEvidence: '',
  purchaseIntent: '',
  intentStrength: 'none',
  urgency: 'none',
  sentiment: 'neutral',
  interestedProducts: [],
  objections: [],
  buyingSignals: [],
  quantitySignal: '',
  summary: '',
  nextBestAction: '',
  leadScore: 42,
  leadScoreSignals: [],
  leadScoreAuto: 42,
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

const _purchaseClaimIntelligence = ConversationIntelligence(
  stage: 'HOT_LEAD',
  confidence: 0.8,
  purchaseStatus: 'CUSTOMER_SAYS_PAID',
  purchaseEvidence: 'Customer said "just paid via GCash"',
  purchaseIntent: '',
  intentStrength: 'none',
  urgency: 'none',
  sentiment: 'neutral',
  interestedProducts: [],
  objections: [],
  buyingSignals: [],
  quantitySignal: '',
  summary: '',
  nextBestAction: '',
  leadScore: 60,
  leadScoreSignals: [],
  leadScoreAuto: 60,
  leadScoreOverride: null,
  isLeadScoreOverridden: false,
  leadScoreOverriddenByName: '',
  leadScoreOverriddenAt: null,
  needsHumanReview: false,
  reviewReason: '',
  isPurchaseClaimPending: true,
  isAgentConfirmed: false,
  confirmedByName: '',
  purchaseConfirmedAt: null,
  purchaseConfirmationNote: '',
  analysisVersion: '',
  analyzerKey: '',
  analyzedAt: null,
);

Widget _harness({
  required ApiClient apiClient,
  required Widget child,
  ConversationIntelligence intelligence = _intelligence,
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      currentEmployeeProvider.overrideWithValue(_employee),
      conversationIntelligenceProvider(
        1,
      ).overrideWith((ref) async => intelligence),
      purchaseConfirmationsProvider(1).overrideWith((ref) async => []),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _openButton(BuildContext context) => ElevatedButton(
  onPressed: () => showIntelligencePanel(context, conversationId: 1),
  child: const Text('open intelligence'),
);

/// Pumps frame-by-frame across a typical dialog exit-transition duration
/// (Material's default is ~150ms) instead of pumpAndSettle(), so a
/// use-after-dispose thrown mid-transition is not skipped over.
Future<void> _pumpAcrossExitTransition(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'editing the lead score and pressing Save does not use the TextEditingController '
    'after it is disposed',
    (tester) async {
      final client = _stubClient((options) {
        if (options.path.contains('lead-score')) {
          return _json(
            '{"stage": "QUALIFIED_LEAD", "lead_score": 77, '
            '"lead_score_auto": 42, "is_lead_score_overridden": true, '
            '"lead_score_overridden_by_name": "Sam Agent"}',
            200,
          );
        }
        return _json('{}', 200);
      });

      await tester.pumpWidget(
        _harness(
          apiClient: client,
          child: Builder(builder: _openButton),
        ),
      );
      await tester.tap(find.text('open intelligence'));
      await tester.pumpAndSettle();

      // Open the "set score by hand" dialog.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      // Change the value and press Save — this is the exact reported
      // repro: edit the score, then tap Save.
      await tester.enterText(find.byType(TextField), '77');
      await tester.tap(find.text('Save'));

      // Do NOT pumpAndSettle() here: that would fast-forward straight past
      // the dialog's exit transition. Pump it frame by frame so a
      // use-after-dispose thrown mid-animation is actually observed.
      await _pumpAcrossExitTransition(tester);

      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapidly editing the score twice in a row does not throw', (
    tester,
  ) async {
    final client = _stubClient((options) {
      if (options.path.contains('lead-score')) {
        return _json(
          '{"stage": "QUALIFIED_LEAD", "lead_score": 90, '
          '"lead_score_auto": 42, "is_lead_score_overridden": true, '
          '"lead_score_overridden_by_name": "Sam Agent"}',
          200,
        );
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open intelligence'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '${80 + i}');
      await tester.tap(find.text('Save'));
      await _pumpAcrossExitTransition(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('confirming a pending purchase claim does not use its note '
      'TextEditingController after it is disposed', (tester) async {
    final client = _stubClient((options) {
      if (options.path.contains('confirm-purchase')) {
        return _json(
          '{"stage": "HOT_LEAD", "purchase_status": "AGENT_CONFIRMED", '
          '"lead_score": 60, "lead_score_auto": 60, '
          '"is_purchase_claim_pending": false, "is_agent_confirmed": true}',
          200,
        );
      }
      return _json('{}', 200);
    });

    await tester.pumpWidget(
      _harness(
        apiClient: client,
        intelligence: _purchaseClaimIntelligence,
        child: Builder(builder: _openButton),
      ),
    );
    await tester.tap(find.text('open intelligence'));
    await tester.pumpAndSettle();

    // Same shape as the lead-score dialog: a note TextField, then a
    // decision button that pops the dialog immediately.
    await tester.tap(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Confirm'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Paid via GCash');

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Confirm'),
      ),
    );

    // Same reasoning as above: pump frame by frame across the dialog's
    // exit transition rather than pumpAndSettle() past it.
    await _pumpAcrossExitTransition(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
