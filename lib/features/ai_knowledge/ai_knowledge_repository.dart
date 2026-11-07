/// AI knowledge endpoints — knowledge bases, sources, the playground, and
/// Agent Assist.
///
/// Every route here is from the backend's OpenAPI schema; the request bodies
/// match what the web client sends:
///
/// * `GET/POST /knowledge-bases/`, `PATCH/DELETE /knowledge-bases/{id}/`
/// * `GET/POST /knowledge-sources/` (`?knowledge_base=` filters),
///   `PATCH/DELETE /knowledge-sources/{id}/`,
///   `POST /knowledge-sources/{id}/reindex/`
/// * `POST /ai/playground/ask/`
/// * `GET/PUT /ai/agent-settings/`, `GET /ai/readiness/`,
///   `GET /ai/conflicts/`, `GET /ai/usage/`
/// * `GET /ai/metrics/`, `GET/PUT /ai/policy/`, `GET /ai/history/`
///
/// All need `ai_knowledge.manage`, and the organization must be in the AI
/// pilot — outside it every one answers 404.
library;

import '../../core/api/api_client.dart';
import '../../core/models/ai_operations.dart';
import '../../core/models/conversation.dart' show Paginated;
import '../../core/models/knowledge.dart';
import '../../core/utils/json_safe.dart';

class AiKnowledgeRepository {
  const AiKnowledgeRepository(this._api);

  final ApiClient _api;

  /// The playground's question limit, in characters as the server counts
  /// them (code points, not UTF-16 units).
  static const maxQuestionLength = 1000;

  /// `KnowledgeBase.name`'s and `KnowledgeSource.title`'s max lengths.
  static const maxBaseNameLength = 160;
  static const maxSourceTitleLength = 200;

  /// Pages are walked rather than trusting one page to hold everything; the
  /// cap only stops a misbehaving `next` from looping forever.
  static const _pageSize = 100;
  static const _maxPages = 50;

  Future<List<T>> _allPages<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic> query = const {},
  }) async {
    final results = <T>[];
    for (var page = 1; page <= _maxPages; page++) {
      final data = await _api.get<Map<String, dynamic>>(
        path,
        query: {...query, 'page': page, 'page_size': _pageSize},
      );
      final parsed = Paginated<T>.fromJson(data, parse);
      results.addAll(parsed.results);
      if (!parsed.hasMore) break;
    }
    return results;
  }

  // -- knowledge bases --------------------------------------------------------

  Future<List<KnowledgeBase>> knowledgeBases() =>
      _allPages('/knowledge-bases/', KnowledgeBase.fromJson);

  Future<KnowledgeBase> createKnowledgeBase({
    required String name,
    String description = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/knowledge-bases/',
      body: {
        'name': name,
        if (description.isNotEmpty) 'description': description,
      },
    );
    return KnowledgeBase.fromJson(data);
  }

  /// Rename, describe, activate or deactivate. Only the fields given are
  /// sent.
  Future<KnowledgeBase> updateKnowledgeBase(
    String id, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/knowledge-bases/$id/',
      body: {
        'name': ?name,
        'description': ?description,
        'is_active': ?isActive,
      },
    );
    return KnowledgeBase.fromJson(data);
  }

  /// Deletes its sources and their chunks with it (204).
  Future<void> deleteKnowledgeBase(String id) =>
      _api.delete<dynamic>('/knowledge-bases/$id/');

  // -- sources ---------------------------------------------------------------

  Future<List<KnowledgeSource>> sources(String knowledgeBaseId) => _allPages(
    '/knowledge-sources/',
    KnowledgeSource.fromJson,
    query: {'knowledge_base': knowledgeBaseId},
  );

  /// Comes back `PENDING`; indexing is queued after the response.
  ///
  /// `knowledge_base_id` is marked read-only in the schema, but it is what
  /// the web client sends on create and the only way to say which base the
  /// source belongs to.
  Future<KnowledgeSource> createSource({
    required String knowledgeBaseId,
    required String sourceType,
    String title = '',
    String question = '',
    String answer = '',
    String body = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/knowledge-sources/',
      body: {
        'knowledge_base_id': knowledgeBaseId,
        'source_type': sourceType,
        ..._content(sourceType, title, question, answer, body),
      },
    );
    return KnowledgeSource.fromJson(data);
  }

  /// Re-indexes server-side when the content changes; the old chunks keep
  /// serving until the new ones are embedded.
  Future<KnowledgeSource> updateSource(
    String id, {
    required String sourceType,
    String title = '',
    String question = '',
    String answer = '',
    String body = '',
  }) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/knowledge-sources/$id/',
      body: _content(sourceType, title, question, answer, body),
    );
    return KnowledgeSource.fromJson(data);
  }

  /// The fields each type carries — the same split the web form sends.
  static Map<String, String> _content(
    String sourceType,
    String title,
    String question,
    String answer,
    String body,
  ) => sourceType == KnowledgeSourceType.manualQa
      ? {'question': question, 'answer': answer, 'title': title}
      : {'title': title, 'body': body};

  /// Its chunks go with it, so it stops being retrievable at once (204).
  Future<void> deleteSource(String id) =>
      _api.delete<dynamic>('/knowledge-sources/$id/');

  /// 202 with the source; the current chunks keep serving meanwhile.
  Future<KnowledgeSource> reindexSource(String id) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/knowledge-sources/$id/reindex/',
      body: const <String, dynamic>{},
    );
    return KnowledgeSource.fromJson(data);
  }

  // -- playground ------------------------------------------------------------

  /// One question against one base. Creates no conversation and no message.
  /// Throttled server-side to 30 a minute.
  Future<PlaygroundAnswer> ask({
    required String knowledgeBaseId,
    required String question,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/ai/playground/ask/',
      body: {'knowledge_base_id': knowledgeBaseId, 'question': question},
    );
    return PlaygroundAnswer.fromJson(data);
  }

  // -- Agent Assist ----------------------------------------------------------

  /// Every connection with its mode. Readiness is taken from the row when
  /// the backend embeds it, otherwise joined from [readiness]; if that read
  /// fails the rows simply carry none.
  Future<List<AiAgentSetting>> agentSettings() async {
    final data = await _api.get<dynamic>('/ai/agent-settings/');
    return _withReadiness(JsonSafe.parseList(data, AiAgentSetting.fromJson));
  }

  /// Sets one connection's mode; answers with every connection after the
  /// change. The server refuses a mode readiness does not allow (400).
  Future<List<AiAgentSetting>> setAgentMode({
    required int connectionId,
    required String mode,
  }) => updateAgentSetting(connectionId: connectionId, changes: {'mode': mode});

  /// Changes some of one connection's AI configuration — only the fields in
  /// [changes], keyed as `AIAgentSettingUpdate` names them (`max_auto_turns`,
  /// `extra_restricted_topics`, ...). Answers with every connection after the
  /// change; out-of-range values are refused with 400.
  Future<List<AiAgentSetting>> updateAgentSetting({
    required int connectionId,
    required Map<String, Object> changes,
  }) async {
    final data = await _api.put<dynamic>(
      '/ai/agent-settings/',
      body: {...changes, 'connection_id': connectionId},
    );
    return _withReadiness(JsonSafe.parseList(data, AiAgentSetting.fromJson));
  }

  Future<List<AiAgentSetting>> _withReadiness(List<AiAgentSetting> rows) async {
    if (rows.every((r) => r.readiness != null)) return rows;
    final List<AiReadiness> checks;
    try {
      checks = await readiness();
    } on Exception {
      return rows;
    }
    final byId = {for (final r in checks) r.connectionId: r};
    return [
      for (final row in rows)
        row.readiness != null ? row : row.withReadiness(byId[row.connectionId]),
    ];
  }

  Future<List<AiReadiness>> readiness() async {
    final data = await _api.get<dynamic>('/ai/readiness/');
    return JsonSafe.parseList(data, AiReadiness.fromJson);
  }

  Future<List<KnowledgeConflict>> conflicts() async {
    final data = await _api.get<dynamic>('/ai/conflicts/');
    return JsonSafe.parseList(data, KnowledgeConflict.fromJson);
  }

  /// [days]: the server's default is 30, its maximum 365.
  Future<AiUsageSummary> usage({int days = 30}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/ai/usage/',
      query: {'days': days},
    );
    return AiUsageSummary.fromJson(data);
  }

  // -- activity and policy ---------------------------------------------------

  /// The server's ceiling on a metrics window.
  static const maxMetricsHours = 720;

  /// AI activity over the last [hours] (clamped to 1–720, the server's
  /// range), for the organization or, with [connectionId], one channel.
  Future<AiMetrics> metrics({required int hours, int? connectionId}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/ai/metrics/',
      query: {
        'hours': hours.clamp(1, maxMetricsHours),
        'connection_id': ?connectionId,
      },
    );
    return AiMetrics.fromJson(data);
  }

  /// The organization's AI policy — the defaults when it was never set.
  Future<AiOrganizationPolicy> policy() async {
    final data = await _api.get<Map<String, dynamic>>('/ai/policy/');
    return AiOrganizationPolicy.fromJson(data);
  }

  /// Sends only [changes] (every field is optional) and answers with the
  /// whole policy as saved. Each change is audited server-side.
  Future<AiOrganizationPolicy> updatePolicy(Map<String, Object> changes) async {
    final data = await _api.put<Map<String, dynamic>>(
      '/ai/policy/',
      body: changes,
    );
    return AiOrganizationPolicy.fromJson(data);
  }

  /// The newest configuration changes, up to [limit] (the server's maximum is
  /// 500). Read-only.
  Future<List<AiConfigurationChange>> history({int limit = 50}) async {
    final data = await _api.get<dynamic>(
      '/ai/history/',
      query: {'limit': limit},
    );
    return JsonSafe.parseList(data, AiConfigurationChange.fromJson);
  }
}
