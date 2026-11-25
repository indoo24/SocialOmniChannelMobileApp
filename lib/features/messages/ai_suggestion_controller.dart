/// AI reply suggestions for one conversation —
/// `POST /api/conversations/{id}/ai-suggestion/`.
///
/// Keyed by conversation id, and auto-disposed with the composer that
/// watches it, so a draft can only ever land in the conversation it was
/// asked for: a response that arrives after its conversation was left is
/// dropped together with this controller.
///
/// Nothing here sends anything. The endpoint itself creates no message and
/// changes nothing about the conversation; the composer puts the draft in
/// the text field and the employee presses Send.
library;

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/logging/app_log.dart';
import '../../core/models/ai_suggestion.dart';
import '../../core/providers.dart';

void _log(String message) => AppLog.debug('AI_SUGGESTION', message);

/// What the suggestion strip above the composer shows.
enum AiSuggestionPhase {
  /// The "AI suggestion" button.
  idle,

  /// A request is out. The button shows progress and takes no more taps.
  loading,

  /// A draft arrived and is not in the composer yet — it is being placed,
  /// or it could not be (the composer was on another tab) and waits to be
  /// used or dismissed.
  ready,

  /// A draft is in the composer.
  placed,

  /// The AI answered without a draft: not in the knowledge base,
  /// conflicting sources, a provider failure, or an empty draft.
  noDraft,

  /// The request failed. Retry is offered.
  failed,

  /// 404: not available for this conversation (not in the AI pilot, the
  /// channel is not in `SUGGEST` mode, or no `conversation.reply`).
  unavailable,

  /// [unavailable], dismissed: the button is no longer offered here.
  hidden,
}

class AiSuggestionState {
  const AiSuggestionState({
    this.phase = AiSuggestionPhase.idle,
    this.suggestion,
    this.errorMessage,
    this.placedSuggestion,
    this.placedText,
    this.retryOf,
  });

  final AiSuggestionPhase phase;

  /// While [AiSuggestionPhase.loading]: the panel being retried —
  /// [AiSuggestionPhase.noDraft] or [AiSuggestionPhase.failed] — which
  /// stays on screen, busy, until the new answer replaces it. Null for a
  /// first request.
  final AiSuggestionPhase? retryOf;

  /// The latest answer not yet in the composer: for
  /// [AiSuggestionPhase.ready] and [AiSuggestionPhase.noDraft], and while a
  /// draft waits to be placed.
  final AiSuggestion? suggestion;

  /// The server's own reason for [AiSuggestionPhase.failed], when it gave
  /// one.
  final String? errorMessage;

  /// The suggestion whose draft is in the composer — its id is sent with
  /// the reply as `suggestion_id`. Kept while other phases come and go (a
  /// failed regenerate does not take the draft out of the composer), and
  /// cleared once the composer is emptied or the reply is sent.
  final AiSuggestion? placedSuggestion;

  String? get placedSuggestionId => placedSuggestion?.suggestionId;

  /// The composer text right after the draft went in. While the composer
  /// still holds exactly this, the employee has not edited it, and a
  /// regenerated draft may replace it without asking.
  final String? placedText;

  bool get isLoading => phase == AiSuggestionPhase.loading;

  /// Retrying a no-draft or failed answer: its panel stays up, busy.
  bool get isRetrying => isLoading && retryOf != null;

  AiSuggestionState copyWith({
    AiSuggestionPhase? phase,
    AiSuggestion? suggestion,
    String? errorMessage,
    AiSuggestionPhase? retryOf,
    bool clearSuggestion = false,
    bool clearError = false,
    bool clearRetryOf = false,
  }) => AiSuggestionState(
    phase: phase ?? this.phase,
    suggestion: clearSuggestion ? null : (suggestion ?? this.suggestion),
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    placedSuggestion: placedSuggestion,
    placedText: placedText,
    retryOf: clearRetryOf ? null : (retryOf ?? this.retryOf),
  );
}

class AiSuggestionController extends Notifier<AiSuggestionState> {
  AiSuggestionController(this.conversationId);

  final int conversationId;

  @override
  AiSuggestionState build() => const AiSuggestionState();

  /// Asks for a draft. Resolves to the suggestion when it carries a draft
  /// the caller may place, and to null otherwise — already loading,
  /// no draft, a failure, or this controller gone (the conversation was
  /// left while the request was out).
  ///
  /// Retrying from a no-draft or failed answer keeps that answer on screen
  /// (busy) until the new one arrives, as the web's suggestion card does.
  Future<AiSuggestion?> request({bool regenerate = false}) async {
    if (state.isLoading || state.phase == AiSuggestionPhase.hidden) {
      return null;
    }
    final from = state.phase;
    final retrying =
        from == AiSuggestionPhase.noDraft || from == AiSuggestionPhase.failed;
    state = state.copyWith(
      phase: AiSuggestionPhase.loading,
      retryOf: retrying ? from : null,
      clearRetryOf: !retrying,
      clearError: !retrying,
      clearSuggestion: !retrying,
    );
    _log('REQUEST conversationId=$conversationId regenerate=$regenerate');
    try {
      final suggestion = await ref
          .read(conversationRepositoryProvider)
          .aiSuggestion(conversationId, regenerate: regenerate);
      if (!ref.mounted) return null;
      _log(
        'RESULT conversationId=$conversationId status=${suggestion.status} '
        'hasDraft=${suggestion.hasDraft} errorCode=${suggestion.errorCode}',
      );
      if (!suggestion.hasDraft) {
        state = state.copyWith(
          phase: AiSuggestionPhase.noDraft,
          suggestion: suggestion,
          clearError: true,
          clearRetryOf: true,
        );
        return null;
      }
      // Ready until the caller places it ([placed]) or the employee turns
      // it down ([declined]); if the caller cannot place it, it waits here
      // to be used or dismissed.
      state = state.copyWith(
        phase: AiSuggestionPhase.ready,
        suggestion: suggestion,
        clearError: true,
        clearRetryOf: true,
      );
      return suggestion;
    } on ApiException catch (error) {
      if (!ref.mounted) return null;
      _log(
        'FAILED conversationId=$conversationId status=${error.statusCode} '
        'code=${error.code}',
      );
      final message = error.message.trim();
      state = error.isNotFound
          ? state.copyWith(
              phase: AiSuggestionPhase.unavailable,
              clearRetryOf: true,
            )
          : state.copyWith(
              phase: AiSuggestionPhase.failed,
              errorMessage: message.isEmpty ? null : message,
              clearError: message.isEmpty,
              clearRetryOf: true,
            );
      return null;
    } catch (error) {
      if (!ref.mounted) return null;
      _log('FAILED conversationId=$conversationId error=$error');
      state = state.copyWith(
        phase: AiSuggestionPhase.failed,
        clearError: true,
        clearRetryOf: true,
      );
      return null;
    }
  }

  /// The draft went into the composer, which now reads [composerText].
  void placed(AiSuggestion suggestion, String composerText) {
    state = AiSuggestionState(
      phase: AiSuggestionPhase.placed,
      placedSuggestion: suggestion,
      placedText: composerText,
    );
    _report(suggestion.suggestionId, AiSuggestionOutcome.used);
  }

  /// The employee kept their own text instead.
  void declined(AiSuggestion suggestion) {
    state = state.copyWith(
      phase: state.placedSuggestion == null
          ? AiSuggestionPhase.idle
          : AiSuggestionPhase.placed,
      clearSuggestion: true,
    );
    _report(suggestion.suggestionId, AiSuggestionOutcome.discarded);
  }

  /// A draft arrived but the composer could not take it right now.
  void park(AiSuggestion suggestion) {
    state = state.copyWith(
      phase: AiSuggestionPhase.ready,
      suggestion: suggestion,
    );
  }

  /// Closes whatever the strip shows. A draft or answer that was never used
  /// is reported as discarded; "unavailable" stops offering the button.
  void dismiss() {
    final current = state;
    // Nothing is dismissed while a request is out: its answer would land
    // after the panel had gone.
    if (current.isLoading) return;
    final unused = switch (current.phase) {
      AiSuggestionPhase.ready ||
      AiSuggestionPhase.noDraft => current.suggestion,
      _ => null,
    };
    if (unused != null && unused.suggestionId.isNotEmpty) {
      _report(unused.suggestionId, AiSuggestionOutcome.discarded);
    }
    state = current.phase == AiSuggestionPhase.unavailable
        ? const AiSuggestionState(phase: AiSuggestionPhase.hidden)
        : AiSuggestionState(
            phase: current.placedSuggestion == null
                ? AiSuggestionPhase.idle
                : AiSuggestionPhase.placed,
            placedSuggestion: current.placedSuggestion,
            placedText: current.placedText,
          );
  }

  /// The composer was emptied: nothing of the draft is left to send.
  void composerCleared() {
    if (state.placedSuggestion == null) return;
    state = AiSuggestionState(
      phase: state.phase == AiSuggestionPhase.placed
          ? AiSuggestionPhase.idle
          : state.phase,
      suggestion: state.suggestion,
      errorMessage: state.errorMessage,
    );
  }

  /// The `suggestion_id` to send with the reply about to go out, and the
  /// end of this suggestion: once sent it is spent.
  String? takeForSend() {
    final id = state.placedSuggestionId;
    if (id == null) return null;
    composerCleared();
    return id;
  }

  void _report(String suggestionId, String outcome) {
    if (suggestionId.isEmpty) return;
    final repository = ref.read(conversationRepositoryProvider);
    // Telemetry only: a failure here never affects the employee.
    unawaited(
      repository
          .reportAiSuggestionOutcome(suggestionId, outcome)
          .then(
            (_) => _log('OUTCOME $outcome sent'),
            onError: (Object error) => _log('OUTCOME $outcome failed=$error'),
          ),
    );
  }
}

final aiSuggestionControllerProvider = NotifierProvider.autoDispose
    .family<AiSuggestionController, AiSuggestionState, int>(
      AiSuggestionController.new,
    );
