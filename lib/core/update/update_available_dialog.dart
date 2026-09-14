/// The "an update is available" dialog.
///
/// Presentational and optional-only: it offers, it never blocks. There is no
/// barrier lock, no `PopScope` interception and no force-update path — the
/// agent can dismiss it with the system back gesture, a scrim tap, or
/// "Later", and carry on working. Both buttons simply pop with a result and
/// leave the acting to the caller.
///
/// Follows the same plain `AlertDialog` + `showDialog<T>` shape as the rest of
/// this app's dialogs (`deactivate_team_dialog.dart` and friends) so it
/// inherits the theme's dialog surface, the Cairo text theme and the ambient
/// `Directionality` — which is what makes RTL, dark mode and text scaling work
/// here without this file mentioning any of them.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

/// What the agent chose. Returned by [showUpdateAvailableDialog]; `null` when
/// the dialog was dismissed without a choice (back gesture or scrim tap),
/// which is treated exactly like [later].
enum UpdateDialogChoice { updateNow, later }

/// Shows the optional-update dialog and resolves to the agent's choice.
///
/// [context] must sit *below* a `Navigator`. The caller (`AppUpdateBridge`)
/// is mounted in `MaterialApp.router`'s `builder`, which is above the
/// router's navigator and therefore has none of its own — it passes the
/// navigator's own context instead. Getting this wrong does not degrade
/// gracefully: `showDialog` throws, and the dialog simply never appears.
Future<UpdateDialogChoice?> showUpdateAvailableDialog(BuildContext context) {
  return showDialog<UpdateDialogChoice>(
    context: context,
    // Dismissible on purpose: this is an optional update (see the library
    // comment). The guard against a second dialog lives in the caller, not in
    // a modal barrier here.
    barrierDismissible: true,
    builder: (dialogContext) => const UpdateAvailableDialog(),
  );
}

/// The dialog body. Public so it can be pumped directly in tests without
/// standing up a navigator route.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: Text(l10n.updateAvailableTitle),
      content: Text(l10n.updateAvailableBody),
      // Stacked rather than side by side: "Update now" and "Later" are both
      // long enough in Arabic that a Row overflows a small phone once the
      // text scales up.
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(UpdateDialogChoice.updateNow),
          child: Text(l10n.updateNowAction),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(UpdateDialogChoice.later),
          child: Text(l10n.updateLaterAction),
        ),
      ],
    );
  }
}
