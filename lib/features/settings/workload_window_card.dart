/// Routing → "Distribution workload period": which window the allocator
/// counts received conversations over, and the live received-vs-held figures
/// for it — the mobile counterpart of the web's routing-settings section.
///
/// ## Contract
///
/// * The window is the routing policy's `workload_window` (`1h` | `24h` |
///   `7d` | `30d`), changed with `PATCH /api/routing/policy/`. It is an
///   organization setting — choosing a period changes how the allocator
///   distributes conversations, not just what this card shows.
/// * The figures come from `GET /api/routing/workload/`, which takes no
///   parameters: it always reports the policy's configured window, in the
///   allocator's order. Nothing is counted or sorted here.
/// * Both require `routing.manage`; the Routing tab is already gated on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/routing_policy.dart';
import '../../core/models/routing_workload.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/shimmer.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';

class WorkloadWindowCard extends ConsumerStatefulWidget {
  const WorkloadWindowCard({required this.policy, super.key});

  final RoutingPolicy policy;

  @override
  ConsumerState<WorkloadWindowCard> createState() => _WorkloadWindowCardState();
}

class _WorkloadWindowCardState extends ConsumerState<WorkloadWindowCard> {
  /// The window being saved right now. Only marks that chip as pending —
  /// the selection stays on the confirmed window until the backend accepts.
  WorkloadWindow? _saving;

  /// The selected window is the routing policy's, and only the policy's: a
  /// load, a refresh, a save's response or a change made on the web all
  /// arrive through it. Nothing here keeps a copy that could go stale.
  String get _selected => widget.policy.workloadWindow;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _select(WorkloadWindow window) async {
    if (_saving != null || window.apiValue == _selected) return;
    setState(() => _saving = window);
    try {
      final saved = await ref
          .read(directoryRepositoryProvider)
          .updateRoutingPolicy(workloadWindow: window.apiValue);
      // The response is the policy as saved: it becomes the policy, so the
      // selection moves only to what the backend actually stored.
      ref.read(routingPolicyProvider.notifier).confirm(saved);
      // The figures are for the policy's window: the new window's numbers
      // replace the old, never sit beside them.
      ref.invalidate(routingWorkloadProvider);
      if (mounted) _showMessage(context.l10n.workloadWindowSaved);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  static String _label(BuildContext context, WorkloadWindow window) =>
      switch (window) {
        WorkloadWindow.lastHour => context.l10n.workloadWindowLastHour,
        WorkloadWindow.last24Hours => context.l10n.workloadWindowLast24Hours,
        WorkloadWindow.last7Days => context.l10n.workloadWindowLast7Days,
        WorkloadWindow.last30Days => context.l10n.workloadWindowLast30Days,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final enabled = widget.policy.isEnabled;

    return Card(
      key: const ValueKey('workloadWindowCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.workloadWindowTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(
              context.l10n.workloadWindowHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.xs),
            Text(
              context.l10n.workloadWindowNote,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final window in WorkloadWindow.values)
                  _WindowChip(
                    key: ValueKey('workloadWindow_${window.apiValue}'),
                    label: _label(context, window),
                    selected: window.apiValue == _selected,
                    pending: window == _saving,
                    // As on the web: only while automatic assignment is on
                    // (the window only matters to the allocator), and one
                    // change at a time.
                    onSelected: enabled && _saving == null
                        ? () => _select(window)
                        : null,
                  ),
              ],
            ),
            if (enabled) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.lg),
                child: Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              Text(
                context.l10n.workloadPreviewTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                context.l10n.workloadPreviewHint,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: Space.sm),
              _WorkloadFigures(
                selectedWindow: _selected,
                saving: _saving != null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One period option. Selected is filled with the primary colour and
/// primary-foreground text, as on the web; unselected keeps the app's chip
/// look. Set here because the theme's chips resolve their selected fill to
/// the same muted colour as their background.
class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.pending,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;

  /// Being saved: marked with a spinner, not selected until confirmed.
  final bool pending;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onSelected != null;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      avatar: pending
          ? const SizedBox.square(
              key: ValueKey('workloadWindowPending'),
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      selectedColor: enabled
          ? scheme.primary
          : scheme.primary.withValues(alpha: 0.6),
      side: selected ? BorderSide(color: scheme.primary) : null,
      labelStyle: selected
          ? TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600)
          : null,
      onSelected: onSelected == null ? null : (_) => onSelected!(),
    );
  }
}

class _WorkloadFigures extends ConsumerWidget {
  const _WorkloadFigures({required this.selectedWindow, required this.saving});

  final String selectedWindow;
  final bool saving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    // A period change in flight means the figures on hand belong to the old
    // period: show loading rather than present them under the new one.
    if (saving) return const _WorkloadSkeleton();

    return ref
        .watch(routingWorkloadProvider)
        .when(
          loading: () => const _WorkloadSkeleton(),
          error: (error, _) => Column(
            key: const ValueKey('workloadPreviewError'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InlineError(
                message: error is ApiException
                    ? error.message
                    : context.l10n.workloadPreviewLoadFailed,
              ),
              TextButton(
                onPressed: () => ref.invalidate(routingWorkloadProvider),
                child: Text(context.l10n.retryButton),
              ),
            ],
          ),
          data: (preview) {
            // Figures computed for a different window than the one selected
            // (the refetch after a change has not landed yet) are stale.
            if (preview.workloadWindow.isNotEmpty &&
                selectedWindow.isNotEmpty &&
                preview.workloadWindow != selectedWindow) {
              return const _WorkloadSkeleton();
            }
            if (preview.employees.isEmpty || preview.nobodyRoutable) {
              return Padding(
                key: const ValueKey('workloadPreviewEmpty'),
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Text(
                  context.l10n.workloadPreviewEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              );
            }
            // The backend's order is the allocator's: kept exactly.
            return Column(
              key: const ValueKey('workloadPreviewList'),
              children: [
                for (var i = 0; i < preview.employees.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  _WorkloadRowTile(row: preview.employees[i]),
                ],
              ],
            );
          },
        );
  }
}

class _WorkloadRowTile extends StatelessWidget {
  const _WorkloadRowTile({required this.row});

  final WorkloadRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final tabular = const [FontFeature.tabularFigures()];

    return Padding(
      key: ValueKey('workloadRow_${row.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              row.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Space.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (row.routable)
                Text(
                  context.l10n.workloadPreviewReceived(row.received),
                  key: const ValueKey('workloadReceived'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                )
              else
                Text(
                  context.l10n.workloadPreviewNotReceiving,
                  key: const ValueKey('workloadNotReceiving'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              Text(
                context.l10n.workloadPreviewHeld(row.openConversations),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkloadSkeleton extends StatelessWidget {
  const _WorkloadSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      key: const ValueKey('workloadPreviewLoading'),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(
                children: [
                  Expanded(child: SkeletonBox(height: 14)),
                  SizedBox(width: Space.xl),
                  SkeletonBox(width: 72, height: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
