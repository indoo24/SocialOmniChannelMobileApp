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
final conversationIntelligenceProvider =
    FutureProvider.family<ConversationIntelligence?, int>((
      ref,
      conversationId,
    ) {
      return ref
          .watch(conversationRepositoryProvider)
          .intelligence(conversationId);
    });

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
