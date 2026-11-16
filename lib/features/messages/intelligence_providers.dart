/// Async reads for the conversation-intelligence panel.
///
/// `FutureProvider`, not `AsyncNotifier`: like `conversationOrdersProvider`
/// and `customerFactsProvider` (`directory_providers.dart`), this holds no
/// local merge state — a mutating action calls the repository directly and
/// `ref.invalidate`s the affected provider, and `intelligence.updated`
/// realtime events do the same from `realtime_bridge.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/intelligence.dart';
import '../../core/providers.dart';

/// The full intelligence read for one conversation.
///
/// `AsyncData(null)` is the legitimate "not analyzed yet" state — distinct
/// from `AsyncLoading` and `AsyncError` — since the backend returns a literal
/// JSON `null` before the analyzer has run.
///
/// Read, watched, awaited (`.future`) and invalidated exactly like the
/// `FutureProvider` it was. A notifier only so that an action whose endpoint
/// answers with this same read can show that answer at once
/// ([ConversationIntelligenceNotifier.applyServerAnswer]).
final conversationIntelligenceProvider =
    AsyncNotifierProvider.family<
      ConversationIntelligenceNotifier,
      ConversationIntelligence?,
      int
    >(ConversationIntelligenceNotifier.new);

class ConversationIntelligenceNotifier
    extends AsyncNotifier<ConversationIntelligence?> {
  ConversationIntelligenceNotifier(this.conversationId);

  final int conversationId;

  @override
  Future<ConversationIntelligence?> build() =>
      ref.watch(conversationRepositoryProvider).intelligence(conversationId);

  /// What the server just answered from an endpoint that returns this same
  /// intelligence read (`POST …/confirm-purchase/`), shown as it is — never
  /// a value worked out here. A later read (an invalidation, a realtime
  /// `intelligence.updated`) replaces it as usual.
  void applyServerAnswer(ConversationIntelligence intelligence) =>
      state = AsyncData(intelligence);
}

/// History of human rulings on purchase claims for one conversation.
final purchaseConfirmationsProvider =
    FutureProvider.family<List<PurchaseConfirmation>, int>((
      ref,
      conversationId,
    ) {
      return ref
          .watch(conversationRepositoryProvider)
          .purchaseConfirmations(conversationId);
    });
