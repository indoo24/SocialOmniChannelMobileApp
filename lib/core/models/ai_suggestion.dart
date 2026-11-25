/// An AI-drafted reply for the employee to review —
/// `POST /api/conversations/{id}/ai-suggestion/` (`SuggestionResponse`).
///
/// The endpoint sends nothing: no message is created and no ownership,
/// unread count, status or routing changes. A human puts [draft] in the
/// composer and a human presses Send.
library;

import '../utils/json_safe.dart';

/// `SuggestionResponse.status`. Read first: only [answered] carries a draft.
class AiSuggestionStatus {
  const AiSuggestionStatus._();

  /// [AiSuggestion.draft] holds the reply.
  static const answered = 'ANSWERED';

  /// The knowledge base cannot support a reply — no draft;
  /// [AiSuggestion.errorCode] says why.
  static const notInKb = 'NOT_IN_KB';

  /// Two or more sources contradict each other — no draft;
  /// [AiSuggestion.citations] names them.
  static const conflictingKnowledge = 'CONFLICTING_KNOWLEDGE';

  /// The provider failed.
  static const error = 'ERROR';
}

/// `SuggestionResponse.error_code` values the API documents for
/// [AiSuggestionStatus.notInKb].
class AiSuggestionErrorCode {
  const AiSuggestionErrorCode._();

  static const attachmentReviewRequired = 'attachment_review_required';
  static const noCustomerMessage = 'no_customer_message';
  static const noKnowledgeBase = 'no_knowledge_base';
}

/// `OutcomeEnum` for `POST /api/ai/suggestions/{public_id}/outcome/`.
class AiSuggestionOutcome {
  const AiSuggestionOutcome._();

  /// The draft was placed into the composer. Sends nothing.
  static const used = 'USED';
  static const discarded = 'DISCARDED';
}

/// A knowledge-base source a suggestion rests on (`SuggestionCitation`).
class AiSuggestionCitation {
  const AiSuggestionCitation({
    required this.sourceTitle,
    required this.chunkId,
  });

  final String sourceTitle;
  final String chunkId;

  factory AiSuggestionCitation.fromJson(Map<String, dynamic> json) =>
      AiSuggestionCitation(
        sourceTitle: JsonSafe.asString(json['source_title']),
        chunkId: JsonSafe.asString(json['chunk_id']),
      );
}

class AiSuggestion {
  const AiSuggestion({
    required this.suggestionId,
    required this.status,
    this.draft = '',
    this.citations = const [],
    this.throughMessageId,
    this.errorCode = '',
    this.errorDetail = '',
    this.conflictReason = '',
  });

  /// `suggestion_id` — reported back as the outcome's id, and sent with
  /// the reply (`Reply.suggestion_id`) when the draft is what was sent.
  final String suggestionId;
  final String status;

  /// Empty for every status but [AiSuggestionStatus.answered].
  final String draft;
  final List<AiSuggestionCitation> citations;

  /// The newest message the draft was written against. A newer message
  /// since means the draft is stale.
  final int? throughMessageId;
  final String errorCode;
  final String errorDetail;
  final String conflictReason;

  /// Whether there is something that may go into a composer. The API is
  /// explicit: read `status` first, and never put an empty draft into a
  /// composer.
  bool get hasDraft =>
      status == AiSuggestionStatus.answered && draft.trim().isNotEmpty;

  /// Whether a message newer than the one the draft was written against has
  /// arrived since.
  bool isStaleAgainst(int? newestMessageId) =>
      throughMessageId != null &&
      newestMessageId != null &&
      newestMessageId > throughMessageId!;

  factory AiSuggestion.fromJson(Map<String, dynamic> json) => AiSuggestion(
    suggestionId: JsonSafe.asString(json['suggestion_id']),
    status: JsonSafe.asString(json['status']).toUpperCase(),
    draft: JsonSafe.asString(json['draft']),
    citations: [
      for (final c in JsonSafe.asObjectList(json['citations']))
        if (c is Map) AiSuggestionCitation.fromJson(JsonSafe.asMap(c)),
    ],
    throughMessageId: JsonSafe.asIntOrNull(json['through_message_id']),
    errorCode: JsonSafe.asString(json['error_code']),
    errorDetail: JsonSafe.asString(json['error_detail']),
    conflictReason: JsonSafe.asString(json['conflict_reason']),
  );
}
