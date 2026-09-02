/// The conversation screen.
///
/// Message history, composer, and the actions the backend permits — with the
/// customer panel moved behind a push rather than shown alongside, because a
/// phone has one column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/employee.dart';
import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../core/realtime/realtime_bridge.dart';
import '../../core/realtime/realtime_logger.dart';
import '../../l10n/l10n_extensions.dart';
import '../authentication/auth_controller.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import '../orders/customer_record_sheet.dart';
import 'conversation_actions_sheet.dart';
import 'conversation_controller.dart';
import 'intelligence_panel.dart';
import 'message_bubble.dart';
import 'notes_controller.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({required this.conversationId, super.key});

  final int conversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  late final ActiveConversation _activeNotifier;
  late final InboxController _inboxNotifier;
  late ProviderContainer _container;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _activeNotifier = ref.read(activeConversationProvider.notifier);
    _inboxNotifier = ref.read(inboxControllerProvider.notifier);
    final activeNotifier = _activeNotifier;
    final conversationId = widget.conversationId;
    Future.microtask(() {
      if (mounted) {
        activeNotifier.opened(conversationId);
        ref
            .read(conversationControllerProvider(conversationId).notifier)
            .refreshOnOpen();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    final activeNotifier = _activeNotifier;
    final inboxNotifier = _inboxNotifier;
    final container = _container;
    final conversationId = widget.conversationId;

    Future.microtask(() {
      try {
        inboxNotifier.markAsRead(conversationId);
        container.invalidate(conversationCountsProvider);
        inboxNotifier.refreshQuietly();
        activeNotifier.closed(conversationId);
      } catch (_) {
        // Provider or scope unmounted/disposed during tear down.
      }
    });

    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _composerController.clear();

    try {
      await ref
          .read(conversationControllerProvider(widget.conversationId).notifier)
          .send(text);
      _scrollToBottom();
    } on ApiException catch (error) {
      if (!mounted) return;
      // The failed bubble already carries the detail; the snackbar is for the
      // case where the agent has scrolled away from it.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      conversationControllerProvider(widget.conversationId),
    );
    final canReply = ref.watch(canProvider(Perm.conversationReply));

    async.whenData((state) {
      final convoIdStr = widget.conversationId.toString();
      final lastMsg = state.messages.isNotEmpty ? state.messages.last : null;
      final active = ref.read(activeConversationProvider);
      final trace = RealtimeLogger.findTraceByMessageOrConvo(
        lastMsg?.id.toString(),
        convoIdStr,
      );
      final traceId = trace?.traceId ?? 'ui_$convoIdStr';

      RealtimeLogger.markStep(
        traceId,
        'UI_STATE_RECEIVED',
        conversationId: convoIdStr,
        messageId: lastMsg?.id.toString(),
      );
      RealtimeLogger.log(
        'UI',
        'CONVERSATION_SCREEN_STATE_RECEIVED',
        traceId: traceId,
        conversationId: convoIdStr,
        messageId: lastMsg?.id.toString(),
        activeConversationId: active?.toString() ?? 'null',
        data: {
          'messageCount': state.messages.length,
          'lastMessageId': lastMsg?.id ?? 'none',
        },
      );
    });

    // Automatically scroll down when a new message arrives.
    ref.listen(conversationControllerProvider(widget.conversationId), (
      previous,
      next,
    ) {
      final prevCount = previous?.value?.messages.length ?? 0;
      final nextCount = next.value?.messages.length ?? 0;
      if (nextCount > prevCount) {
        _scrollToBottom();
      }
    });

    // A realtime `conversation.access_changed` event resolved to "access
    // lost" for this conversation — leave rather than keep showing a thread
    // this employee can no longer see.
    ref.listen<int?>(revokedConversationProvider, (previous, next) {
      if (next != widget.conversationId) return;
      final navigator = Navigator.of(context);
      Future.microtask(() {
        if (!mounted) return;
        ref.read(revokedConversationProvider.notifier).clear();
        if (navigator.canPop()) {
          navigator.pop();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: async.maybeWhen(
          data: (state) => _Header(conversation: state.conversation),
          orElse: () => Text(context.l10n.conversationFallbackTitle),
        ),
        actions: [
          // Orders and captured details. Badged when the analyzer has read
          // something out of the chat that nobody has reviewed.
          async.maybeWhen(
            data: (state) => _RecordButton(
              conversationId: widget.conversationId,
              customerId: state.conversation.customer.id,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          // Lead score, funnel stage, purchase status and the rest of the
          // analyzer's read. Badged when it needs a human's attention.
          async.maybeWhen(
            data: (state) => _IntelligenceButton(
              conversationId: widget.conversationId,
              needsHumanReview:
                  state.conversation.intelligence?.needsHumanReview ?? false,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: context.l10n.customerDetailsTooltip,
            icon: const Icon(Icons.person_outline),
            onPressed: () =>
                context.push(Routes.customer(widget.conversationId)),
          ),
          IconButton(
            tooltip: context.l10n.actionsTooltip,
            icon: const Icon(Icons.more_vert),
            onPressed: () => showConversationActionsSheet(
              context,
              conversationId: widget.conversationId,
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => LoadingState(label: context.l10n.loadingConversation),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(
            conversationControllerProvider(widget.conversationId),
          ),
        ),
        data: (state) => Column(
          children: [
            Expanded(
              child:
                  (state.messages.isEmpty &&
                      (ref
                                  .watch(
                                    notesControllerProvider(
                                      widget.conversationId,
                                    ),
                                  )
                                  .value ??
                              const [])
                          .isEmpty)
                  ? EmptyState(
                      title: context.l10n.noMessagesYetTitle,
                      message: context.l10n.noMessagesYetMessage,
                      icon: Icons.chat_bubble_outline,
                    )
                  : _MessageList(
                      state: state,
                      controller: _scrollController,
                      conversationId: widget.conversationId,
                    ),
            ),
            if (canReply)
              _Composer(
                conversationId: widget.conversationId,
                controller: _composerController,
                sending: _sending,
                onSend: _send,
              )
            else
              const _ReadOnlyNotice(),
          ],
        ),
      ),
    );
  }
}

/// Opens the orders and customer-details sheet, badged when the analyzer has
/// left something unreviewed.
class _RecordButton extends ConsumerWidget {
  const _RecordButton({required this.conversationId, required this.customerId});

  final int conversationId;
  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts =
        ref.watch(customerFactsProvider(customerId)).value ?? const [];
    final orders =
        ref.watch(conversationOrdersProvider(conversationId)).value ?? const [];

    final pending =
        facts.where((f) => f.needsReview).length +
        orders.where((o) => o.isSuggestion).length;

    return Stack(
      children: [
        IconButton(
          tooltip: context.l10n.ordersTooltip,
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed: () => showCustomerRecordSheet(
            context,
            conversationId: conversationId,
            customerId: customerId,
          ),
        ),
        if (pending > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15),
              decoration: BoxDecoration(
                color: ScenarioColors.warning,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '$pending',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens the intelligence panel, dotted when the analyzer flagged this
/// conversation for a human to look at.
class _IntelligenceButton extends StatelessWidget {
  const _IntelligenceButton({
    required this.conversationId,
    required this.needsHumanReview,
  });

  final int conversationId;
  final bool needsHumanReview;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: context.l10n.intelligenceTooltip,
          icon: const Icon(Icons.insights_outlined),
          onPressed: () =>
              showIntelligencePanel(context, conversationId: conversationId),
        ),
        if (needsHumanReview)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: ScenarioColors.warning,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.conversation});

  final dynamic conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusTone) = ConversationBadges.status(
      context,
      conversation.status as String,
    );

    return Row(
      children: [
        InitialsAvatar(
          initials: conversation.customer.initials as String,
          imageUrl: conversation.customer.avatarUrl as String,
          size: 36,
          provider: conversation.provider as String,
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      conversation.customer.displayName as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  StatusBadge(
                    label: statusLabel,
                    tone: statusTone,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 1.5),
              Row(
                children: [
                  _ChannelPill(provider: conversation.provider as String),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _formatSubtitle(context, conversation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: theme.textTheme.labelSmall?.color?.withValues(
                          alpha: 0.75,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatSubtitle(BuildContext context, dynamic conversation) {
    final phone = conversation.customer.phone as String?;
    final channelName = conversation.channelName as String?;
    final parts = <String>[
      if (phone != null && phone.isNotEmpty) '@$phone',
      if (channelName != null && channelName.isNotEmpty) channelName,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return ConversationBadges.providerLabel(
      context,
      conversation.provider as String,
    );
  }
}

class _ChannelPill extends StatelessWidget {
  const _ChannelPill({required this.provider});

  final String provider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, color, label) = _providerInfo(context, provider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color, String) _providerInfo(
    BuildContext context,
    String provider,
  ) => switch (provider.toUpperCase()) {
    'WHATSAPP' => (
      Icons.chat_bubble_rounded,
      const Color(0xFF16A34A),
      'WhatsApp',
    ),
    'MESSENGER' => (Icons.facebook, const Color(0xFF2563EB), 'Messenger'),
    'INSTAGRAM' => (
      Icons.camera_alt_outlined,
      const Color(0xFFE11D48),
      'Instagram',
    ),
    'TELEGRAM' => (Icons.send_rounded, const Color(0xFF0284C7), 'Telegram'),
    _ => (Icons.chat_bubble_outline_rounded, ScenarioColors.primary, provider),
  };
}

class _TimelineEntry {
  const _TimelineEntry({this.message, this.note, required this.time});

  final Message? message;
  final InternalNote? note;
  final DateTime time;
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.state,
    required this.controller,
    required this.conversationId,
  });

  final ConversationState state;
  final ScrollController controller;
  final int conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDelete = ref.watch(canProvider(Perm.conversationDeleteMessage));
    final notes =
        ref.watch(notesControllerProvider(conversationId)).value ?? const [];

    final entries = <_TimelineEntry>[
      for (final m in state.messages)
        _TimelineEntry(message: m, time: m.sentAt),
      for (final n in notes) _TimelineEntry(note: n, time: n.createdAt),
    ]..sort((a, b) => a.time.compareTo(b.time));

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Older history loads when the agent reaches the top.
        if (notification.metrics.pixels <= 80 && state.hasMore) {
          ref
              .read(conversationControllerProvider(conversationId).notifier)
              .loadOlder();
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        addAutomaticKeepAlives: false,
        itemCount: entries.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (state.isLoadingMore && index == 0) {
            return const Padding(
              padding: EdgeInsets.all(Space.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final offset = state.isLoadingMore ? index - 1 : index;
          final entry = entries[offset];
          final previous = offset > 0 ? entries[offset - 1] : null;
          final showDay =
              previous == null || !_sameDay(previous.time, entry.time);

          return Column(
            children: [
              if (showDay) _DayDivider(date: entry.time),
              if (entry.note != null)
                _InternalNoteTimelineCard(note: entry.note!)
              else if (entry.message != null)
                MessageBubble(
                  message: entry.message!,
                  onRetry:
                      entry.message!.hasFailed && entry.message!.localId != null
                      ? () => ref
                            .read(
                              conversationControllerProvider(
                                conversationId,
                              ).notifier,
                            )
                            .retry(entry.message!.localId!)
                      : null,
                  onDiscard:
                      entry.message!.hasFailed && entry.message!.localId != null
                      ? () => ref
                            .read(
                              conversationControllerProvider(
                                conversationId,
                              ).notifier,
                            )
                            .discardFailed(entry.message!.localId!)
                      : null,
                  onDelete:
                      canDelete &&
                          !entry.message!.isSystem &&
                          !entry.message!.isPending &&
                          !entry.message!.hasFailed &&
                          entry.message!.id >= 0
                      ? () => _confirmDeleteMessage(
                          context,
                          ref,
                          conversationId,
                          entry.message!,
                        )
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _InternalNoteTimelineCard extends StatelessWidget {
  const _InternalNoteTimelineCard({required this.note});

  final InternalNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF241B08) : const Color(0xFFFEFCE8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: const Color(0xFFEAB308)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF854D0E),
                        ),
                        const SizedBox(width: Space.xs),
                        Text(
                          context.l10n.internalNoteTab,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: isDark
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF713F12),
                          ),
                        ),
                        if (note.authorName.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              ' · ${note.authorName} · ${formatTime(context, note.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFFFDE68A)
                                    : const Color(0xFF854D0E),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF78350F).withValues(alpha: 0.4)
                                : const Color(0xFFFEF08A),
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Text(
                            context.l10n.notVisibleToCustomer,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFFFDE68A)
                                  : const Color(0xFF854D0E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      note.body.isNotEmpty ? note.body : '—',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? const Color(0xFFFEF9C3)
                            : const Color(0xFF451A03),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirms, then soft-deletes a message. ADMIN/SUPERVISOR only.
Future<void> _confirmDeleteMessage(
  BuildContext context,
  WidgetRef ref,
  int conversationId,
  Message message,
) async {
  final reasonController = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.deleteMessageConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dialogContext.l10n.deleteMessageConfirmBody),
          const SizedBox(height: Space.md),
          TextField(
            controller: reasonController,
            decoration: InputDecoration(
              labelText: dialogContext.l10n.deleteMessageReasonLabel,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.deleteMessageAction),
        ),
      ],
    ),
  );
  final reason = reasonController.text.trim();
  if (confirmed != true) return;

  try {
    await ref
        .read(conversationRepositoryProvider)
        .deleteMessage(conversationId, message.id, reason: reason);
    if (!context.mounted) return;
    ref
        .read(conversationControllerProvider(conversationId).notifier)
        .removeMessage(message.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.deleteMessageDeletedSnackbar)),
    );
  } on ApiException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
              height: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Text(
              formatDayHeading(context, date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.textTheme.labelSmall?.color?.withValues(
                  alpha: 0.7,
                ),
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ComposerMode { reply, internalNote, template }

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: isDark ? 0.25 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: isDark ? 0.5 : 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? activeColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? activeColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.conversationId,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final int conversationId;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  _ComposerMode _mode = _ComposerMode.reply;
  String? _selectedTemplate;
  bool _savingNote = false;

  static const _defaultTemplates = [
    'Hello! How can we help you today?',
    'Thank you for reaching out. We are looking into this for you.',
    'Your request has been received and is being processed.',
    'Is there anything else we can assist you with?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canNote = ref.watch(canProvider(Perm.conversationNote));

    final isInternal = _mode == _ComposerMode.internalNote;
    final composerBackground = isInternal
        ? (isDark ? const Color(0xFF231B06) : const Color(0xFFFEFCE8))
        : theme.colorScheme.surface;
    final composerBorder = isInternal
        ? (isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A))
        : theme.colorScheme.outline;

    return SafeArea(
      top: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.xs,
          Space.md,
          Space.sm,
        ),
        decoration: BoxDecoration(
          color: composerBackground,
          border: Border(top: BorderSide(color: composerBorder)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode selector row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SegmentTab(
                    label: context.l10n.replyTab,
                    icon: Icons.chat_bubble_outline_rounded,
                    active: _mode == _ComposerMode.reply,
                    activeColor: ScenarioColors.primary,
                    onTap: () => setState(() => _mode = _ComposerMode.reply),
                  ),
                  if (canNote) ...[
                    const SizedBox(width: Space.xs),
                    _SegmentTab(
                      label: context.l10n.internalNoteTab,
                      icon: Icons.sticky_note_2_outlined,
                      active: _mode == _ComposerMode.internalNote,
                      activeColor: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFD97706),
                      onTap: () =>
                          setState(() => _mode = _ComposerMode.internalNote),
                    ),
                  ],
                  const SizedBox(width: Space.xs),
                  _SegmentTab(
                    label: context.l10n.templateTab,
                    icon: Icons.description_outlined,
                    active: _mode == _ComposerMode.template,
                    activeColor: isDark
                        ? const Color(0xFFA5B4FC)
                        : const Color(0xFF4F46E5),
                    onTap: () => setState(() => _mode = _ComposerMode.template),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),

            // Mode Content
            if (_mode == _ComposerMode.reply) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('composer_reply_input'),
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: context.l10n.writeReplyHint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton.filled(
                      onPressed: widget.sending ? null : widget.onSend,
                      icon: widget.sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ] else if (_mode == _ComposerMode.internalNote) ...[
              Column(
                children: [
                  TextField(
                    key: const ValueKey('composer_internal_note_input'),
                    controller: widget.controller,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      filled: true,
                      hintText: context.l10n.internalNoteInputHint,
                      fillColor: isDark
                          ? ScenarioColors.warning.withValues(alpha: 0.1)
                          : const Color(0xFFFFFBEB),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFEAB308),
                          width: 1.5,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                        borderSide: BorderSide(
                          color: isDark
                              ? ScenarioColors.warning.withValues(alpha: 0.3)
                              : const Color(0xFFFDE68A),
                          width: 1,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(Space.md),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: isDark
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.notSentToCustomer,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          backgroundColor: isDark
                              ? const Color(0xFFD97706)
                              : const Color(0xFFEAB308),
                          foregroundColor: isDark
                              ? Colors.white
                              : const Color(0xFF451A03),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                            vertical: 8,
                          ),
                        ),
                        onPressed: _savingNote
                            ? null
                            : () async {
                                final text = widget.controller.text.trim();
                                if (text.isEmpty) return;
                                setState(() => _savingNote = true);
                                try {
                                  await ref
                                      .read(
                                        notesControllerProvider(
                                          widget.conversationId,
                                        ).notifier,
                                      )
                                      .addNote(text);
                                  widget.controller.clear();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(context.l10n.saveNote),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _savingNote = false);
                                  }
                                }
                              },
                        icon: _savingNote
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(
                          context.l10n.saveNote,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else if (_mode == _ComposerMode.template) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.approvedTemplate,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedTemplate,
                          hint: Text(context.l10n.chooseTemplate),
                          items: [
                            for (final t in _defaultTemplates)
                              DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (val) =>
                              setState(() => _selectedTemplate = val),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      IconButton(
                        tooltip: 'Reset',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () =>
                            setState(() => _selectedTemplate = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                        onPressed: (_selectedTemplate == null || widget.sending)
                            ? null
                            : () async {
                                final text = _selectedTemplate!;
                                await ref
                                    .read(
                                      conversationControllerProvider(
                                        widget.conversationId,
                                      ).notifier,
                                    )
                                    .send(text);
                                setState(() => _selectedTemplate = null);
                              },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: Text(context.l10n.sendTemplate),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown to QA and anyone else the backend does not grant reply permission.
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Space.sm),
            Text(context.l10n.readOnlyLabel, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
