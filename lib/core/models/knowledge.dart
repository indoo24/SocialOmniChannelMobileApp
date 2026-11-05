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

/// `GroundingProfileEnum`: how much supporting evidence an automatic reply
/// needs.
class AiGroundingProfile {
  const AiGroundingProfile._();
  static const strict = 'STRICT';
  static const balanced = 'BALANCED';
  static const flexible = 'FLEXIBLE';
  static const values = [strict, balanced, flexible];
}

/// `ResumeBehaviourEnum`: what the AI does when it is allowed back into a
/// conversation.
class AiResumeBehaviour {
  const AiResumeBehaviour._();
  static const ask = 'ASK';
  static const wait = 'WAIT';
  static const values = [ask, wait];
}

/// One reason a conversation is handed to a person.
///
/// [locked] rules are always on. The one rule that is not — handing off a
/// restricted topic — is switched with `handoff_on_restricted_topic`.
/// The item shape (`reason`, `why`, `locked`, `enabled`) is not spelled out
/// in the schema (`handoff_rules` is a list of free-form objects); it is the
/// one the web client reads.
class AiHandoffRule {
  const AiHandoffRule({
    required this.reason,
    this.why = '',
    this.locked = true,
    this.enabled = true,
  });

  final String reason;
  final String why;
  final bool locked;
  final bool enabled;

  factory AiHandoffRule.fromJson(Map<String, dynamic> json) {
    final reason = JsonSafe.asString(json['reason']);
    if (reason.isEmpty) throw const FormatException('handoff rule: reason');
    return AiHandoffRule(
      reason: reason,
      why: JsonSafe.asString(json['why']),
      // An unreadable flag reads as locked: never offer a switch the server
      // did not say exists.
      locked: JsonSafe.asBool(json['locked'], fallback: true),
      enabled: JsonSafe.asBool(json['enabled'], fallback: true),
    );
  }
}

/// One channel connection, its AI mode, and the limits automatic replies
/// work within. A connection with no stored setting reads `OFF`.
///
/// The limits are null when the server did not send them (an older backend):
/// the channel settings are then not offered rather than shown with guessed
/// values.
class AiAgentSetting {
  const AiAgentSetting({
    required this.connectionId,
    required this.connectionName,
    required this.provider,
    this.status = '',
    this.mode = AiAssistMode.off,
    this.assistSupported = false,
    this.readiness,
    this.maxAutoTurns,
    this.autoSessionIdleHours,
    this.dailyAutoSendLimit,
    this.groundingProfile = '',
    this.groundingFloor,
    this.resumeBehaviour = '',
    this.extraRestrictedTopics = const [],
    this.lockedRestrictedTopics = const [],
    this.handoffRules = const [],
  });

  /// `AIAgentSettingUpdate`'s bounds. There is no "unlimited".
  static const maxAutoTurnsRange = (min: 1, max: 50);
  static const autoSessionIdleHoursRange = (min: 1, max: 72);
  static const dailyAutoSendLimitRange = (min: 1, max: 1000);
  static const maxRestrictedTopics = 50;
  static const maxRestrictedTopicLength = 60;

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

  /// Automatic replies in one session before a person takes over.
  final int? maxAutoTurns;

  /// Hours of customer silence after which a new AI session starts.
  final int? autoSessionIdleHours;

  /// Automatic replies this channel may send in a day.
  final int? dailyAutoSendLimit;
  final String groundingProfile;

  /// The evidence threshold the profile currently means. Read-only.
  final double? groundingFloor;
  final String resumeBehaviour;

  /// Topics this business adds to the always-on ones; editable.
  final List<String> extraRestrictedTopics;

  /// Built-in safety topics; always on, never editable.
  final List<String> lockedRestrictedTopics;
  final List<AiHandoffRule> handoffRules;

  /// Whether the server sent this channel's limits at all.
  bool get hasChannelConfig =>
      maxAutoTurns != null &&
      autoSessionIdleHours != null &&
      dailyAutoSendLimit != null;

  /// The one switchable handoff rule's state — what
  /// `handoff_on_restricted_topic` sets. Null when there is no such rule.
  bool? get handoffOnRestrictedTopic {
    for (final rule in handoffRules) {
      if (!rule.locked) return rule.enabled;
    }
    return null;
  }

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
    maxAutoTurns: maxAutoTurns,
    autoSessionIdleHours: autoSessionIdleHours,
    dailyAutoSendLimit: dailyAutoSendLimit,
    groundingProfile: groundingProfile,
    groundingFloor: groundingFloor,
    resumeBehaviour: resumeBehaviour,
    extraRestrictedTopics: extraRestrictedTopics,
    lockedRestrictedTopics: lockedRestrictedTopics,
    handoffRules: handoffRules,
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
    maxAutoTurns: JsonSafe.asIntOrNull(json['max_auto_turns']),
    autoSessionIdleHours: JsonSafe.asIntOrNull(json['auto_session_idle_hours']),
    dailyAutoSendLimit: JsonSafe.asIntOrNull(json['daily_auto_send_limit']),
    groundingProfile: JsonSafe.asString(json['grounding_profile']),
    groundingFloor: JsonSafe.asDoubleOrNull(json['grounding_floor']),
    resumeBehaviour: JsonSafe.asString(json['resume_behaviour']),
    extraRestrictedTopics: JsonSafe.asStringList(
      json['extra_restricted_topics'],
    ),
    lockedRestrictedTopics: JsonSafe.asStringList(
      json['locked_restricted_topics'],
    ),
    handoffRules: JsonSafe.parseList(
      json['handoff_rules'],
      AiHandoffRule.fromJson,
    ),
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
