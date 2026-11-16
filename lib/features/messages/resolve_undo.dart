/// "Conversation resolved", with Undo — the feedback after a resolve.
///
/// Restored from the header Resolved button (now "تم البيع") for the
/// conversation actions sheet's Resolve button: the same snack bar, the same
/// five-second Undo through the same status endpoint.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../l10n/l10n_extensions.dart';
import 'conversation_controller.dart';

/// How long the Undo offered after resolving stays available.
const resolveUndoWindow = Duration(seconds: 5);

/// Shows "Conversation resolved" with Undo, after a resolve the server has
/// accepted. Undo puts the conversation back to [previousStatus] through the
/// status endpoint, via the conversation's controller so the thread and the
/// inbox both follow — and says "reopened" only once the server agreed.
///
/// Everything Undo needs is taken from [context] now: the agent may have left
/// the conversation by the time they tap it.
void showResolveUndoSnackBar(
  BuildContext context, {
  required int conversationId,
  required String previousStatus,
  Duration undoWindow = resolveUndoWindow,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final l10n = context.l10n;
  final errorColor = Theme.of(context).colorScheme.error;
  var undone = false;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('resolveUndoSnackBar'),
        content: Text(l10n.conversationResolvedSnackbar),
        duration: undoWindow,
        // A snack bar with an action otherwise stays until dismissed; the
        // Undo window is meant to close by itself.
        persist: false,
        action: SnackBarAction(
          key: const Key('resolveUndoAction'),
          label: l10n.undoAction,
          onPressed: () async {
            // One Undo per resolve, however the action is reached.
            if (undone) return;
            undone = true;
            if (kDebugMode) {
              debugPrint(
                '[RESOLVE_UNDO] conversation=$conversationId '
                'restoring=$previousStatus',
              );
            }
            try {
              await container
                  .read(conversationControllerProvider(conversationId).notifier)
                  .updateStatus(previousStatus);
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.conversationReopenedSnackbar)),
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                  '[RESOLVE_UNDO] conversation=$conversationId failed '
                  '(${e.runtimeType})',
                );
              }
              // Nothing changed locally: the controller only applies a
              // status the server accepted, so it still reads Resolved.
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    e is ApiException && e.message.isNotEmpty
                        ? e.message
                        : l10n.resolveUndoFailedMessage,
                  ),
                  backgroundColor: errorColor,
                ),
              );
            }
          },
        ),
      ),
    );
}
