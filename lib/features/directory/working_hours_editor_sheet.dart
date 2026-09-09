/// Working hours interval editor modal sheet.
///
/// Allows configuring working intervals for a specific weekday (0 = Monday .. 6 = Sunday).
/// Supports multiple intervals per day, validates start < end and non-overlapping constraints,
/// and returns the configured list of [WorkingHoursWindow] or empty if marked as not working.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/directory.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';

/// Opens the working hours editor for [weekday] and returns the updated intervals,
/// or `null` if cancelled.
Future<List<WorkingHoursWindow>?> showWorkingHoursEditorSheet(
  BuildContext context, {
  required int weekday,
  required List<WorkingHoursWindow> currentWindows,
  required String timezone,
}) {
  return showModalBottomSheet<List<WorkingHoursWindow>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (context, controller) => _WorkingHoursEditorSheet(
        weekday: weekday,
        currentWindows: currentWindows,
        timezone: timezone,
        scrollController: controller,
      ),
    ),
  );
}

class _WorkingHoursEditorSheet extends StatefulWidget {
  const _WorkingHoursEditorSheet({
    required this.weekday,
    required this.currentWindows,
    required this.timezone,
    required this.scrollController,
  });

  final int weekday;
  final List<WorkingHoursWindow> currentWindows;
  final String timezone;
  final ScrollController scrollController;

  @override
  State<_WorkingHoursEditorSheet> createState() =>
      _WorkingHoursEditorSheetState();
}

class _IntervalEntry {
  _IntervalEntry({required this.startCtrl, required this.endCtrl});

  final TextEditingController startCtrl;
  final TextEditingController endCtrl;

  void dispose() {
    startCtrl.dispose();
    endCtrl.dispose();
  }
}

class _WorkingHoursEditorSheetState extends State<_WorkingHoursEditorSheet> {
  final List<_IntervalEntry> _entries = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final dayWindows = widget.currentWindows
        .where((w) => w.weekday == widget.weekday)
        .toList();

    if (dayWindows.isEmpty) {
      _entries.add(
        _IntervalEntry(
          startCtrl: TextEditingController(text: '09:00'),
          endCtrl: TextEditingController(text: '17:00'),
        ),
      );
    } else {
      for (final w in dayWindows) {
        _entries.add(
          _IntervalEntry(
            startCtrl: TextEditingController(text: w.startTime),
            endCtrl: TextEditingController(text: w.endTime),
          ),
        );
      }
    }
  }

  final List<_IntervalEntry> _disposed = [];

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    for (final e in _disposed) {
      e.dispose();
    }
    super.dispose();
  }

  void _addInterval() {
    setState(() {
      _error = null;
      _entries.add(
        _IntervalEntry(
          startCtrl: TextEditingController(text: '09:00'),
          endCtrl: TextEditingController(text: '17:00'),
        ),
      );
    });
  }

  void _removeInterval(int index) {
    setState(() {
      _error = null;
      final entry = _entries.removeAt(index);
      _disposed.add(entry);
    });
  }

  void _clearAll() {
    setState(() {
      _error = null;
      _disposed.addAll(_entries);
      _entries.clear();
    });
  }

  int? _parseMinutes(String time) {
    final trimmed = time.trim();
    final regex = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');
    final match = regex.firstMatch(trimmed);
    if (match == null) return null;
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    return hours * 60 + minutes;
  }

  String _formatTime(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final currentMinutes = _parseMinutes(controller.text) ?? 9 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
    );
    if (picked != null) {
      final formatted = _formatTime(picked.hour * 60 + picked.minute);
      controller.text = formatted;
      setState(() => _error = null);
    }
  }

  void _save() {
    if (_entries.isEmpty) {
      Navigator.of(context).pop(<WorkingHoursWindow>[]);
      return;
    }

    final parsedWindows = <WorkingHoursWindow>[];

    for (int i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final startMin = _parseMinutes(entry.startCtrl.text);
      final endMin = _parseMinutes(entry.endCtrl.text);

      if (startMin == null || endMin == null) {
        setState(() => _error = context.l10n.invalidTimeFormatError);
        return;
      }

      if (startMin >= endMin) {
        setState(() => _error = context.l10n.invalidIntervalStartBeforeEnd);
        return;
      }

      parsedWindows.add(
        WorkingHoursWindow(
          weekday: widget.weekday,
          startTime: _formatTime(startMin),
          endTime: _formatTime(endMin),
          crossesMidnight: false,
        ),
      );
    }

    // Check for overlapping intervals
    for (int i = 0; i < parsedWindows.length; i++) {
      for (int j = i + 1; j < parsedWindows.length; j++) {
        if (parsedWindows[i].overlapsWith(parsedWindows[j])) {
          setState(() => _error = context.l10n.overlappingIntervalsError);
          return;
        }
      }
    }

    Navigator.of(context).pop(parsedWindows);
  }

  String _weekdayTitle(BuildContext context, int day) => switch (day) {
    0 => context.l10n.weekdayMonday,
    1 => context.l10n.weekdayTuesday,
    2 => context.l10n.weekdayWednesday,
    3 => context.l10n.weekdayThursday,
    4 => context.l10n.weekdayFriday,
    5 => context.l10n.weekdaySaturday,
    _ => context.l10n.weekdaySunday,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _weekdayTitle(context, widget.weekday),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    context.l10n.workingHoursTimezoneHelper(widget.timezone),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _entries.isEmpty ? null : _clearAll,
              child: Text(context.l10n.clearDayHoursAction),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        if (_error != null) ...[
          InlineError(message: _error!),
          const SizedBox(height: Space.md),
        ],
        if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Center(
              child: Text(
                context.l10n.dayNotWorking,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (int i = 0; i < _entries.length; i++) ...[
            Row(
              key: ObjectKey(_entries[i]),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _entries[i].startCtrl,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: InputDecoration(
                      labelText: context.l10n.startTimeLabel,
                      hintText: '09:00',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.access_time, size: 18),
                        onPressed: () =>
                            _pickTime(context, _entries[i].startCtrl),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.sm),
                  child: Text('—', style: TextStyle(fontSize: 16)),
                ),
                Expanded(
                  child: TextField(
                    controller: _entries[i].endCtrl,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: InputDecoration(
                      labelText: context.l10n.endTimeLabel,
                      hintText: '17:00',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.access_time, size: 18),
                        onPressed: () =>
                            _pickTime(context, _entries[i].endCtrl),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove interval',
                  color: theme.colorScheme.error,
                  onPressed: () => _removeInterval(i),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
          ],
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: _addInterval,
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.l10n.addIntervalAction),
        ),
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: Space.md),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _save,
              child: Text(context.l10n.commonSave),
            ),
          ],
        ),
      ],
    );
  }
}
