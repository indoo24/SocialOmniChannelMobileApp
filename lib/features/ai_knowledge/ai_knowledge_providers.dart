/// State for the AI & Knowledge settings tab.
///
/// Every provider here is `autoDispose`: the data is organization
/// configuration only that tab shows, so it is read fresh each time the tab
/// opens and never outlives it (or the session).
///
/// Mutations wait for the server and show its answer — a source is never
/// marked ready because a request was accepted. Sources the server is still
/// indexing are re-read every [KnowledgeSourcesController.pollInterval] until
/// none is, the same cadence the web client polls at.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/ai_operations.dart';
import '../../core/models/knowledge.dart';
import '../../core/providers.dart';
import 'ai_knowledge_repository.dart';

final aiKnowledgeRepositoryProvider = Provider<AiKnowledgeRepository>(
  (ref) => AiKnowledgeRepository(ref.watch(apiClientProvider)),
);

// --------------------------------------------------------------------------- //
// Knowledge bases
// --------------------------------------------------------------------------- //

class KnowledgeBasesController extends AsyncNotifier<List<KnowledgeBase>> {
  @override
  Future<List<KnowledgeBase>> build() =>
      ref.watch(aiKnowledgeRepositoryProvider).knowledgeBases();

  AiKnowledgeRepository get _repository =>
      ref.read(aiKnowledgeRepositoryProvider);

  List<KnowledgeBase> get _current => state.value ?? const [];

  /// Creates a base and selects it, as the web client does.
  Future<KnowledgeBase> create({
    required String name,
    String description = '',
  }) async {
    final created = await _repository.createKnowledgeBase(
      name: name,
      description: description,
    );
    if (!ref.mounted) return created;
    state = AsyncData([..._current, created]);
    ref.read(selectedKnowledgeBaseIdProvider.notifier).select(created.id);
    return created;
  }

  Future<void> edit(String id, {String? name, String? description}) async {
    final updated = await _repository.updateKnowledgeBase(
      id,
      name: name,
      description: description,
    );
    _replace(updated);
  }

  Future<void> setActive(String id, {required bool isActive}) async {
    final updated = await _repository.updateKnowledgeBase(
      id,
      isActive: isActive,
    );
    _replace(updated);
  }

  Future<void> delete(String id) async {
    await _repository.deleteKnowledgeBase(id);
    if (!ref.mounted) return;
    state = AsyncData([
      for (final base in _current)
        if (base.id != id) base,
    ]);
  }

  void _replace(KnowledgeBase updated) {
    if (!ref.mounted) return;
    state = AsyncData([
      for (final base in _current) base.id == updated.id ? updated : base,
    ]);
  }
}

final knowledgeBasesProvider =
    AsyncNotifierProvider.autoDispose<
      KnowledgeBasesController,
      List<KnowledgeBase>
    >(KnowledgeBasesController.new);

/// The base the person picked. May name one that no longer exists — read
/// [selectedKnowledgeBaseProvider] instead, which falls back to the first.
class SelectedKnowledgeBaseIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

final selectedKnowledgeBaseIdProvider =
    NotifierProvider.autoDispose<SelectedKnowledgeBaseIdController, String?>(
      SelectedKnowledgeBaseIdController.new,
    );

/// The base the Knowledge and playground sections work on: the selected
/// one, else the first. Null while loading or when there is none.
final selectedKnowledgeBaseProvider = Provider.autoDispose<KnowledgeBase?>((
  ref,
) {
  final bases = ref.watch(knowledgeBasesProvider).value;
  if (bases == null || bases.isEmpty) return null;
  final id = ref.watch(selectedKnowledgeBaseIdProvider);
  for (final base in bases) {
    if (base.id == id) return base;
  }
  return bases.first;
});

// --------------------------------------------------------------------------- //
// Sources
// --------------------------------------------------------------------------- //

/// One base's sources, re-read while any of them is still being indexed.
class KnowledgeSourcesController extends AsyncNotifier<List<KnowledgeSource>> {
  KnowledgeSourcesController(this.knowledgeBaseId);

  final String knowledgeBaseId;

  static const pollInterval = Duration(seconds: 2);

  Timer? _poll;

  AiKnowledgeRepository get _repository =>
      ref.read(aiKnowledgeRepositoryProvider);

  @override
  Future<List<KnowledgeSource>> build() async {
    ref.onDispose(() => _poll?.cancel());
    final sources = await ref
        .watch(aiKnowledgeRepositoryProvider)
        .sources(knowledgeBaseId);
    _schedulePoll(sources);
    return sources;
  }

  void _schedulePoll(List<KnowledgeSource> sources) {
    _poll?.cancel();
    _poll = sources.any((s) => s.isInFlight)
        ? Timer(pollInterval, _pollOnce)
        : null;
  }

  Future<void> _pollOnce() async {
    if (!ref.mounted) return;
    final before = state.value ?? const <KnowledgeSource>[];
    try {
      final sources = await _repository.sources(knowledgeBaseId);
      if (!ref.mounted) return;
      state = AsyncData(sources);
      // A source that finished changes its base's ready count.
      if (before.where((s) => s.isInFlight).length !=
          sources.where((s) => s.isInFlight).length) {
        ref.invalidate(knowledgeBasesProvider);
      }
      _schedulePoll(sources);
    } on ApiException catch (error) {
      if (!ref.mounted) return;
      // A refusal will not change by asking again; a dropped connection may.
      final retryable = error is NetworkException || error.statusCode >= 500;
      if (retryable) _schedulePoll(before);
    }
  }

  /// Re-reads the list after a change. If even that fails the change still
  /// happened, so the provider is reset to load again rather than keep
  /// showing the list from before it.
  Future<void> _reload() async {
    try {
      final sources = await _repository.sources(knowledgeBaseId);
      if (!ref.mounted) return;
      state = AsyncData(sources);
      _schedulePoll(sources);
    } on ApiException {
      if (ref.mounted) ref.invalidateSelf();
    }
  }

  Future<KnowledgeSource> create({
    required String sourceType,
    String title = '',
    String question = '',
    String answer = '',
    String body = '',
  }) async {
    final created = await _repository.createSource(
      knowledgeBaseId: knowledgeBaseId,
      sourceType: sourceType,
      title: title,
      question: question,
      answer: answer,
      body: body,
    );
    if (!ref.mounted) return created;
    ref.invalidate(knowledgeBasesProvider);
    await _reload();
    return created;
  }

  Future<KnowledgeSource> edit(
    KnowledgeSource source, {
    String title = '',
    String question = '',
    String answer = '',
    String body = '',
  }) async {
    final updated = await _repository.updateSource(
      source.id,
      sourceType: source.sourceType,
      title: title,
      question: question,
      answer: answer,
      body: body,
    );
    if (!ref.mounted) return updated;
    ref.invalidate(knowledgeBasesProvider);
    await _reload();
    return updated;
  }

  Future<void> delete(String id) async {
    await _repository.deleteSource(id);
    if (!ref.mounted) return;
    ref.invalidate(knowledgeBasesProvider);
    await _reload();
  }

  /// Shows the status the server answered with (usually `PENDING`) and
  /// follows it until indexing settles.
  Future<void> reindex(String id) async {
    final queued = await _repository.reindexSource(id);
    if (!ref.mounted) return;
    final sources = [
      for (final s in state.value ?? const <KnowledgeSource>[])
        s.id == id ? queued : s,
    ];
    state = AsyncData(sources);
    ref.invalidate(knowledgeBasesProvider);
    _schedulePoll(sources);
  }
}

final knowledgeSourcesProvider = AsyncNotifierProvider.autoDispose
    .family<KnowledgeSourcesController, List<KnowledgeSource>, String>(
      KnowledgeSourcesController.new,
    );

// --------------------------------------------------------------------------- //
// Playground
// --------------------------------------------------------------------------- //

/// Why a question cannot be sent as typed.
enum PlaygroundQuestionError { empty, tooLong }

class PlaygroundState {
  const PlaygroundState({
    this.asking = false,
    this.result,
    this.error,
    this.knowledgeBaseId,
    this.question = '',
  });

  /// A question is in flight; another is refused until it returns.
  final bool asking;

  /// The server's answer to the last question that got one.
  final PlaygroundAnswer? result;

  /// The last question's failure (an [ApiException]), if it had one.
  final Object? error;

  /// The base the last question was asked of, so an answer is only ever
  /// shown next to the base it came from.
  final String? knowledgeBaseId;
  final String question;
}

class PlaygroundController extends Notifier<PlaygroundState> {
  @override
  PlaygroundState build() => const PlaygroundState();

  /// Null when [question] can be sent. Length is counted in code points,
  /// which is how the server counts its 1000-character limit.
  static PlaygroundQuestionError? validate(String question) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return PlaygroundQuestionError.empty;
    if (trimmed.runes.length > AiKnowledgeRepository.maxQuestionLength) {
      return PlaygroundQuestionError.tooLong;
    }
    return null;
  }

  /// Asks [question] of the base [knowledgeBaseId]. Resolves to false
  /// without sending anything while a question is already in flight, or
  /// when the question or base is not valid — the guard against a double
  /// tap spending two of the 30 questions a minute.
  ///
  /// Nothing here creates a conversation or a message: the playground
  /// endpoint is the only call made.
  Future<bool> ask({
    required String knowledgeBaseId,
    required String question,
  }) async {
    if (state.asking) return false;
    if (knowledgeBaseId.isEmpty || validate(question) != null) return false;
    final trimmed = question.trim();

    state = PlaygroundState(
      asking: true,
      knowledgeBaseId: knowledgeBaseId,
      question: trimmed,
    );
    try {
      final result = await ref
          .read(aiKnowledgeRepositoryProvider)
          .ask(knowledgeBaseId: knowledgeBaseId, question: trimmed);
      if (!ref.mounted) return true;
      state = PlaygroundState(
        result: result,
        knowledgeBaseId: knowledgeBaseId,
        question: trimmed,
      );
      // Every question counts towards usage.
      ref.invalidate(aiUsageProvider);
    } on ApiException catch (error) {
      if (!ref.mounted) return true;
      state = PlaygroundState(
        error: error,
        knowledgeBaseId: knowledgeBaseId,
        question: trimmed,
      );
      // The base is gone (deleted elsewhere) or out of reach: re-read the
      // list so it stops being offered.
      if (error.isNotFound) ref.invalidate(knowledgeBasesProvider);
    }
    return true;
  }
}

final playgroundControllerProvider =
    NotifierProvider.autoDispose<PlaygroundController, PlaygroundState>(
      PlaygroundController.new,
    );

// --------------------------------------------------------------------------- //
// Agent Assist, conflicts, usage
// --------------------------------------------------------------------------- //

class AgentSettingsController extends AsyncNotifier<List<AiAgentSetting>> {
  @override
  Future<List<AiAgentSetting>> build() =>
      ref.watch(aiKnowledgeRepositoryProvider).agentSettings();

  /// Sets [connectionId] to [mode] and shows every connection as the server
  /// answers. Throws on refusal (a 400 for a mode readiness does not allow),
  /// leaving the list as it was.
  Future<void> setMode(int connectionId, String mode) =>
      updateSettings(connectionId, {'mode': mode});

  /// Saves [changes] to one connection's AI configuration (only those
  /// fields) and shows every connection as the server answers. Throws on
  /// refusal, leaving the list as it was.
  Future<void> updateSettings(
    int connectionId,
    Map<String, Object> changes,
  ) async {
    final previous = {
      for (final row in state.value ?? const <AiAgentSetting>[])
        row.connectionId: row.readiness,
    };
    final updated = await ref
        .read(aiKnowledgeRepositoryProvider)
        .updateAgentSetting(connectionId: connectionId, changes: changes);
    if (!ref.mounted) return;
    // A settings change does not change readiness; keep what was known.
    state = AsyncData([
      for (final row in updated)
        row.readiness != null
            ? row
            : row.withReadiness(previous[row.connectionId]),
    ]);
  }
}

final agentSettingsProvider =
    AsyncNotifierProvider.autoDispose<
      AgentSettingsController,
      List<AiAgentSetting>
    >(AgentSettingsController.new);

final knowledgeConflictsProvider =
    FutureProvider.autoDispose<List<KnowledgeConflict>>(
      (ref) => ref.watch(aiKnowledgeRepositoryProvider).conflicts(),
    );

/// The last 30 days — the window the web client shows.
final aiUsageProvider = FutureProvider.autoDispose<AiUsageSummary>(
  (ref) => ref.watch(aiKnowledgeRepositoryProvider).usage(),
);

// --------------------------------------------------------------------------- //
// Activity and policy
// --------------------------------------------------------------------------- //

/// The AI activity windows offered, in hours — the web's three.
const aiActivityWindows = [1, 24, 168];

/// The activity window on screen. 24 hours to start, the server's default.
class AiActivityWindowController extends Notifier<int> {
  @override
  int build() => 24;

  void select(int hours) => state = hours;
}

final aiActivityWindowProvider =
    NotifierProvider.autoDispose<AiActivityWindowController, int>(
      AiActivityWindowController.new,
    );

/// Organization-wide AI activity for one window, by its hours.
final aiMetricsProvider = FutureProvider.autoDispose.family<AiMetrics, int>(
  (ref, hours) =>
      ref.watch(aiKnowledgeRepositoryProvider).metrics(hours: hours),
);

/// The organization's AI policy, and saving it.
class AiPolicyController extends AsyncNotifier<AiOrganizationPolicy> {
  @override
  Future<AiOrganizationPolicy> build() =>
      ref.watch(aiKnowledgeRepositoryProvider).policy();

  /// Saves [changes] and shows the policy as the server answers. Throws on
  /// refusal (400 with the field that was out of range), leaving the policy
  /// as it was. Nothing is sent when there is nothing to change.
  Future<void> save(Map<String, Object> changes) async {
    if (changes.isEmpty) return;
    final saved = await ref
        .read(aiKnowledgeRepositoryProvider)
        .updatePolicy(changes);
    if (!ref.mounted) return;
    state = AsyncData(saved);
    // The organization switches feed every channel's readiness.
    ref.invalidate(agentSettingsProvider);
  }
}

final aiPolicyProvider =
    AsyncNotifierProvider.autoDispose<AiPolicyController, AiOrganizationPolicy>(
      AiPolicyController.new,
    );
