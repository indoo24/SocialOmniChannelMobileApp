/// Inbox filters.
///
/// A bottom sheet rather than the web's persistent sidebar — the same filters,
/// in the place a phone puts secondary controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
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
                Text('Filters', style: theme.textTheme.titleLarge),
                const Spacer(),
                if (!filters.isEmpty)
                  TextButton(
                    onPressed: () {
                      controller.clear();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),

            _SectionLabel('Assignment'),
            Wrap(
              spacing: Space.sm,
              children: [
                FilterChip(
                  label: const Text('Assigned to me'),
                  selected: filters.assignedToMe,
                  onSelected: (selected) => controller.update(
                    filters.copyWith(
                      assignedToMe: selected,
                      unassigned: selected ? false : filters.unassigned,
                    ),
                  ),
                ),
                FilterChip(
                  label: const Text('Unassigned'),
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
            _SectionLabel('Status'),
            _ChoiceRow(
              options: _statuses,
              selected: filters.status,
              onSelected: (value) => controller.update(
                value == null
                    ? filters.copyWith(clearStatus: true)
                    : filters.copyWith(status: value),
              ),
            ),

            const SizedBox(height: Space.lg),
            _SectionLabel('Priority'),
            _ChoiceRow(
              options: _priorities,
              selected: filters.priority,
              onSelected: (value) => controller.update(
                value == null
                    ? filters.copyWith(clearPriority: true)
                    : filters.copyWith(priority: value),
              ),
            ),

            const SizedBox(height: Space.lg),
            _SectionLabel('Channel'),
            _ChoiceRow(
              options: _providers,
              selected: filters.provider,
              onSelected: (value) => controller.update(
                value == null
                    ? filters.copyWith(clearProvider: true)
                    : filters.copyWith(provider: value),
              ),
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Show results'),
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
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;

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
            label: Text(humanizeEnum(option)),
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
