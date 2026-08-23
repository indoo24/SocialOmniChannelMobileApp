/// Async read for a conversation's Meta conversions history.
///
/// `FutureProvider.family`, the same shape as `conversationEventsProvider`
/// (`conversation_history_providers.dart`) — a flat, non-paginated array
/// with no local merge state. Reporting a conversion is a plain repository
/// call from the UI plus `ref.invalidate`, matching every other mutating
/// action in this app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversion_event.dart';
import '../../core/providers.dart';

final conversationConversionsProvider =
    FutureProvider.family<List<ConversionEvent>, int>((ref, conversationId) {
      return ref
          .watch(conversationRepositoryProvider)
          .conversions(conversationId);
    });
