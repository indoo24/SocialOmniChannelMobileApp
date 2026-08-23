/// The conversation audit timeline: assignments, status/priority/category
/// changes, notes, purchase rulings — everything `ConversationEvent` covers.
///
/// A bottom sheet, the same shape as `showIntelligencePanel` and
/// `showCustomerRecordSheet`: secondary conversation data reached from a
/// sheet entry point rather than a permanent panel, because a phone has one
/// column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation_event.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'conversation_history_providers.dart';

/// Opens the conversation history sheet.
Future<void> showConversationHistorySheet(
  BuildContext context, {
  required int conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => _HistorySheet(
        conversationId: conversationId,
        scrollController: controller,
      ),
    ),
  );
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({
    required this.conversationId,
    required this.scrollController,
  });

  final int conversationId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(conversationEventsProvider(conversationId));

    // A CustomScrollView/SliverList, not ListView(children: [...]) — every
    // status/priority/category/assignment/note/intelligence change logs an
    // event, so a conversation reused heavily across a long test session can
    // accumulate a large history. An eager Column(children: [for (...) ...])
    // builds and lays out every row synchronously in a single frame instead
    // of only the ones actually visible — see the matching fix and comment
    // in conversion_sheet.dart, which hit this same shape as a real,
    // device-confirmed ANR ("Input dispatching timed out").
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.conversationHistoryTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: Space.md),
                  ],
                ),
              ),
              async.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(Space.xl),
                    child: LoadingState(),
                  ),
                ),
                error: (error, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.lg),
                    child: ErrorStateView(
                      error: error,
                      onRetry: () => ref.invalidate(
                        conversationEventsProvider(conversationId),
                      ),
                    ),
                  ),
                ),
                // Newest first — the backend's own order is chronological
                // (oldest first, for a natural audit-log read), but a "what
                // just happened" panel reads better with the most recent
                // entry on top.
                data: (events) {
                  if (events.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.lg),
                        child: Text(
                          context.l10n.conversationHistoryEmpty,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    );
                  }
                  final reversed = events.reversed.toList(growable: false);
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _HistoryRow(event: reversed[index]),
                      childCount: reversed.length,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});

  final ConversationEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTransition =
        event.fromValue.isNotEmpty || event.toValue.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(event.eventType),
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  humanizeEnum(event.eventType),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatDateTime(context, event.createdAt),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          if (hasTransition) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                event.fromValue.isNotEmpty && event.toValue.isNotEmpty
                    ? '${event.fromValue} → ${event.toValue}'
                    : event.toValue.isNotEmpty
                    ? event.toValue
                    : event.fromValue,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          if (event.actorName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(event.actorName, style: theme.textTheme.labelSmall),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(String eventType) => switch (eventType) {
    'ASSIGNED' ||
    'UNASSIGNED' ||
    'TRANSFERRED' ||
    'TEAM_ASSIGNED' => Icons.person_outline,
    'STATUS_CHANGED' => Icons.sync_alt,
    'PRIORITY_CHANGED' => Icons.flag_outlined,
    'CATEGORY_CHANGED' => Icons.label_outline,
    'NOTE_ADDED' => Icons.sticky_note_2_outlined,
    'MESSAGE_DELETED' => Icons.delete_outline,
    'PURCHASE_CONFIRMED' || 'PURCHASE_REJECTED' => Icons.shopping_bag_outlined,
    'INTELLIGENCE_REFRESHED' ||
    'LEAD_SCORE_OVERRIDDEN' ||
    'LEAD_SCORE_RESET' => Icons.psychology_outlined,
    'CONVERSION_REPORTED' => Icons.campaign_outlined,
    'CONVERSATION_CREATED' => Icons.chat_bubble_outline,
    _ => Icons.history,
  };
}
