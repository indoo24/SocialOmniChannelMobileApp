/// State representation and provider for the Dashboard date-range filter.
///
/// Supports standard presets ('today', 'last_7_days', 'last_30_days',
/// 'this_month', 'last_month') as well as custom date ranges.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_extensions.dart';

/// Presets supported by the OpenAPI `/api/dashboard/` endpoint.
enum DashboardPreset {
  today('today'),
  last7Days('last_7_days'),
  last30Days('last_30_days'),
  thisMonth('this_month'),
  lastMonth('last_month');

  const DashboardPreset(this.apiValue);

  /// The exact parameter string expected by `GET /api/dashboard/?preset=...`.
  final String apiValue;

  /// Localized display label.
  String label(BuildContext context) => switch (this) {
    DashboardPreset.today => context.l10n.dateFilterToday,
    DashboardPreset.last7Days => context.l10n.dateFilterLast7Days,
    DashboardPreset.last30Days => context.l10n.dateFilterLast30Days,
    DashboardPreset.thisMonth => context.l10n.dateFilterThisMonth,
    DashboardPreset.lastMonth => context.l10n.dateFilterLastMonth,
  };

  /// Computes the calendar bounds (inclusive) for reference and tests.
  (DateTime from, DateTime to) calculateRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DashboardPreset.today => (today, today),
      DashboardPreset.last7Days => (
        today.subtract(const Duration(days: 6)),
        today,
      ),
      DashboardPreset.last30Days => (
        today.subtract(const Duration(days: 29)),
        today,
      ),
      DashboardPreset.thisMonth => (
        DateTime(today.year, today.month, 1),
        today,
      ),
      DashboardPreset.lastMonth => (
        DateTime(
          today.month == 1 ? today.year - 1 : today.year,
          today.month == 1 ? 12 : today.month - 1,
          1,
        ),
        DateTime(today.year, today.month, 0), // Last day of previous month
      ),
    };
  }
}

/// The active filter state for the dashboard.
class DashboardDateFilterState {
  const DashboardDateFilterState({
    this.preset = DashboardPreset.today,
    this.customFrom,
    this.customTo,
  });

  /// The active preset, or `null` if a custom range is active.
  final DashboardPreset? preset;

  /// Custom range start date, local.
  final DateTime? customFrom;

  /// Custom range end date, local.
  final DateTime? customTo;

  /// Whether a custom date range is currently active.
  bool get isCustom => preset == null && customFrom != null && customTo != null;

  /// `YYYY-MM-DD` string for the custom `from` query parameter.
  String? get fromApiString =>
      customFrom != null ? _toIsoDate(customFrom!) : null;

  /// `YYYY-MM-DD` string for the custom `to` query parameter.
  String? get toApiString => customTo != null ? _toIsoDate(customTo!) : null;

  /// Formats date to `YYYY-MM-DD`.
  static String _toIsoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Formats date to `MM/dd/yyyy`.
  static String formatMmDdYyyy(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$m/$day/${d.year}';
  }

  /// Formats the active filter for display on the trigger button.
  String displayLabel(BuildContext context) {
    if (preset != null) {
      return preset!.label(context);
    }
    if (isCustom) {
      return '${formatMmDdYyyy(customFrom!)} – ${formatMmDdYyyy(customTo!)}';
    }
    return context.l10n.dateFilterToday;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardDateFilterState &&
          runtimeType == other.runtimeType &&
          preset == other.preset &&
          customFrom == other.customFrom &&
          customTo == other.customTo;

  @override
  int get hashCode => Object.hash(preset, customFrom, customTo);
}

/// Notifier managing the selected dashboard date range filter.
class DashboardDateFilterNotifier extends Notifier<DashboardDateFilterState> {
  @override
  DashboardDateFilterState build() => const DashboardDateFilterState();

  /// Switches to one of the standard presets.
  void selectPreset(DashboardPreset preset) {
    state = DashboardDateFilterState(preset: preset);
  }

  /// Sets a custom date range and invalidates any active preset.
  void selectCustomRange({required DateTime from, required DateTime to}) {
    state = DashboardDateFilterState(
      preset: null,
      customFrom: DateTime(from.year, from.month, from.day),
      customTo: DateTime(to.year, to.month, to.day),
    );
  }

  /// Resets to the default "Today" preset.
  void reset() {
    state = const DashboardDateFilterState();
  }
}

/// Provider for the dashboard date filter state.
final dashboardDateFilterProvider =
    NotifierProvider<DashboardDateFilterNotifier, DashboardDateFilterState>(
      DashboardDateFilterNotifier.new,
    );
