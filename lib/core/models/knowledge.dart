/// AI knowledge: knowledge bases, their sources, the answer playground, and
/// per-channel Agent Assist settings.
///
/// Shapes follow the backend's OpenAPI schema (`KnowledgeBase`,
/// `KnowledgeSource`, `PlaygroundResponse`, `AIAgentSetting`, `Readiness`,
/// `AIUsageSummary`, `KnowledgeConflict`). Every enum-like field stays a
/// plain string: an unknown value from a newer backend degrades to "not one
/// of the cases this app knows" rather than failing to parse.
library;

import '../utils/json_safe.dart';

DateTime? _date(Object? value) {
  final raw = JsonSafe.asStringOrNull(value);
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

// --------------------------------------------------------------------------- //
// Knowledge bases and sources
// --------------------------------------------------------------------------- //

/// A named collection the AI may answer from. `id` is the public UUID — the
/// one the playground's `knowledge_base_id` takes.
class KnowledgeBase {
  const KnowledgeBase({
    required this.id,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.sourceCount = 0,
    this.readySourceCount = 0,
    this.createdByName = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;

  /// An inactive base is skipped by retrieval; its content survives.
  final bool isActive;
  final int sourceCount;
  final int readySourceCount;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory KnowledgeBase.fromJson(Map<String, dynamic> json) => KnowledgeBase(
    id: JsonSafe.asString(json['id']),
    name: JsonSafe.asString(json['name']),
    description: JsonSafe.asString(json['description']),
    isActive: JsonSafe.asBool(json['is_active'], fallback: true),
    sourceCount: JsonSafe.asInt(json['source_count']),
    readySourceCount: JsonSafe.asInt(json['ready_source_count']),
    createdByName: JsonSafe.asString(json['created_by_name']),
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
  );
}

/// `SourceTypeEnum`.
class KnowledgeSourceType {
  const KnowledgeSourceType._();

  /// Needs `question` and `answer`; `title` is optional.
  static const manualQa = 'MANUAL_QA';

  /// Needs `title` and `body`.
  static const plainText = 'PLAIN_TEXT';
}

/// `KnowledgeSourceStatusEnum`. Read-only: only indexing moves it.
class KnowledgeSourceStatus {
  const KnowledgeSourceStatus._();
  static const pending = 'PENDING';
  static const indexing = 'INDEXING';
  static const ready = 'READY';
  static const failed = 'FAILED';
}

class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.knowledgeBaseId,
    required this.sourceType,
    required this.status,
    this.title = '',
    this.displayTitle = '',
    this.question = '',
    this.answer = '',
    this.body = '',
    this.attempts = 0,
    this.errorCode = '',
    this.errorDetail = '',
    this.chunkCount = 0,
    this.createdByName = '',
    this.indexedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String knowledgeBaseId;
  final String sourceType;
  final String status;
  final String title;

  /// The server's own label for the row: the title, or the question of a
  /// Q&A without one.
  final String displayTitle;
  final String question;
  final String answer;
  final String body;
  final int attempts;
  final String errorCode;
  final String errorDetail;

  /// Live chunks only — a superseded generation is not counted.
  final int chunkCount;
  final String createdByName;
  final DateTime? indexedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isQa => sourceType == KnowledgeSourceType.manualQa;

  /// Still being processed server-side, so its status will change without
  /// anyone touching it — the list keeps re-reading while any row is.
  bool get isInFlight =>
      status == KnowledgeSourceStatus.pending ||
      status == KnowledgeSourceStatus.indexing;

  /// What to call the row: the server's label, else whatever text it has.
  String get label => displayTitle.isNotEmpty
      ? displayTitle
      : (title.isNotEmpty ? title : question);

  factory KnowledgeSource.fromJson(Map<String, dynamic> json) =>
      KnowledgeSource(
        id: JsonSafe.asString(json['id']),
        knowledgeBaseId: JsonSafe.asString(json['knowledge_base_id']),
        sourceType: JsonSafe.asString(json['source_type']),
        status: JsonSafe.asString(
          json['status'],
          fallback: KnowledgeSourceStatus.pending,
        ),
        title: JsonSafe.asString(json['title']),
        displayTitle: JsonSafe.asString(json['display_title']),
        question: JsonSafe.asString(json['question']),
        answer: JsonSafe.asString(json['answer']),
        body: JsonSafe.asString(json['body']),
        attempts: JsonSafe.asInt(json['attempts']),
        errorCode: JsonSafe.asString(json['error_code']),
        errorDetail: JsonSafe.asString(json['error_detail']),
        chunkCount: JsonSafe.asInt(json['chunk_count']),
        createdByName: JsonSafe.asString(json['created_by_name']),
        indexedAt: _date(json['indexed_at']),
        createdAt: _date(json['created_at']),
        updatedAt: _date(json['updated_at']),
      );
}

// --------------------------------------------------------------------------- //
// Playground
// --------------------------------------------------------------------------- //

/// `PlaygroundResponse.status`. Read it before anything else in the answer.
class PlaygroundStatus {
  const PlaygroundStatus._();

  /// Supported by the knowledge base; always carries at least one citation.
  static const answered = 'ANSWERED';

  /// A correct outcome, not an error: the base does not support an answer.
  static const notInKb = 'NOT_IN_KB';

  /// The provider could not be reached or returned something unusable.
  static const error = 'ERROR';

  /// Not in the playground's documented set, but the web client handles it
  /// (two sources disagree), so a backend that sends it is shown it rather
  /// than treated as unknown.
  static const conflictingKnowledge = 'CONFLICTING_KNOWLEDGE';
}

/// Where one statement in an answer came from.
class KnowledgeCitation {
  const KnowledgeCitation({
    required this.sourceId,
    required this.sourceTitle,
    required this.sourceType,
    required this.chunkId,
    required this.rank,
    required this.score,
  });

  final String sourceId;
  final String sourceTitle;
  final String sourceType;
  final String chunkId;
  final int rank;
  final double score;

  factory KnowledgeCitation.fromJson(Map<String, dynamic> json) =>
      KnowledgeCitation(
        sourceId: JsonSafe.asString(json['source_id']),
        sourceTitle: JsonSafe.asString(json['source_title']),
        sourceType: JsonSafe.asString(json['source_type']),
        chunkId: JsonSafe.asString(json['chunk_id']),
        rank: JsonSafe.asInt(json['rank']),
        score: JsonSafe.asDouble(json['score']),
      );
}

/// A retrieval candidate, for diagnostics. Carries the chunk text, which the
/// citations deliberately do not.
class RetrievedChunk {
  const RetrievedChunk({
    required this.chunkId,
    required this.rank,
    required this.score,
    required this.text,
    required this.sourceTitle,
    this.chunkIndex = 0,
    this.sourceId = '',
    this.sourceType = '',
  });

  final String chunkId;
  final int rank;
  final double score;
  final int chunkIndex;
  final String text;
  final String sourceId;
  final String sourceTitle;
  final String sourceType;

  factory RetrievedChunk.fromJson(Map<String, dynamic> json) => RetrievedChunk(
    chunkId: JsonSafe.asString(json['chunk_id']),
    rank: JsonSafe.asInt(json['rank']),
    score: JsonSafe.asDouble(json['score']),
    chunkIndex: JsonSafe.asInt(json['chunk_index']),
    text: JsonSafe.asString(json['text']),
    sourceId: JsonSafe.asString(json['source_id']),
    sourceTitle: JsonSafe.asString(json['source_title']),
    sourceType: JsonSafe.asString(json['source_type']),
  );
}

class PlaygroundAnswer {
  const PlaygroundAnswer({
    required this.status,
    this.answer = '',
    this.citations = const [],
    this.retrieved = const [],
    this.model = '',
    this.provider = '',
    this.policyVersion = '',
    this.durationMs = 0,
    this.retrievalMs = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedTokens = 0,
    this.totalTokens = 0,
    this.errorCode = '',
    this.errorDetail = '',
    this.conflictReason = '',
  });

  final String status;
  final String answer;
  final List<KnowledgeCitation> citations;
  final List<RetrievedChunk> retrieved;
  final String model;
  final String provider;
  final String policyVersion;
  final int durationMs;
  final int retrievalMs;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  final int totalTokens;
  final String errorCode;
  final String errorDetail;
  final String conflictReason;

  factory PlaygroundAnswer.fromJson(Map<String, dynamic> json) =>
      PlaygroundAnswer(
        status: JsonSafe.asString(json['status']),
        answer: JsonSafe.asString(json['answer']),
        citations: JsonSafe.parseList(
          json['citations'],
          KnowledgeCitation.fromJson,
        ),
        retrieved: JsonSafe.parseList(
          json['retrieved'],
          RetrievedChunk.fromJson,
        ),
        model: JsonSafe.asString(json['model']),
        provider: JsonSafe.asString(json['provider']),
        policyVersion: JsonSafe.asString(json['policy_version']),
        durationMs: JsonSafe.asInt(json['duration_ms']),
        retrievalMs: JsonSafe.asInt(json['retrieval_ms']),
        inputTokens: JsonSafe.asInt(json['input_tokens']),
        outputTokens: JsonSafe.asInt(json['output_tokens']),
        cachedTokens: JsonSafe.asInt(json['cached_tokens']),
        totalTokens: JsonSafe.asInt(json['total_tokens']),
        errorCode: JsonSafe.asString(json['error_code']),
        errorDetail: JsonSafe.asString(json['error_detail']),
        conflictReason: JsonSafe.asString(json['conflict_reason']),
      );
}

// --------------------------------------------------------------------------- //
// Agent Assist, readiness, usage, conflicts
// --------------------------------------------------------------------------- //

/// `AIAgentSettingUpdateModeEnum` — the only three modes there are.
class AiAssistMode {
  const AiAssistMode._();
  static const off = 'OFF';
  static const suggest = 'SUGGEST';
  static const auto = 'AUTO';
}

/// Whether one connection is fit for each mode, and why not.
///
/// [blocking] and [warnings] are machine-readable codes the interface
/// translates — see `aiReadinessReason`.
class AiReadiness {
  const AiReadiness({
    required this.connectionId,
    this.provider = '',
    this.state = 'NOT_READY',
    this.suggestAllowed = false,
    this.autoAllowed = false,
    this.blocking = const [],
    this.warnings = const [],
    this.detail = const {},
  });

  final int connectionId;
  final String provider;

  /// `NOT_READY`, `READY_FOR_SUGGEST` or `READY_FOR_AUTO`.
  final String state;
  final bool suggestAllowed;
  final bool autoAllowed;
  final List<String> blocking;
  final List<String> warnings;
  final Map<String, dynamic> detail;

  /// Codes that block `AUTO` only. Free-form `detail`, read the way the web
  /// client reads it.
  List<String> get autoBlocking =>
      JsonSafe.asStringList(detail['auto_blocking']);

  /// Sources indexed and searchable extracts, when the server reported them.
  int? get sourcesReady => JsonSafe.asIntOrNull(detail['sources_ready']);
  int? get embeddedChunks => JsonSafe.asIntOrNull(detail['embedded_chunks']);

  factory AiReadiness.fromJson(Map<String, dynamic> json) => AiReadiness(
    connectionId: JsonSafe.asInt(json['connection_id'], fallback: -1),
    provider: JsonSafe.asString(json['provider']),
    state: JsonSafe.asString(json['state'], fallback: 'NOT_READY'),
    suggestAllowed: JsonSafe.asBool(json['suggest_allowed']),
    autoAllowed: JsonSafe.asBool(json['auto_allowed']),
    blocking: JsonSafe.asStringList(json['blocking']),
    warnings: JsonSafe.asStringList(json['warnings']),
    detail: JsonSafe.asMap(json['detail']),
  );
}

/// One channel connection and its AI mode. A connection with no stored
/// setting reads `OFF`.
class AiAgentSetting {
  const AiAgentSetting({
    required this.connectionId,
    required this.connectionName,
    required this.provider,
    this.status = '',
    this.mode = AiAssistMode.off,
    this.assistSupported = false,
    this.readiness,
  });

  final int connectionId;
  final String connectionName;
  final String provider;
  final String status;
  final String mode;
  final bool assistSupported;

  /// Embedded by the backend when it sends it, else joined from
  /// `GET /ai/readiness/`. Null when neither said — then nothing beyond the
  /// current mode and `OFF` is offered.
  final AiReadiness? readiness;

  /// The modes to offer: `OFF` always, the others only when readiness allows
  /// them — or when the connection is already in that mode, so the current
  /// state is always visible. The server refuses the rest regardless.
  List<String> get offeredModes => [
    AiAssistMode.off,
    if ((readiness?.suggestAllowed ?? false) || mode == AiAssistMode.suggest)
      AiAssistMode.suggest,
    if ((readiness?.autoAllowed ?? false) || mode == AiAssistMode.auto)
      AiAssistMode.auto,
  ];

  AiAgentSetting withReadiness(AiReadiness? value) => AiAgentSetting(
    connectionId: connectionId,
    connectionName: connectionName,
    provider: provider,
    status: status,
    mode: mode,
    assistSupported: assistSupported,
    readiness: value,
  );

  factory AiAgentSetting.fromJson(Map<String, dynamic> json) => AiAgentSetting(
    connectionId: JsonSafe.asInt(json['connection_id'], fallback: -1),
    connectionName: JsonSafe.asString(json['connection_name']),
    provider: JsonSafe.asString(json['provider']),
    status: JsonSafe.asString(json['status']),
    mode: JsonSafe.asString(json['mode'], fallback: AiAssistMode.off),
    assistSupported: JsonSafe.asBool(json['assist_supported']),
    readiness: json['readiness'] is Map
        ? AiReadiness.fromJson(JsonSafe.asMap(json['readiness']))
        : null,
  );
}

/// Aggregated AI spend. Not billing, and no content.
class AiUsageSummary {
  const AiUsageSummary({
    this.requests = 0,
    this.totalTokens = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.answered = 0,
    this.notInKb = 0,
    this.errors = 0,
    this.byModel = const {},
    this.since,
  });

  final int requests;
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int answered;
  final int notInKb;
  final int errors;
  final Map<String, int> byModel;
  final DateTime? since;

  factory AiUsageSummary.fromJson(Map<String, dynamic> json) => AiUsageSummary(
    requests: JsonSafe.asInt(json['requests']),
    totalTokens: JsonSafe.asInt(json['total_tokens']),
    inputTokens: JsonSafe.asInt(json['input_tokens']),
    outputTokens: JsonSafe.asInt(json['output_tokens']),
    answered: JsonSafe.asInt(json['answered']),
    notInKb: JsonSafe.asInt(json['not_in_kb']),
    errors: JsonSafe.asInt(json['errors']),
    byModel: {
      for (final entry in JsonSafe.asMap(json['by_model']).entries)
        entry.key: JsonSafe.asInt(entry.value),
    },
    since: _date(json['since']),
  );
}

/// Two (or more) active sources that answer the same question differently.
class KnowledgeConflict {
  const KnowledgeConflict({required this.sources, required this.reason});

  final List<String> sources;
  final String reason;

  factory KnowledgeConflict.fromJson(Map<String, dynamic> json) =>
      KnowledgeConflict(
        sources: JsonSafe.asStringList(json['sources']),
        reason: JsonSafe.asString(json['reason']),
      );
}
