/// Notifications screen adapted for mobile from the web notifications center.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/notification.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import 'notifications_controller.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationsControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsControllerProvider);
    final unreadCount = ref.watch(notificationsUnreadCountProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.notificationsTitle),
        actions: [
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: () async {
                await ref
                    .read(notificationsControllerProvider.notifier)
                    .markAllRead();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.notificationsAllRead),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.done_all, size: 16),
              label: Text(
                context.l10n.notificationsMarkAllRead,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: ScenarioColors.primary,
              ),
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(notificationsControllerProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child: EmptyState(
                      title: context.l10n.notificationsEmpty,
                      icon: Icons.notifications_none_outlined,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(notificationsControllerProvider.notifier).refresh(),
            child: ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount:
                  state.notifications.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == state.notifications.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: Space.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final notification = state.notifications[index];
                return _NotificationTile(
                  key: ValueKey(notification.id),
                  notification: notification,
                  onTap: () => _handleOpen(notification),
                  onMarkRead: notification.isRead
                      ? null
                      : () => ref
                            .read(notificationsControllerProvider.notifier)
                            .markRead(notification.id),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _handleOpen(NotificationModel notification) {
    if (!notification.isRead) {
      ref
          .read(notificationsControllerProvider.notifier)
          .markRead(notification.id);
    }

    if (notification.conversation != null) {
      context.push(Routes.conversation(notification.conversation!));
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.onMarkRead,
    super.key,
  });

  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;

  Color _severityColor() {
    return switch (notification.severity) {
      NotificationSeverity.critical => ScenarioColors.destructive,
      NotificationSeverity.warning => ScenarioColors.warning,
      _ => ScenarioColors.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUnread = !notification.isRead;
    final title = notification.resolveTitle(context.l10n);
    final reasonTags = notification.resolveReasonTags(context.l10n);
    final relativeTime = formatRelativeTime(context, notification.createdAt);

    final tileBackground = isUnread
        ? (isDark
              ? ScenarioColors.darkPrimary.withValues(alpha: 0.12)
              : ScenarioColors.primary.withValues(alpha: 0.05))
        : Colors.transparent;

    return Material(
      color: tileBackground,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.md,
            Space.md,
            Space.md,
            Space.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left severity accent bar
              Container(
                width: 3.5,
                height: 48,
                margin: const EdgeInsetsDirectional.only(end: Space.md, top: 2),
                decoration: BoxDecoration(
                  color: _severityColor(),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
              ),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and unread indicator dot
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isUnread
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: Space.sm),
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: ScenarioColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Reason tags chips
                    if (reasonTags.isNotEmpty) ...[
                      const SizedBox(height: Space.xs + 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in reasonTags)
                            StatusBadge(
                              label: tag,
                              tone: BadgeTone.neutral,
                              dense: true,
                            ),
                        ],
                      ),
                    ],

                    const SizedBox(height: Space.sm),

                    // Footer: time, occurrences, and Open Conversation action
                    Row(
                      children: [
                        Text(
                          relativeTime,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        if (notification.occurrenceCount > 1) ...[
                          const SizedBox(width: Space.sm),
                          Text(
                            context.l10n.notificationsOccurrences(
                              notification.occurrenceCount.toString(),
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.outline,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (notification.conversation != null)
                          TextButton(
                            onPressed: onTap,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.xs,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: ScenarioColors.primary,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.l10n.notificationsOpenConversation,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 13,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
