/// Inbox filters.
///
/// A bottom sheet rather than the web's persistent sidebar — the same filters,
/// in the place a phone puts secondary controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import 'conversation_repository.dart';
import 'inbox_controller.dart';

const _statuses = [
  'NEW',
  'OPEN',
  'WAITING_CUSTOMER',
  'WAITING_INTERNAL',
  'RESOLVED',
  'CLOSED',
];
const _priorities = ['URGENT', 'HIGH', 'NORMAL', 'LOW'];
const _providers = ['WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'TIKTOK', 'MOCK'];

Future<void> showInboxFiltersSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _FiltersSheet(),
  );
}

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(inboxFiltersProvider);
    final controller = ref.read(inboxFiltersProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.l10n.filtersTitle, style: theme.textTheme.titleLarge),
                const Spacer(),
                if (!filters.isEmpty)
                  TextButton(
                    onPressed: () {
                      controller.clear();
                      Navigator.of(context).pop();
                    },
                    child: Text(context.l10n.clearAll),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),

            _SectionLabel(context.l10n.assignmentSection),
            Wrap(
              spacing: Space.sm,
              children: [
                FilterChip(
                  label: Text(context.l10n.assignedToMeFilter),
                  selected: filters.assignedToMe,
                  onSelected: (selected) => controller.update(
                    filters.copyWith(
                      assignedToMe: selected,
                      unassigned: selected ? false : filters.unassigned,
                    ),
                  ),
                ),
                FilterChip(
                  label: Text(context.l10n.unassignedFilter),
                  selected: filters.unassigned,
                  onSelected: (selected) => controller.update(
                    filters.copyWith(
                      unassigned: selected,
                      assignedToMe: selected ? false : filters.assignedToMe,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: Space.lg),
            _SectionLabel(context.l10n.statusSection),
            _ChoiceRow(
              options: _statuses,
              selected: filters.status,
              labelOf: (context, value) =>
                  ConversationBadges.status(context, value).$1,
              onSelected: (value) => controller.update(
                value == null
                    ? filters.copyWith(clearStatus: true)
                    : filters.copyWith(status: value),
              ),
            ),

            const SizedBox(height: Space.lg),
            _SectionLabel(context.l10n.prioritySection),
            _ChoiceRow(
              options: _priorities,
              selected: filters.priority,
              labelOf: (context, value) =>
                  ConversationBadges.priority(context, value).$1,
              onSelected: (value) => controller.update(
                value == null
                    ? filters.copyWith(clearPriority: true)
                    : filters.copyWith(priority: value),
              ),
            ),

            const SizedBox(height: Space.lg),
            _SectionLabel(context.l10n.channelSection),
            _ChoiceRow(
              options: _providers,
              selected: filters.provider,
              labelOf: ConversationBadges.providerLabel,
              onSelected: (value) => controller.update(
                value == null
                    ? filters.copyWith(clearProvider: true)
                    : filters.copyWith(provider: value),
              ),
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.showResultsButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;

  /// Maps a raw backend value (`'WAITING_CUSTOMER'`) to its localized label.
  final String Function(BuildContext context, String value) labelOf;

  /// Null clears the choice — tapping the selected chip again deselects it.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(labelOf(context, option)),
            selected: selected == option,
            onSelected: (isSelected) =>
                onSelected(isSelected ? option : null),
          ),
      ],
    );
  }
}

/// Exposed for tests: the filter set a sheet would produce.
ConversationFilters filtersWithStatus(
  ConversationFilters base,
  String? status,
) =>
    status == null
        ? base.copyWith(clearStatus: true)
        : base.copyWith(status: status);
