/// Conversation intelligence: model parsing and the five endpoints in
/// `ConversationRepository`.
///
/// Mirrors `api_client_test.dart`'s `_StubAdapter` — networking is tested
/// directly against canned responses rather than through widgets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/intelligence.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/messages/intelligence_providers.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
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

ConversationRepository _repositoryReturning(
  ResponseBody Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = _StubAdapter(handler);
  return ConversationRepository(client);
}

const _fullIntelligenceJson = '''
{
  "stage": "QUALIFIED_LEAD",
  "confidence": 0.82,
  "purchase_status": "CUSTOMER_SAYS_ORDERED",
  "purchase_evidence": "I already paid for it",
  "purchase_intent": "buy_now",
  "intent_strength": "high",
  "urgency": "medium",
  "sentiment": "positive",
  "interested_products": ["Blue sneakers"],
  "objections": ["price"],
  "buying_signals": ["asked about delivery"],
  "quantity_signal": "2 pairs",
  "summary": "Customer wants to buy blue sneakers.",
  "next_best_action": "Confirm the order.",
  "lead_score": 72,
  "lead_score_signals": [{"signal": "purchase_claim", "label": "Says they ordered", "points": 30}],
  "lead_score_auto": 60,
  "lead_score_override": 72,
  "is_lead_score_overridden": true,
  "lead_score_overridden_by_name": "Nour",
  "lead_score_overridden_at": "2026-08-19T10:00:00Z",
  "needs_human_review": true,
  "review_reason": "Purchase claim needs confirmation",
  "is_purchase_claim_pending": true,
  "is_agent_confirmed": false,
  "confirmed_by_name": "",
  "purchase_confirmed_at": null,
  "purchase_confirmation_note": "",
  "analysis_version": "mock:1",
  "analyzer_key": "mock",
  "analyzed_at": "2026-08-19T09:55:00Z"
}
''';

void main() {
  group('ConversationIntelligence.fromJson', () {
    test('parses the full backend shape', () {
      final intel = ConversationIntelligence.fromJson(
        jsonDecode(_fullIntelligenceJson) as Map<String, dynamic>,
      );

      expect(intel.stage, 'QUALIFIED_LEAD');
      expect(intel.confidence, 0.82);
      expect(intel.purchaseStatus, 'CUSTOMER_SAYS_ORDERED');
      expect(intel.leadScore, 72);
      expect(intel.leadScoreAuto, 60);
      expect(intel.leadScoreOverride, 72);
      expect(intel.isLeadScoreOverridden, isTrue);
      expect(intel.leadScoreOverriddenByName, 'Nour');
      expect(intel.leadScoreSignals, hasLength(1));
      expect(intel.leadScoreSignals.single.points, 30);
      expect(intel.needsHumanReview, isTrue);
      expect(intel.isPurchaseClaimPending, isTrue);
      expect(intel.isAgentConfirmed, isFalse);
      expect(intel.interestedProducts, ['Blue sneakers']);
      expect(intel.analyzedAt, isNotNull);
    });

    test('a missing/reset override parses as null, not zero', () {
      final intel = ConversationIntelligence.fromJson({
        'stage': 'NEW_LEAD',
        'purchase_status': 'NONE',
        'lead_score': 40,
        'lead_score_auto': 40,
        'lead_score_override': null,
        'is_lead_score_overridden': false,
      });

      expect(intel.leadScoreOverride, isNull);
      expect(intel.isLeadScoreOverridden, isFalse);
      expect(intel.leadScore, 40);
    });

    test('malformed fields fall back rather than throwing', () {
      final intel = ConversationIntelligence.fromJson(const {});

      expect(intel.stage, 'NEW_LEAD');
      expect(intel.purchaseStatus, 'NONE');
      expect(intel.leadScore, 0);
      expect(intel.leadScoreSignals, isEmpty);
      expect(intel.needsHumanReview, isFalse);
    });
  });

  group('PurchaseConfirmation.fromJson', () {
    test('parses a confirmation row', () {
      final confirmation = PurchaseConfirmation.fromJson({
        'id': 9,
        'decision': 'CONFIRMED',
        'previous_status': 'CUSTOMER_SAYS_ORDERED',
        'evidence': 'I paid already',
        'note': 'Verified with the shop.',
        'employee_name': 'Mona',
        'decided_at': '2026-08-19T11:00:00Z',
      });

      expect(confirmation.isConfirmed, isTrue);
      expect(confirmation.employeeName, 'Mona');
      expect(confirmation.decidedAt, isNotNull);
    });
  });

  group('ConversationRepository intelligence endpoints', () {
    test(
      'GET /intelligence/ returns null before the analyzer has run',
      () async {
        final repository = _repositoryReturning((_) => _json('null', 200));

        final result = await repository.intelligence(1);

        expect(result, isNull);
      },
    );

    test('GET /intelligence/ parses a full read', () async {
      final repository = _repositoryReturning(
        (_) => _json(_fullIntelligenceJson, 200),
      );

      final result = await repository.intelligence(1);

      expect(result, isNotNull);
      expect(result!.stage, 'QUALIFIED_LEAD');
      expect(result.leadScore, 72);
    });

    test(
      'POST /intelligence/ re-runs the analyzer and returns the fresh read',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json(_fullIntelligenceJson, 200);
        });

        final result = await repository.refreshIntelligence(1);

        expect(captured!.method, 'POST');
        expect(captured!.path, '/conversations/1/intelligence/');
        expect(result!.leadScore, 72);
      },
    );

    test('POST /lead-score/ sends the override as a body field', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_fullIntelligenceJson, 200);
      });

      await repository.setLeadScore(1, 85);

      expect(captured!.path, '/conversations/1/lead-score/');
      expect(captured!.data, {'score': 85});
    });

    test(
      'POST /lead-score/ with score:null hands control back to the analyzer',
      () async {
        RequestOptions? captured;
        final repository = _repositoryReturning((options) {
          captured = options;
          return _json(_fullIntelligenceJson, 200);
        });

        await repository.setLeadScore(1, null);

        // An explicit null key, not an omitted one — the backend treats them
        // differently (reset vs malformed request).
        expect(captured!.data, {'score': null});
        expect((captured!.data as Map).containsKey('score'), isTrue);
      },
    );

    test('POST /confirm-purchase/ sends confirmed and note', () async {
      RequestOptions? captured;
      final repository = _repositoryReturning((options) {
        captured = options;
        return _json(_fullIntelligenceJson, 200);
      });

      await repository.confirmPurchase(
        1,
        confirmed: true,
        note: 'Checked the shop records.',
      );

      expect(captured!.path, '/conversations/1/confirm-purchase/');
      expect(captured!.data, {
        'confirmed': true,
        'note': 'Checked the shop records.',
      });
    });

    test(
      'GET /purchase-confirmations/ parses a plain, unpaginated array',
      () async {
        final repository = _repositoryReturning(
          (_) => _json(
            '[{"id": 1, "decision": "CONFIRMED", "employee_name": "Mona", '
            '"decided_at": "2026-08-19T11:00:00Z"}, '
            '{"id": 2, "decision": "REJECTED", "employee_name": "Sam", '
            '"decided_at": "2026-08-18T11:00:00Z"}]',
            200,
          ),
        );

        final result = await repository.purchaseConfirmations(1);

        expect(result, hasLength(2));
        expect(result.first.isConfirmed, isTrue);
        expect(result.last.isConfirmed, isFalse);
      },
    );

    test(
      'a malformed row in the history is dropped, not fatal to the page',
      () async {
        final repository = _repositoryReturning(
          (_) => _json(
            '[{"id": 1, "decision": "CONFIRMED"}, "not-an-object"]',
            200,
          ),
        );

        final result = await repository.purchaseConfirmations(1);

        expect(result, hasLength(1));
      },
    );
  });

  group('conversationIntelligenceProvider realtime invalidation', () {
    // realtime_bridge.dart's `intelligence.updated` handler calls
    // `ref.invalidate(conversationIntelligenceProvider(id))` so the panel
    // refetches from the authority rather than being patched from the event.
    // This proves the provider actually does refetch on invalidate, which is
    // the mechanism that call depends on.
    test('invalidating the provider triggers a fresh fetch', () async {
      var callCount = 0;
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((_) {
        callCount += 1;
        return _json(_fullIntelligenceJson, 200);
      });

      final container = ProviderContainer(
        overrides: [
          cookieJarProvider.overrideWithValue(CookieJar()),
          apiClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final first = await container.read(
        conversationIntelligenceProvider(1).future,
      );
      expect(first!.leadScore, 72);
      expect(callCount, 1);

      container.invalidate(conversationIntelligenceProvider(1));

      final second = await container.read(
        conversationIntelligenceProvider(1).future,
      );
      expect(second!.leadScore, 72);
      expect(
        callCount,
        2,
        reason: 'invalidate must cause a refetch, not reuse the cached value',
      );
    });
  });
}
