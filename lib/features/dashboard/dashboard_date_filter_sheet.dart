/// Dashboard date-range filter button and modal sheet.
///
/// Reproduces the Web dashboard's date-range filter popover on mobile:
/// - Presets: Today (default), Last 7 days, Last 30 days, This month, Last month
/// - Custom range: From / To date pickers with validation (from <= to, <= 366 days),
///   Cancel and Apply actions.
/// - Communicates with `dashboardDateFilterProvider`, which drives `dashboardProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/l10n_extensions.dart';
import 'dashboard_date_filter_state.dart';

/// Opens the date-range filter sheet.
Future<void> showDashboardDateFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _DashboardDateFilterSheet(),
  );
}

/// Compact outlined button displayed in the Dashboard header.
class DashboardDateFilterButton extends ConsumerWidget {
  const DashboardDateFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(dashboardDateFilterProvider);
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showDashboardDateFilterSheet(context),
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.xs),
                Flexible(
                  child: Text(
                    filterState.displayLabel(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardDateFilterSheet extends ConsumerStatefulWidget {
  const _DashboardDateFilterSheet();

  @override
  ConsumerState<_DashboardDateFilterSheet> createState() =>
      _DashboardDateFilterSheetState();
}

class _DashboardDateFilterSheetState
    extends ConsumerState<_DashboardDateFilterSheet> {
  DateTime? _from;
  DateTime? _to;
  String? _error;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(dashboardDateFilterProvider);
    if (filter.isCustom) {
      _from = filter.customFrom;
      _to = filter.customTo;
    }
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _from = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _to = picked;
        _error = null;
      });
    }
  }

  void _applyCustom() {
    if (_from == null || _to == null) {
      setState(() => _error = context.l10n.dateFilterInvalidRange);
      return;
    }

    final fromDate = DateTime(_from!.year, _from!.month, _from!.day);
    final toDate = DateTime(_to!.year, _to!.month, _to!.day);

    if (fromDate.isAfter(toDate)) {
      setState(() => _error = context.l10n.dateFilterInvalidRange);
      return;
    }

    if (toDate.difference(fromDate).inDays > 366) {
      setState(() => _error = context.l10n.dateFilterRangeExceedsLimit);
      return;
    }

    ref
        .read(dashboardDateFilterProvider.notifier)
        .selectCustomRange(from: fromDate, to: toDate);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(dashboardDateFilterProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.dateFilterTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.sm),
            for (final preset in DashboardPreset.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 0,
                ),
                visualDensity: VisualDensity.compact,
                title: Text(
                  preset.label(context),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        !filterState.isCustom && filterState.preset == preset
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                trailing: !filterState.isCustom && filterState.preset == preset
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  ref
                      .read(dashboardDateFilterProvider.notifier)
                      .selectPreset(preset);
                  Navigator.of(context).pop();
                },
              ),
            const Divider(height: Space.lg),
            Text(
              context.l10n.dateFilterCustomRange,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.dateFilterFrom,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      InkWell(
                        key: const ValueKey('dashboard_date_filter_from'),
                        onTap: _pickFromDate,
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _from != null
                                    ? DashboardDateFilterState.formatMmDdYyyy(
                                        _from!,
                                      )
                                    : context.l10n.dateFilterPlaceholder,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.dateFilterTo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      InkWell(
                        key: const ValueKey('dashboard_date_filter_to'),
                        onTap: _pickToDate,
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _to != null
                                    ? DashboardDateFilterState.formatMmDdYyyy(
                                        _to!,
                                      )
                                    : context.l10n.dateFilterPlaceholder,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: Space.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const SizedBox(width: Space.sm),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(80, 40),
                  ),
                  onPressed: _applyCustom,
                  child: Text(context.l10n.dateFilterApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
