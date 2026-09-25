/// Shared CSV export flow: fetch the bytes an export repository method
/// returns, write them to a user-accessible CSV file named
/// `[fileNamePrefix]_YYYY-MM-DD.csv` (avoiding collisions), show a success
/// message with an "Open" action, and optionally share the file.
///
/// One function for both Customers and Inbox exports rather than two copies
/// of the same download/write/share/error sequence — the only thing that
/// differs between them is which repository method supplies the bytes and
/// what the file is named.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../api/api_exception.dart';
import 'attachment_helper.dart';
import '../../l10n/l10n_extensions.dart';

/// Fetches CSV bytes via [fetch], writes them to an accessible file named
/// `[fileNamePrefix]_YYYY-MM-DD.csv` (avoiding collisions if a file with the
/// same name already exists), displays a success snackbar with an "Open"
/// action to view the file in an installed app, and optionally opens the
/// platform share sheet if [share] is true.
///
/// Never truncates or samples: [fetch] is expected to call the backend's
/// export endpoint directly (not the paginated list), so the file always
/// contains every currently-filtered row, not just what is loaded on screen.
///
/// Shows a snackbar on failure — an `ApiException`'s own message for a
/// refused or rate-limited (429) export, a generic one otherwise. Never fails
/// silently.
Future<File?> exportCsvAndShare(
  BuildContext context, {
  required Future<List<int>> Function() fetch,
  required String fileNamePrefix,
  bool share = true,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await fetch();
    final dir = await AttachmentHelper.getAccessibleDirectory();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final baseName = '${fileNamePrefix}_$dateStr.csv';
    final targetPath = AttachmentHelper.getUniqueFilePath(dir, baseName);
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);

    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.csvExportSuccessMessage),
          action: SnackBarAction(
            label: context.l10n.openFileAction,
            onPressed: () =>
                AttachmentHelper.openFile(file.path, context: context),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    if (share) {
      // `SharePlatform.instance` directly, not the `SharePlus` wrapper: that
      // wrapper caches `SharePlatform.instance` in a `static final` the first
      // time anything touches it, so a widget test that swaps the platform
      // fake in `setUp` (after some earlier test already read it) would keep
      // talking to the real, channel-backed implementation — which has no
      // handler under `flutter test` and hangs `pumpAndSettle` forever. Reading
      // `SharePlatform.instance` fresh on every call is what `SharePlus.share`
      // does internally anyway, so this changes nothing at runtime.
      await SharePlatform.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]),
      );
    }

    return file;
  } on ApiException catch (error) {
    if (!context.mounted) return null;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error.statusCode == 429
              ? context.l10n.exportRateLimitedMessage
              : error.message,
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return null;
  } catch (_) {
    if (!context.mounted) return null;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.exportFailedMessage),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    return null;
  }
}
