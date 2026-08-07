/// Customer details.
///
/// The web client shows this as a third column beside the conversation. A
/// phone has one column, so it becomes a pushed screen reached from the
/// conversation's app bar — same information, same permissions, native shape.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../messages/conversation_controller.dart';

class CustomerDetailsScreen extends ConsumerWidget {
  const CustomerDetailsScreen({required this.conversationId, super.key});

  final int conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationControllerProvider(conversationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: async.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () =>
              ref.invalidate(conversationControllerProvider(conversationId)),
        ),
        data: (state) => _Details(conversation: state.conversation),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = conversation.customer;
    final intelligence = conversation.intelligence;

    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Center(
          child: Column(
            children: [
              InitialsAvatar(
                initials: customer.initials,
                imageUrl: customer.avatarUrl,
                size: 72,
                provider: conversation.provider,
              ),
              const SizedBox(height: Space.md),
              Text(customer.displayName, style: theme.textTheme.titleLarge),
              const SizedBox(height: Space.xs),
              Text(
                ConversationBadges.providerLabel(conversation.provider),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),

        _Section(
          title: 'Conversation',
          rows: [
            ('Status', ConversationBadges.status(conversation.status).$1),
            ('Priority', ConversationBadges.priority(conversation.priority).$1),
            ('Category', conversation.category?.label ?? '—'),
            ('Assigned to', conversation.assignedTo?.fullName ?? 'Unassigned'),
            ('Team', conversation.assignedTeam?.name ?? '—'),
            ('Channel', conversation.channelName),
            ('Messages', '${conversation.messageCount}'),
            ('Started', formatDateTime(conversation.startedAt)),
            ('Last message', formatDateTime(conversation.lastMessageAt)),
          ],
        ),

        if (customer.lifecycleStage.isNotEmpty ||
            customer.preferredLanguage.isNotEmpty)
          _Section(
            title: 'Customer',
            rows: [
              if (customer.lifecycleStage.isNotEmpty)
                ('Lifecycle', humanizeEnum(customer.lifecycleStage)),
              if (customer.preferredLanguage.isNotEmpty)
                ('Language', customer.preferredLanguage),
            ],
          ),

        if (intelligence != null)
          _Section(
            title: 'Intelligence',
            rows: [
              ('Stage', humanizeEnum(intelligence.stage)),
              ('Lead score', '${intelligence.leadScore}'),
              ('Purchase', humanizeEnum(intelligence.purchaseStatus)),
              if (intelligence.needsHumanReview)
                ('Review', 'Needs human review'),
            ],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.md,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            rows[i].$1,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            rows[i].$2.isEmpty ? '—' : rows[i].$2,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
