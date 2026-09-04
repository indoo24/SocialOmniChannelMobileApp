/// The conversation screen.
///
/// Message history, composer, and the actions the backend permits — with the
/// customer panel moved behind a push rather than shown alongside, because a
/// phone has one column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
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
import '../conversations/customer_conversation_group_sheet.dart';
import '../conversations/inbox_controller.dart';
import '../templates/templates_providers.dart';
import '../../core/models/template.dart';
import 'composer_attachment.dart';
import 'conversation_actions_sheet.dart';
import 'conversation_controller.dart';
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
  bool _initialScrollDone = false;
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final distanceFromBottom = pos.maxScrollExtent - pos.pixels;
    final show = distanceFromBottom > 150;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  bool _isNearBottom({double threshold = 150}) {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return true;
    return (pos.maxScrollExtent - pos.pixels) <= threshold;
  }

  void _jumpToBottomInitial() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.hasContentDimensions) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        _initialScrollDone = true;
        _onScroll();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _scrollController.hasClients &&
              _scrollController.position.hasContentDimensions) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
            _initialScrollDone = true;
            _onScroll();
          }
        });
      }
    });
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
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
    _scrollController.removeListener(_onScroll);
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

  /// [attachmentId] is a draft already staged (uploaded) via the
  /// attachment/voice flow in [_Composer] — this method only ever
  /// references it, never uploads anything itself. [attachmentPreview]
  /// renders that same local file in the optimistic bubble.
  Future<void> _send({
    String? attachmentId,
    MessageAttachment? attachmentPreview,
  }) async {
    final text = _composerController.text.trim();
    final hasAttachment = attachmentId != null;
    if ((text.isEmpty && !hasAttachment) || _sending) return;

    setState(() => _sending = true);
    _composerController.clear();

    try {
      await ref
          .read(conversationControllerProvider(widget.conversationId).notifier)
          .send(
            text,
            attachmentId: attachmentId,
            attachmentPreview: attachmentPreview,
          );
      _scrollToBottom(animated: true);
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      conversationControllerProvider(widget.conversationId),
    );
    final canReply = ref.watch(canProvider(Perm.conversationReply));
    final canChangeCategory = ref.watch(
      canProvider(Perm.conversationChangeCategory),
    );

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
        if (!_initialScrollDone) {
          _jumpToBottomInitial();
        } else if (_isNearBottom()) {
          _scrollToBottom(animated: true);
        } else {
          _onScroll();
        }
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
          async.maybeWhen(
            data: (state) => _FollowUpButton(
              conversation: state.conversation,
              canChange: canChangeCategory,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          async.maybeWhen(
            data: (state) => state.conversation.assignedTo != null
                ? _AssigneeAvatar(assignedTo: state.conversation.assignedTo!)
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
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
              child: Stack(
                children: [
                  Positioned.fill(
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
                            onInitialLayout: _initialScrollDone
                                ? null
                                : _jumpToBottomInitial,
                          ),
                  ),
                  PositionedDirectional(
                    end: Space.md,
                    bottom: Space.sm,
                    child: _ScrollToBottomButton(
                      visible: _showScrollToBottom,
                      onPressed: () => _scrollToBottom(animated: true),
                    ),
                  ),
                ],
              ),
            ),
            if (canReply)
              _Composer(
                conversationId: widget.conversationId,
                controller: _composerController,
                sending: _sending,
                onSend: _send,
                isWhatsApp:
                    async.value?.conversation.provider.toUpperCase() ==
                    'WHATSAPP',
              )
            else
              const _ReadOnlyNotice(),
          ],
        ),
      ),
    );
  }
}

/// Standalone Follow-up Flag button in the conversation header.
class _FollowUpButton extends ConsumerWidget {
  const _FollowUpButton({required this.conversation, required this.canChange});

  final Conversation conversation;
  final bool canChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFollowUp = conversation.isFollowUp;

    final dateStr = conversation.followUpDate != null
        ? ' (${DateFormat('yyyy-MM-dd').format(conversation.followUpDate!)})'
        : '';
    final tooltip = isFollowUp
        ? '${context.l10n.followUpTooltip}$dateStr'
        : context.l10n.followUpTooltip;

    final flagColor = isFollowUp
        ? const Color(0xFFEAB308)
        : theme.colorScheme.onSurfaceVariant;

    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        isFollowUp ? Icons.flag_rounded : Icons.flag_outlined,
        color: flagColor,
        size: 22,
      ),
      onPressed: canChange
          ? () => _showFollowUpDialog(context, ref, conversation)
          : null,
    );
  }
}

/// Compact Assignee Avatar in the conversation header.
class _AssigneeAvatar extends StatelessWidget {
  const _AssigneeAvatar({required this.assignedTo});

  final EmployeeBrief assignedTo;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: assignedTo.fullName,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InitialsAvatar(
          initials: assignedTo.initials,
          imageUrl: assignedTo.avatarUrl,
          size: 26,
        ),
      ),
    );
  }
}

Future<void> _showFollowUpDialog(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
) async {
  DateTime? selectedDate = conversation.followUpDate;
  bool isFollowUp = conversation.isFollowUp ? true : true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final theme = Theme.of(context);
        final dateFormatted = selectedDate != null
            ? DateFormat('yyyy-MM-dd').format(selectedDate!)
            : context.l10n.noFollowUpDate;

        return AlertDialog(
          title: Text(
            conversation.isFollowUp
                ? context.l10n.editFollowUpTitle
                : context.l10n.markFollowUpTitle,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  context.l10n.followUpSwitchLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: isFollowUp,
                onChanged: (val) => setDialogState(() => isFollowUp = val),
              ),
              if (isFollowUp) ...[
                const SizedBox(height: Space.sm),
                Text(
                  context.l10n.followUpDateLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.xs),
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            dateFormatted,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (selectedDate != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: context.l10n.clearDate,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                setDialogState(() => selectedDate = null),
                          )
                        else
                          Icon(
                            Icons.arrow_drop_down,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (conversation.isFollowUp)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await ref
                        .read(
                          conversationControllerProvider(
                            conversation.id,
                          ).notifier,
                        )
                        .updateFollowUp(isFollowUp: false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.followUpClearedMessage),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: theme.colorScheme.error,
                        ),
                      );
                    }
                  }
                },
                child: Text(context.l10n.removeFollowUp),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.discardAction),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final dateStr = selectedDate != null
                    ? DateFormat('yyyy-MM-dd').format(selectedDate!)
                    : null;
                final clearDate =
                    conversation.followUpDate != null && selectedDate == null;
                try {
                  await ref
                      .read(
                        conversationControllerProvider(
                          conversation.id,
                        ).notifier,
                      )
                      .updateFollowUp(
                        isFollowUp: isFollowUp,
                        followUpDate: isFollowUp ? dateStr : null,
                        clearFollowUpDate: isFollowUp ? clearDate : false,
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isFollowUp
                              ? context.l10n.followUpUpdatedMessage
                              : context.l10n.followUpClearedMessage,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: theme.colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: Text(context.l10n.saveFollowUp),
            ),
          ],
        );
      },
    ),
  );
}

/// Floating WhatsApp-style scroll-to-latest button.
class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 1.5),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        opacity: visible ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Material(
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            shape: const CircleBorder(),
            color: isDark
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.white,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? theme.colorScheme.outline
                        : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.conversation});

  final dynamic conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (statusLabel, statusTone) = ConversationBadges.status(
      context,
      conversation.status as String,
    );

    final inboxState = ref.watch(inboxControllerProvider).value;
    final groups = inboxState?.groups ?? const [];
    final matchingGroup = groups
        .where(
          (g) =>
              g.customer.id > 0 &&
              g.customer.id == conversation.customer.id &&
              g.isMultiConversation,
        )
        .firstOrNull;

    return InkWell(
      onTap: matchingGroup != null
          ? () => CustomerConversationGroupSheet.show(
              context,
              group: matchingGroup,
              currentConversationId: conversation.id as int?,
            )
          : null,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Row(
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
      ),
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
    this.onInitialLayout,
  });

  final ConversationState state;
  final ScrollController controller;
  final int conversationId;
  final VoidCallback? onInitialLayout;

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

    if (onInitialLayout != null && entries.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onInitialLayout!();
      });
    }

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

/// Sends the composer's current text, plus an optional attachment already
/// staged (uploaded) via [ConversationRepository.stageAttachment].
typedef ComposerSendCallback =
    void Function({String? attachmentId, MessageAttachment? attachmentPreview});

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.conversationId,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.isWhatsApp = false,
  });

  final int conversationId;
  final TextEditingController controller;
  final bool sending;
  final ComposerSendCallback onSend;
  final bool isWhatsApp;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  _ComposerMode _mode = _ComposerMode.reply;
  WhatsAppTemplate? _selectedTemplate;
  bool _savingNote = false;

  /// An image already picked and uploaded, waiting to be sent (or removed).
  /// Voice notes skip this state entirely — recording finishes and sends in
  /// one motion, matching WhatsApp's own behavior, rather than sitting as a
  /// staged preview the agent could otherwise edit alongside typed text.
  StagedAttachment? _stagedImage;
  bool _isRecording = false;
  final _voiceRecorderKey = GlobalKey<ComposerVoiceRecorderState>();

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onImageStaged(StagedAttachment staged) {
    setState(() => _stagedImage = staged);
  }

  void _onImageRemoved() {
    setState(() => _stagedImage = null);
  }

  void _onVoiceStaged(StagedAttachment staged) {
    // A voice note sends immediately on finishing recording rather than
    // sitting in the composer for a separate Send tap — matching the "Stop
    // and send" affordance the recording bar itself already promises. Any
    // text already typed goes along as the same message's caption — the
    // `Reply` endpoint accepts `text` alongside `attachment_ids` in one
    // call, the same combination an image send already uses.
    widget.onSend(
      attachmentId: staged.draftId,
      attachmentPreview: staged.attachment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canNote = ref.watch(canProvider(Perm.conversationNote));
    final convo = ref
        .watch(conversationControllerProvider(widget.conversationId))
        .value
        ?.conversation;
    final isWhatsApp = convo != null
        ? (convo.provider.toUpperCase() == 'WHATSAPP')
        : widget.isWhatsApp;

    final currentMode = (!isWhatsApp && _mode == _ComposerMode.template)
        ? _ComposerMode.reply
        : _mode;

    final isInternal = currentMode == _ComposerMode.internalNote;
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
                    active: currentMode == _ComposerMode.reply,
                    activeColor: ScenarioColors.primary,
                    onTap: () => setState(() => _mode = _ComposerMode.reply),
                  ),
                  if (canNote) ...[
                    const SizedBox(width: Space.xs),
                    _SegmentTab(
                      label: context.l10n.internalNoteTab,
                      icon: Icons.sticky_note_2_outlined,
                      active: currentMode == _ComposerMode.internalNote,
                      activeColor: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFD97706),
                      onTap: () =>
                          setState(() => _mode = _ComposerMode.internalNote),
                    ),
                  ],
                  if (isWhatsApp) ...[
                    const SizedBox(width: Space.xs),
                    _SegmentTab(
                      label: context.l10n.templateTab,
                      icon: Icons.description_outlined,
                      active: currentMode == _ComposerMode.template,
                      activeColor: isDark
                          ? const Color(0xFFA5B4FC)
                          : const Color(0xFF4F46E5),
                      onTap: () =>
                          setState(() => _mode = _ComposerMode.template),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.xs),

            // Mode Content
            if (currentMode == _ComposerMode.reply) ...[
              if (_stagedImage != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ComposerAttachmentPreview(
                    conversationId: widget.conversationId,
                    staged: _stagedImage!,
                    onRemoved: _onImageRemoved,
                  ),
                ),
              if (_isRecording)
                ComposerVoiceRecorder(
                  key: _voiceRecorderKey,
                  conversationId: widget.conversationId,
                  enabled: !widget.sending,
                  onStaged: _onVoiceStaged,
                  onError: _showMessage,
                  onRecordingChanged: (recording) {
                    if (mounted) setState(() => _isRecording = recording);
                  },
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Attachment button on the far left
                    ComposerAttachmentButton(
                      conversationId: widget.conversationId,
                      enabled: !widget.sending,
                      onStaged: _onImageStaged,
                      onError: _showMessage,
                    ),
                    const SizedBox(width: Space.xs),
                    // Text input in the middle
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
                    const SizedBox(width: Space.xs),
                    // Microphone button immediately before Send
                    ComposerVoiceRecorder(
                      key: _voiceRecorderKey,
                      conversationId: widget.conversationId,
                      enabled: !widget.sending,
                      onStaged: _onVoiceStaged,
                      onError: _showMessage,
                      onRecordingChanged: (recording) {
                        if (mounted) setState(() => _isRecording = recording);
                      },
                    ),
                    const SizedBox(width: Space.xs),
                    // Send button fixed at far right
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton.filled(
                        onPressed: widget.sending
                            ? null
                            : () {
                                final staged = _stagedImage;
                                if (staged != null) {
                                  setState(() => _stagedImage = null);
                                }
                                widget.onSend(
                                  attachmentId: staged?.draftId,
                                  attachmentPreview: staged?.attachment,
                                );
                              },
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
            ] else if (currentMode == _ComposerMode.internalNote) ...[
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
            ] else if (currentMode == _ComposerMode.template) ...[
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
                  ref
                      .watch(
                        conversationTemplatesProvider(widget.conversationId),
                      )
                      .when(
                        loading: () => Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<WhatsAppTemplate>(
                                isExpanded: true,
                                items: const [],
                                onChanged: null,
                                hint: Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: Space.sm),
                                    Text(context.l10n.loadingTemplates),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        error: (err, _) => Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.genericErrorFallbackMessage,
                                style: TextStyle(
                                  color: ScenarioColors.danger,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                ref
                                  ..invalidate(
                                    conversationTemplatesProvider(
                                      widget.conversationId,
                                    ),
                                  )
                                  ..invalidate(templatesForChannelProvider);
                              },
                              child: Text(context.l10n.retryButton),
                            ),
                          ],
                        ),
                        data: (templates) {
                          if (templates.isEmpty) {
                            return Row(
                              children: [
                                Expanded(
                                  child:
                                      DropdownButtonFormField<WhatsAppTemplate>(
                                        isExpanded: true,
                                        items: const [],
                                        onChanged: null,
                                        hint: Text(
                                          context.l10n.noTemplatesAvailable,
                                        ),
                                      ),
                                ),
                                const SizedBox(width: Space.xs),
                                IconButton(
                                  tooltip: context.l10n.refreshAction,
                                  icon: const Icon(Icons.refresh_rounded),
                                  onPressed: () {
                                    ref
                                      ..invalidate(
                                        conversationTemplatesProvider(
                                          widget.conversationId,
                                        ),
                                      )
                                      ..invalidate(templatesForChannelProvider);
                                  },
                                ),
                              ],
                            );
                          }

                          final validSelection =
                              templates.any(
                                (t) => t.id == _selectedTemplate?.id,
                              )
                              ? _selectedTemplate
                              : null;

                          return Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<WhatsAppTemplate>(
                                  isExpanded: true,
                                  initialValue: validSelection,
                                  hint: Text(context.l10n.chooseTemplate),
                                  items: [
                                    for (final t in templates)
                                      DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          '${t.name} · ${t.body.isNotEmpty ? t.body : t.language}',
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
                                onPressed: () {
                                  setState(() => _selectedTemplate = null);
                                  ref
                                    ..invalidate(
                                      conversationTemplatesProvider(
                                        widget.conversationId,
                                      ),
                                    )
                                    ..invalidate(templatesForChannelProvider);
                                },
                              ),
                            ],
                          );
                        },
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
                                final text = _selectedTemplate!.body.isNotEmpty
                                    ? _selectedTemplate!.body
                                    : _selectedTemplate!.name;
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
