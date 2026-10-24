/// Choosing where to forward a message, confirming, and sending it.
///
/// A bottom sheet over the conversation, so the thread underneath is never
/// left, reloaded or scrolled: when the forward is done the sheet closes and
/// the agent is exactly where they were. How a forward is carried out — and
/// what it is not — is `message_forwarding.dart`.
///
/// The destination list is the server's own conversation search
/// (`GET /conversations/`, the same `search` the inbox uses), limited to the
/// accounts the inbox shows, so what can be picked is what the employee can
/// see. Whether they may *send* there, and whether the channel will take the
/// message, is the server's call at the end, and its refusal is shown.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../conversations/conversation_repository.dart';
import '../conversations/inbox_controller.dart';
import '../directory/directory_providers.dart';
import 'conversation_controller.dart';
import 'message_forwarding.dart';

/// What to look for, and which conversation to leave out (the one the message
/// is already in).
typedef ForwardDestinationsKey = ({String search, int excludeId});

/// [hidden] counts the rows left out because they provably cannot be sent a
/// free-form message ([destinationProvablyIneligible]).
typedef ForwardDestinations = ({
  List<Conversation> items,
  int hidden,
  bool hasMore,
});

/// One page of conversations matching [ForwardDestinationsKey.search], newest
/// activity first, as the server answers it. Limited to the accounts the
/// inbox itself shows (a removed or disconnected account's conversations are
/// not offered as somewhere to send), and without the ones its rows prove
/// cannot be sent a free-form message — closed, or WhatsApp past the 24-hour
/// window. Everything else is offered, not vouched for: a list row does not
/// say whether the destination will accept the message, so that is asked of
/// the server again when the agent confirms.
final forwardDestinationsProvider = FutureProvider.autoDispose
    .family<ForwardDestinations, ForwardDestinationsKey>((ref, key) async {
      List<int>? accounts;
      try {
        accounts = eligibleInboxAccounts(
          await ref.watch(channelsProvider.future),
        );
      } catch (_) {
        accounts = null; // the server's own default
      }
      final page = await ref
          .read(conversationRepositoryProvider)
          .list(
            filters: scopeToEligibleAccounts(
              ConversationFilters(search: key.search),
              accounts,
            ),
          );
      final others = [
        for (final conversation in page.results)
          if (conversation.id != key.excludeId) conversation,
      ];
      final now = DateTime.now();
      final offered = [
        for (final conversation in others)
          if (!destinationProvablyIneligible(conversation, now: now))
            conversation,
      ];
      return (
        items: offered,
        hidden: others.length - offered.length,
        hasMore: page.hasMore,
      );
    });

/// The Forward action: says why when [message] cannot be forwarded, otherwise
/// opens the destination sheet.
Future<void> startForwardMessage(
  BuildContext context, {
  required int conversationId,
  required Message message,
}) async {
  final block = forwardBlockOf(message);
  if (block != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(forwardBlockMessage(context.l10n, block))),
      );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ForwardMessageSheet(
      sourceConversationId: conversationId,
      message: message,
    ),
  );
}

class ForwardMessageSheet extends ConsumerStatefulWidget {
  const ForwardMessageSheet({
    required this.sourceConversationId,
    required this.message,
    super.key,
  });

  final int sourceConversationId;
  final Message message;

  @override
  ConsumerState<ForwardMessageSheet> createState() =>
      _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends ConsumerState<ForwardMessageSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  Conversation? _selected;

  /// A forward is in flight. Everything that could start another is off while
  /// it is, and the sheet cannot be dismissed from under it.
  bool _busy = false;

  /// Destinations the server has just refused to be sent to: they are taken
  /// off the list at once rather than offered again.
  final _unfit = <int>{};

  /// The confirmation dialog is open (or opening): a second tap on the
  /// button behind it must not stack another.
  bool _confirming = false;
  String? _error;

  /// One idempotency key per destination for as long as this sheet is open:
  /// a retry after a lost answer reuses it, so the server returns the message
  /// it already stored instead of storing a second.
  final _clientIds = <int, String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  String _channelOf(BuildContext context, Conversation c) {
    final provider = ConversationBadges.providerLabel(context, c.provider);
    return c.channelName.isEmpty ? provider : '$provider · ${c.channelName}';
  }

  Future<void> _confirm() async {
    final destination = _selected;
    if (destination == null || _busy || _confirming) return;
    _confirming = true;
    final l10n = context.l10n;
    final message = widget.message;
    final text = message.text.trim();

    // Whichever button is pressed first decides. A second press — a double
    // tap — would otherwise pop again, and the second pop lands on the sheet
    // underneath, not on the dialog that is already closing.
    var decided = false;
    void decide(BuildContext dialogContext, bool answer) {
      if (decided) return;
      decided = true;
      Navigator.of(dialogContext).pop(answer);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('forwardConfirmDialog'),
        title: Text(dialogContext.l10n.forwardConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dialogContext.l10n.forwardConfirmBody(
                destination.customer.displayName,
                _channelOf(dialogContext, destination),
              ),
            ),
            const SizedBox(height: Space.md),
            // What is about to be sent, so it is never a surprise.
            if (text.isNotEmpty)
              Text(
                text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            if (message.attachments.isNotEmpty)
              Text(
                dialogContext.l10n.forwardAttachmentCount(
                  message.attachments.length,
                ),
                style: Theme.of(dialogContext).textTheme.labelMedium,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => decide(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('forwardConfirmSend'),
            onPressed: () => decide(dialogContext, true),
            child: Text(dialogContext.l10n.forwardMessageAction),
          ),
        ],
      ),
    );
    _confirming = false;
    if (ok == true && mounted) await _send(destination);
  }

  Future<void> _send(Conversation destination) async {
    // The guard that makes a second tap, or a second confirmation, a no-op.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final name = destination.customer.displayName;
    final clientId = _clientIds.putIfAbsent(
      destination.id,
      () =>
          'fwd-${widget.message.id}-${destination.id}-'
          '${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      await ref
          .read(messageForwarderProvider)
          .forward(
            message: widget.message,
            destinationConversationId: destination.id,
            clientMessageId: clientId,
          );
      if (!mounted) return;
      _refreshAfterForward(destination.id);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.forwardedToMessage(name))));
    } on ForwardDestinationBlocked catch (blocked) {
      // It could not take the message when checked, so nothing was
      // transferred. Say why, and stop offering it if that is its state now.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = forwardErrorMessage(l10n, blocked);
        if (blocked.hidesDestination) {
          _unfit.add(destination.id);
          _selected = null;
        }
      });
    } on SessionExpiredException {
      // The app is already taking the agent back to sign in.
      if (mounted) setState(() => _busy = false);
    } on RequestCancelledException {
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = forwardErrorMessage(l10n, error);
      });
    }
  }

  /// The destination now has a new message: bring the lists that show it up
  /// to date. The destination's own thread, if it is loaded, is re-read; the
  /// server's realtime event does the same for anyone else watching.
  void _refreshAfterForward(int destinationId) {
    unawaited(ref.read(inboxControllerProvider.notifier).refreshQuietly());
    ref.invalidate(conversationCountsProvider);
    final thread = conversationControllerProvider(destinationId);
    if (ref.exists(thread)) {
      unawaited(ref.read(thread.notifier).refreshFromServer());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = AppColors.of(context).mutedForeground;
    final results = ref.watch(
      forwardDestinationsProvider((
        search: _search,
        excludeId: widget.sourceConversationId,
      )),
    );
    final selected = _selected;

    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.forwardSheetTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Space.md),
                TextField(
                  key: const Key('forwardSearchField'),
                  controller: _searchController,
                  enabled: !_busy,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.forwardSearchHint,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  l10n.forwardChooseHint,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.forwardEligibilityHint,
                  key: const Key('forwardEligibilityHint'),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                Flexible(
                  child: results.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: Space.xl),
                      child: LoadingState(),
                    ),
                    error: (error, _) => ErrorStateView(
                      error: error,
                      onRetry: () =>
                          ref.invalidate(forwardDestinationsProvider),
                    ),
                    data: (found) {
                      final shown = [
                        for (final c in found.items)
                          if (!_unfit.contains(c.id)) c,
                      ];
                      final hidden =
                          found.hidden + (found.items.length - shown.length);
                      if (shown.isEmpty) {
                        // Told apart: nothing matched, or things matched and
                        // none of them can be sent to.
                        final noneEligible = hidden > 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Space.lg,
                          ),
                          child: Text(
                            noneEligible
                                ? l10n.forwardNoEligible
                                : l10n.forwardNoResults,
                            key: Key(
                              noneEligible
                                  ? 'forwardNoEligible'
                                  : 'forwardNoResults',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      }
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          for (final c in shown)
                            _DestinationRow(
                              conversation: c,
                              channel: _channelOf(context, c),
                              selected: selected?.id == c.id,
                              enabled: !_busy,
                              onTap: () => setState(() {
                                _selected = c;
                                _error = null;
                              }),
                            ),
                          if (hidden > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.sm,
                              ),
                              child: Text(
                                l10n.forwardHiddenCount(hidden),
                                key: const Key('forwardHiddenNote'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                          if (found.hasMore)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.sm,
                              ),
                              child: Text(
                                l10n.forwardMoreHint,
                                key: const Key('forwardMoreHint'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    _error!,
                    key: const Key('forwardError'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: Space.md),
                FilledButton(
                  key: const Key('forwardConfirmButton'),
                  onPressed: selected == null || _busy ? null : _confirm,
                  child: _busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: Space.sm),
                            Text(l10n.forwardingInProgress),
                          ],
                        )
                      : Text(
                          selected == null
                              ? l10n.forwardMessageAction
                              : l10n.forwardToNamed(
                                  selected.customer.displayName,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One conversation to choose: the customer, the channel and account it is
/// on, and their number — enough to tell two threads of one customer, or two
/// customers of one name, apart.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.conversation,
    required this.channel,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Conversation conversation;
  final String channel;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = conversation.customer;
    final phone = customer.phone.trim();
    return ListTile(
      key: ValueKey('forwardDestination_${conversation.id}'),
      contentPadding: EdgeInsets.zero,
      selected: selected,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: InitialsAvatar(
        initials: customer.initials,
        imageUrl: customer.avatarUrl,
        size: 36,
        provider: conversation.provider,
      ),
      // Names are customer data — never translated.
      title: Text(
        customer.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(channel, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (phone.isNotEmpty)
            Text(
              phone,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
    );
  }
}
