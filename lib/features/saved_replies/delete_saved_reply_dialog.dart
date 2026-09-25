/// Delete a saved reply — `DELETE /saved-replies/{id}/`.
///
/// The endpoint deactivates rather than deletes (see
/// `SavedRepliesRepository.deactivate`'s doc comment), but the web Settings
/// screen and this dialog both call the action "Delete" — from the caller's
/// side it removes the reply from every list and releases its shortcut, and
/// there is no "reactivate" affordance on mobile, so presenting it as
/// deactivation-with-a-different-name would only be confusing. Follows the
/// same `showDialog<bool>` confirm-then-act shape as
/// `deactivate_team_dialog.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../l10n/l10n_extensions.dart';
import 'saved_replies_providers.dart';
import 'saved_reply.dart';

Future<void> confirmDeleteSavedReply(
  BuildContext context,
  WidgetRef ref, {
  required SavedReply reply,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.deleteSavedReplyConfirmTitle),
      content: Text(
        dialogContext.l10n.deleteSavedReplyConfirmBody(reply.title),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.deleteSavedReplyAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  try {
    await ref.read(savedRepliesRepositoryProvider).deactivate(reply.id);
    if (!context.mounted) return;
    ref.invalidate(manageableSavedRepliesProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.savedReplyDeletedSnackbar)),
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
