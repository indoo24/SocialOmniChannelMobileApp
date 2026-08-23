/// Deactivate Employee — `DELETE /employees/{id}/`.
///
/// Despite the verb this does not delete the row (see the doc comment on
/// `DirectoryRepository.deactivateEmployee`), so the confirmation below is
/// careful to say "deactivate", never "delete" — matching the spec's "no
/// 'Delete permanently' wording." Follows the same
/// `showDialog<bool>` confirm-then-act shape as `conversation_screen.dart`'s
/// `_confirmDeleteMessage`.
///
/// The backend refuses to deactivate the caller's own account with a 400.
/// The action is also hidden here for that case — see
/// `employees_screen.dart`'s call site — but the 400 path stays reachable
/// (another admin's session, a race between two admins) and is handled like
/// any other validation error rather than assumed impossible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/directory.dart';
import '../../core/providers.dart';
import '../../l10n/l10n_extensions.dart';
import 'directory_providers.dart';

Future<void> confirmDeactivateEmployee(
  BuildContext context,
  WidgetRef ref, {
  required DirectoryEmployee employee,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.deactivateEmployeeConfirmTitle),
      content: Text(
        dialogContext.l10n.deactivateEmployeeConfirmBody(employee.fullName),
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
          child: Text(dialogContext.l10n.deactivateAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  try {
    await ref.read(directoryRepositoryProvider).deactivateEmployee(employee.id);
    if (!context.mounted) return;
    ref.invalidate(employeeDirectoryProvider);
    ref.invalidate(onlineEmployeesProvider);
    if (employee.teamIds.isNotEmpty) ref.invalidate(teamsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.employeeDeactivatedSnackbar(employee.fullName),
        ),
      ),
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
