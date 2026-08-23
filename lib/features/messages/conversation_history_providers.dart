/// Async read for the conversation audit timeline.
///
/// `FutureProvider.family`, the same shape as
/// `purchaseConfirmationsProvider` (`intelligence_providers.dart`) — a flat,
/// non-paginated array with no local merge state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation_event.dart';
import '../../core/providers.dart';

final conversationEventsProvider =
    FutureProvider.family<List<ConversationEvent>, int>((ref, conversationId) {
      return ref.watch(conversationRepositoryProvider).events(conversationId);
    });
