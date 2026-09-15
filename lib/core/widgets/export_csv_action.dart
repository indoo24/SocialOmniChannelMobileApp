/// The "Export CSV" app-bar action Customers and Inbox both use.
///
/// A `PopupMenuButton` with one item today rather than a bare `IconButton`:
/// both screens' app bars are already close to full (search, filters,
/// notifications, account menu), and a menu leaves room to add more
/// per-screen actions later without another icon competing for space —
/// matching "place the action where it fits naturally" rather than copying
/// the web toolbar's dedicated button verbatim.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../utils/csv_export.dart';

class ExportCsvAction extends StatefulWidget {
  const ExportCsvAction({
    required this.fetch,
    required this.fileNamePrefix,
    super.key,
  });

  final Future<List<int>> Function() fetch;
  final String fileNamePrefix;

  @override
  State<ExportCsvAction> createState() => _ExportCsvActionState();
}

class _ExportCsvActionState extends State<ExportCsvAction> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await exportCsvAndShare(
        context,
        fetch: widget.fetch,
        fileNamePrefix: widget.fileNamePrefix,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_exporting) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return PopupMenuButton<void>(
      key: const Key('export-csv-menu'),
      tooltip: context.l10n.exportCsvAction,
      icon: const Icon(Icons.ios_share_outlined),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('export-csv-item'),
          onTap: _export,
          child: Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 12),
              Text(context.l10n.exportCsvAction),
            ],
          ),
        ),
      ],
    );
  }
}
