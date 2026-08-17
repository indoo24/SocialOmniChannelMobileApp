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
import 'message_bubble.dart';

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
      inboxNotifier.markAsRead(conversationId);
      container.invalidate(conversationCountsProvider);
      inboxNotifier.refreshQuietly();
      activeNotifier.closed(conversationId);
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: async.maybeWhen(
          data: (state) => _Header(conversation: state.conversation),
          orElse: () => Text(context.l10n.conversationFallbackTitle),
        ),
        actions: [
          // Orders and captured details. Badged when the analyzer has read
          // something out of the chat that nobody has reviewed — otherwise the
          // suggestions sit in a sheet no one thinks to open.
          async.maybeWhen(
            data: (state) => _RecordButton(
              conversationId: widget.conversationId,
              customerId: state.conversation.customer.id,
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
              child: state.messages.isEmpty
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

class _Header extends StatelessWidget {
  const _Header({required this.conversation});

  final dynamic conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        InitialsAvatar(
          initials: conversation.customer.initials as String,
          imageUrl: conversation.customer.avatarUrl as String,
          size: 32,
          provider: conversation.provider as String,
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                conversation.customer.displayName as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                ConversationBadges.providerLabel(
                  context,
                  conversation.provider as String,
                ),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    final messages = state.messages;

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
        // Keeps memory flat on long histories rather than retaining every
        // bubble that has scrolled off.
        addAutomaticKeepAlives: false,
        itemCount: messages.length + (state.isLoadingMore ? 1 : 0),
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
          final message = messages[offset];
          final previous = offset > 0 ? messages[offset - 1] : null;
          final showDay =
              previous == null || !_sameDay(previous.sentAt, message.sentAt);

          return Column(
            children: [
              if (showDay) _DayDivider(date: message.sentAt),
              MessageBubble(
                message: message,
                onRetry: message.hasFailed && message.localId != null
                    ? () => ref
                          .read(
                            conversationControllerProvider(
                              conversationId,
                            ).notifier,
                          )
                          .retry(message.localId!)
                    : null,
                onDiscard: message.hasFailed && message.localId != null
                    ? () => ref
                          .read(
                            conversationControllerProvider(
                              conversationId,
                            ).notifier,
                          )
                          .discardFailed(message.localId!)
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

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.xs,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            formatDayHeading(context, date),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.md,
          Space.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
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
                onPressed: sending ? null : onSend,
                icon: sending
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
