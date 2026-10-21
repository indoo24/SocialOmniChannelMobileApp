/// Personal conversation pinning: `POST` / `DELETE /conversations/{id}/pin/`.
///
/// A pin is the signed-in employee's own; nobody else's inbox changes, and
/// pinning touches nothing else about the conversation (assignment, status,
/// unread state). The server decides both the pin state — its answer's
/// `is_pinned` is what is shown — and where a pinned row sorts within the
/// current filter, so nothing here reorders the inbox by itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../messages/conversation_controller.dart';
import '../../core/providers.dart';
import 'inbox_controller.dart';

/// The conversations with a pin or unpin request on its way.
class PinningController extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// Pins or unpins [conversationId] and, once the server has confirmed,
  /// shows the confirmed state in the inbox and the open conversation.
  ///
  /// Resolves to the confirmed state, or to null without sending anything
  /// when a request for this conversation is already on its way (a second
  /// tap). Throws the request's [ApiException] when it fails; nothing on
  /// screen has changed then.
  Future<bool?> setPinned(int conversationId, {required bool pinned}) async {
    if (state.contains(conversationId)) return null;
    state = {...state, conversationId};
    try {
      final confirmed = await ref
          .read(conversationRepositoryProvider)
          .setPinned(conversationId, pinned: pinned);
      if (ref.exists(inboxControllerProvider)) {
        final inbox = ref.read(inboxControllerProvider.notifier);
        inbox.applyPinned(conversationId, isPinned: confirmed);
        // The server's order for the current filter: at the top of the list
        // it is merged in; scrolled down, "New activity" offers it instead
        // of moving rows under the agent.
        unawaited(inbox.refreshQuietly());
      }
      final detail = conversationControllerProvider(conversationId);
      if (ref.exists(detail)) {
        ref.read(detail.notifier).applyPinned(isPinned: confirmed);
      }
      return confirmed;
    } on ApiException catch (error) {
      // No longer this employee's to see: take the row out of the list.
      if (error.statusCode == 404 && ref.exists(inboxControllerProvider)) {
        ref
            .read(inboxControllerProvider.notifier)
            .removeConversation(conversationId);
      }
      rethrow;
    } finally {
      if (ref.mounted) state = {...state}..remove(conversationId);
    }
  }
}

final pinningProvider = NotifierProvider<PinningController, Set<int>>(
  PinningController.new,
);

/// What to tell the agent after a failed pin or unpin, and whether trying
/// again could help.
(String, bool) pinErrorMessage(AppLocalizations l10n, ApiException error) {
  if (error is NetworkException || error.statusCode >= 500) {
    return (l10n.pinRequestFailedMessage, true);
  }
  final code = error.code.toLowerCase();
  return switch (error.statusCode) {
    400 when code.contains('pin') && code.contains('limit') => (
      l10n.pinLimitReachedMessage,
      false,
    ),
    // The server's own reason (the pin limit among them) when it gave one.
    400 => (
      error.message.isNotEmpty ? error.message : l10n.pinRequestFailedMessage,
      false,
    ),
    403 => (l10n.pinPermissionDeniedMessage, false),
    404 => (l10n.conversationUnavailableMessage, false),
    _ => (l10n.pinRequestFailedMessage, false),
  };
}

/// Pins [conversationId] if [currentlyPinned] is false, unpins it otherwise,
/// and reports the outcome in a snack bar — success only once the server has
/// confirmed it. Everything needed afterwards is taken from [context] now,
/// so the outcome (and a Retry) still works if the screen has gone.
Future<void> toggleConversationPin(
  BuildContext context, {
  required int conversationId,
  required bool currentlyPinned,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final errorColor = Theme.of(context).colorScheme.error;

  Future<void> run() async {
    try {
      final confirmed = await container
          .read(pinningProvider.notifier)
          .setPinned(conversationId, pinned: !currentlyPinned);
      if (confirmed == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              confirmed
                  ? l10n.conversationPinnedMessage
                  : l10n.conversationUnpinnedMessage,
            ),
          ),
        );
    } on SessionExpiredException {
      // The app is already taking the agent back to sign in.
    } on RequestCancelledException {
      // Abandoned on purpose; nothing to report.
    } on ApiException catch (error) {
      final (message, retryable) = pinErrorMessage(l10n, error);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: errorColor,
            action: retryable
                ? SnackBarAction(label: l10n.retryButton, onPressed: run)
                : null,
          ),
        );
    }
  }

  return run();
}

/// The pin action's label and icon for a conversation in [pinned] state.
(String, IconData) pinActionLabel(AppLocalizations l10n, bool pinned) => pinned
    ? (l10n.unpinConversationAction, Icons.push_pin)
    : (l10n.pinConversationAction, Icons.push_pin_outlined);

/// The small pin shown on a pinned row. A tilted pin in the quiet text
/// colour, named for screen readers — distinct from the unread count, the
/// priority badge and the follow-up flag.
class PinnedIndicator extends StatelessWidget {
  const PinnedIndicator({this.size = 15, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.pinnedIndicator;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: Transform.rotate(
          angle: 0.6,
          child: Icon(
            Icons.push_pin,
            key: const Key('pinnedIndicator'),
            size: size,
            color: AppColors.of(context).mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// Long-press on an inbox row: the row's quick actions — for now, pinning.
Future<void> showConversationQuickActions(
  BuildContext context, {
  required Conversation conversation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Consumer(
        builder: (context, ref, _) {
          final busy = ref.watch(pinningProvider).contains(conversation.id);
          final (label, icon) = pinActionLabel(
            context.l10n,
            conversation.isPinned,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  0,
                  Space.lg,
                  Space.sm,
                ),
                child: Text(
                  conversation.customer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                key: const Key('quickActionPin'),
                leading: Icon(icon),
                title: Text(label),
                enabled: !busy,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  toggleConversationPin(
                    context,
                    conversationId: conversation.id,
                    currentlyPinned: conversation.isPinned,
                  );
                },
              ),
              const SizedBox(height: Space.sm),
            ],
          );
        },
      ),
    ),
  );
}
