import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_group.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';

/// Modal bottom sheet showing all WhatsApp conversations for a single customer.
///
/// Allows the agent to inspect the different numbers/threads, see their latest
/// activity and unread status, and open the exact backend conversation desired.
class CustomerConversationGroupSheet extends StatelessWidget {
  const CustomerConversationGroupSheet({
    required this.group,
    this.currentConversationId,
    super.key,
  });

  final CustomerConversationGroup group;
  final int? currentConversationId;

  static Future<void> show(
    BuildContext context, {
    required CustomerConversationGroup group,
    int? currentConversationId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomerConversationGroupSheet(
        group: group,
        currentConversationId: currentConversationId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? ScenarioColors.darkCard : ScenarioColors.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.lg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.md + bottomPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Space.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),

              // Header: Customer Info
              Row(
                children: [
                  InitialsAvatar(
                    initials: group.customer.initials,
                    imageUrl: group.customer.avatarUrl,
                    provider: group.provider,
                    size: 44,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.customer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.l10n.whatsappConversationsGroupTitle} · ${context.l10n.groupedConversationsCount(group.conversationCount)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? ScenarioColors.darkMutedForeground
                                : ScenarioColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              const Divider(height: 1),
              const SizedBox(height: Space.md),

              // Conversations list
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (int i = 0; i < group.conversations.length; i++) ...[
                        if (i > 0) const SizedBox(height: Space.sm),
                        _ConversationOptionCard(
                          conversation: group.conversations[i],
                          isCurrent:
                              group.conversations[i].id ==
                              currentConversationId,
                          onSelect: () => _openConversation(
                            context,
                            group.conversations[i].id,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openConversation(BuildContext context, int conversationId) {
    Navigator.of(context).pop();

    if (currentConversationId != null) {
      if (conversationId == currentConversationId) return;
      context.pushReplacement(Routes.conversation(conversationId));
    } else {
      context.push(Routes.conversation(conversationId));
    }
  }
}

class _ConversationOptionCard extends StatelessWidget {
  const _ConversationOptionCard({
    required this.conversation,
    required this.isCurrent,
    required this.onSelect,
  });

  final Conversation conversation;
  final bool isCurrent;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final phone = conversation.customer.phone;
    final channelName = conversation.channelName;
    final titleText = phone.isNotEmpty
        ? (channelName.isNotEmpty && channelName != phone
              ? '$phone · $channelName'
              : phone)
        : (channelName.isNotEmpty ? channelName : '#${conversation.id}');

    final (statusLabel, statusTone) = ConversationBadges.status(
      context,
      conversation.status,
    );
    final (priorityLabel, priorityTone) = ConversationBadges.priority(
      context,
      conversation.priority,
    );
    final unread = conversation.hasUnread;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: isDark
                ? (isCurrent
                      ? ScenarioColors.primary.withValues(alpha: 0.12)
                      : ScenarioColors.darkBackground)
                : (isCurrent
                      ? ScenarioColors.primary.withValues(alpha: 0.06)
                      : const Color(0xFFF9FAFB)),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: isCurrent
                  ? ScenarioColors.primary
                  : (isDark
                        ? ScenarioColors.darkBorder
                        : ScenarioColors.border),
              width: isCurrent ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Phone / Channel & Relative Time
              Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_rounded,
                    size: 15,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: Space.xs),
                    StatusBadge(
                      label: context.l10n.currentConversationBadge,
                      tone: BadgeTone.info,
                      dense: true,
                    ),
                  ],
                  const SizedBox(width: Space.xs),
                  Text(
                    formatRelativeTime(context, conversation.lastMessageAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? ScenarioColors.darkMutedForeground
                          : ScenarioColors.mutedForeground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),

              // Message Preview
              Text(
                conversation.lastMessagePreview.isEmpty
                    ? context.l10n.noMessagesYetPreview
                    : conversation.lastMessagePreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: unread
                      ? (isDark
                            ? ScenarioColors.darkForeground
                            : ScenarioColors.foreground)
                      : (isDark
                            ? ScenarioColors.darkMutedForeground
                            : ScenarioColors.mutedForeground),
                  fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: Space.sm),

              // Badges & Open Action
              Row(
                children: [
                  StatusBadge(
                    label: statusLabel,
                    tone: statusTone,
                    dense: true,
                  ),
                  if (ConversationBadges.showsPriority(
                    conversation.priority,
                  )) ...[
                    const SizedBox(width: Space.xs),
                    StatusBadge(
                      label: priorityLabel,
                      tone: priorityTone,
                      dense: true,
                      icon: Icons.priority_high,
                    ),
                  ],
                  if (unread) ...[
                    const SizedBox(width: Space.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: ScenarioColors.primary,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        conversation.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: Text(context.l10n.openConversationAction),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
