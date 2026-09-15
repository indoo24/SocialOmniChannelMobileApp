/// Shared CSV export flow: fetch the bytes an export repository method
/// returns, write them to a temp file, then hand that file to the platform
/// share sheet.
///
/// One function for both Customers and Inbox exports rather than two copies
/// of the same download/write/share/error sequence — the only thing that
/// differs between them is which repository method supplies the bytes and
/// what the file is named.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../api/api_exception.dart';
import '../../l10n/l10n_extensions.dart';

/// Fetches CSV bytes via [fetch], writes them to a temp file named
/// `[fileNamePrefix]_` followed by a millisecond timestamp and `.csv`, and
/// opens the share sheet.
///
/// Never truncates or samples: [fetch] is expected to call the backend's
/// export endpoint directly (not the paginated list), so the file always
/// contains every currently-filtered row, not just what is loaded on screen.
///
/// Shows a snackbar on failure — an `ApiException`'s own message for a
/// refused or rate-limited (429) export, a generic one otherwise. Never fails
/// silently.
Future<void> exportCsvAndShare(
  BuildContext context, {
  required Future<List<int>> Function() fetch,
  required String fileNamePrefix,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await fetch();
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${fileNamePrefix}_$timestamp.csv');
    await file.writeAsBytes(bytes, flush: true);

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
  } on ApiException catch (error) {
    if (!context.mounted) return;
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
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.exportFailedMessage),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
