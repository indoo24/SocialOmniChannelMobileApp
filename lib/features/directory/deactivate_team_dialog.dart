/// Deactivate Team — `DELETE /teams/{id}/`.
///
/// Despite the verb this does not delete the row (see the doc comment on
/// `DirectoryRepository.deactivateTeam`), so the confirmation below is
/// careful to say "deactivate", never "delete". Follows the same
/// `showDialog<bool>` confirm-then-act shape as `deactivate_employee_dialog.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../../l10n/l10n_extensions.dart';
import 'directory_providers.dart';

Future<void> confirmDeactivateTeam(
  BuildContext context,
  WidgetRef ref, {
  required Team team,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.deactivateTeamConfirmTitle),
      content: Text(dialogContext.l10n.deactivateTeamConfirmBody(team.name)),
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
          child: Text(dialogContext.l10n.deactivateAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  try {
    await ref.read(directoryRepositoryProvider).deactivateTeam(team.id);
    if (!context.mounted) return;
    ref.invalidate(teamsProvider);
    ref.invalidate(employeeDirectoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.teamDeactivatedSnackbar(team.name))),
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
