/// Routing → "Distribution method" and, under round robin, "Rotation order" —
/// the mobile counterpart of the web's routing-settings sections.
///
/// ## Contract
///
/// * The method is the routing policy's `distribution_mode`
///   (`RECENT_WORKLOAD` | `ROUND_ROBIN`), changed with
///   `PATCH /api/routing/policy/`. It decides how the allocator orders the
///   employees allowed to take a conversation; eligibility is unaffected.
/// * The rotation comes from `GET /api/routing/workload/`: under
///   `ROUND_ROBIN` each row carries a `rotation` block whose `turns_behind`
///   says how many colleagues are ahead — `0` is next. The rows are shown in
///   the order the server sends them. Nothing is ordered or counted here: the
///   backend alone decides who gets the next conversation.
/// * Both need `routing.manage`; the Routing tab is already gated on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/routing_policy.dart';
import '../../core/models/routing_workload.dart';
import '../../core/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/shimmer.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';
import '../directory/directory_providers.dart';

class DistributionMethodCard extends ConsumerStatefulWidget {
  const DistributionMethodCard({required this.policy, super.key});

  final RoutingPolicy policy;

  @override
  ConsumerState<DistributionMethodCard> createState() =>
      _DistributionMethodCardState();
}

class _DistributionMethodCardState
    extends ConsumerState<DistributionMethodCard> {
  /// The method being saved. Only marks that option as pending — the
  /// selection stays on the policy's method until the backend accepts.
  String? _saving;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _select(String mode) async {
    if (_saving != null || mode == widget.policy.distributionMode) return;
    setState(() => _saving = mode);
    try {
      final saved = await ref
          .read(directoryRepositoryProvider)
          .updateRoutingPolicy(distributionMode: mode);
      // The response is the policy as saved: the selection, and which card
      // shows below it, move only to what the backend stored.
      ref.read(routingPolicyProvider.notifier).confirm(saved);
      ref.invalidate(routingWorkloadProvider);
      if (mounted) _showMessage(context.l10n.distributionSaved);
    } on ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final policy = widget.policy;
    // As on the web: only while automatic assignment is on — the method only
    // matters to the allocator — and one change at a time.
    final enabled = policy.isEnabled && _saving == null;
    final options = [
      (
        RoutingDistributionMode.recentWorkload,
        l10n.distributionRecentWorkload,
        l10n.distributionRecentWorkloadHint,
      ),
      (
        RoutingDistributionMode.roundRobin,
        l10n.distributionRoundRobin,
        l10n.distributionRoundRobinHint,
      ),
    ];

    return Card(
      key: const ValueKey('distributionMethodCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.distributionMethodTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(l10n.distributionMethodHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: Space.md),
            RadioGroup<String>(
              groupValue: policy.distributionMode,
              onChanged: (mode) {
                if (enabled && mode != null) _select(mode);
              },
              child: Column(
                children: [
                  for (final (mode, label, hint) in options) ...[
                    _MethodOption(
                      key: ValueKey('distributionMethod_$mode'),
                      mode: mode,
                      label: label,
                      hint: hint,
                      selected: policy.distributionMode == mode,
                      pending: _saving == mode,
                      enabled: enabled,
                      onTap: () => _select(mode),
                    ),
                    if (mode != options.last.$1)
                      const SizedBox(height: Space.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodOption extends StatelessWidget {
  const _MethodOption({
    required this.mode,
    required this.label,
    required this.hint,
    required this.selected,
    required this.pending,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String mode;
  final String label;
  final String hint;
  final bool selected;

  /// Being saved: marked with a spinner, not selected until confirmed.
  final bool pending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: enabled || selected || pending ? 1 : 0.6,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.xs,
            Space.xs,
            Space.md,
            Space.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.06) : null,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pending)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    key: ValueKey('distributionMethodPending'),
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Radio<String>(value: mode, enabled: enabled),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(hint, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Under round robin, in place of the workload-period card: who is next, as
/// the server orders it. The period controls are not shown — the period plays
/// no part in this method.
class RotationOrderCard extends StatelessWidget {
  const RotationOrderCard({required this.policy, super.key});

  final RoutingPolicy policy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('rotationOrderCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.rotationTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(context.l10n.rotationHint, style: theme.textTheme.bodySmall),
            // Like the web: no order while automatic assignment is off.
            if (policy.isEnabled) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.lg),
                child: Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              const RoutingRotationList(),
            ],
          ],
        ),
      ),
    );
  }
}

/// The rotation from `GET /api/routing/workload/`, read-only: the account it
/// is for, then every employee in the server's order, the next one marked.
///
/// Shows a skeleton while the figures on hand belong to the other method (a
/// change has not been read back yet), rather than present them as a rotation.
class RoutingRotationList extends ConsumerWidget {
  const RoutingRotationList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ref
        .watch(routingWorkloadProvider)
        .when(
          loading: () => const RotationSkeleton(),
          error: (error, _) => Column(
            key: const ValueKey('rotationError'),
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
            // Figures for the other method: the refetch after a change has
            // not landed yet.
            if (preview.distributionMode.isNotEmpty && !preview.isRoundRobin) {
              return const RotationSkeleton();
            }
            if (preview.employees.isEmpty || preview.nobodyRoutable) {
              return Padding(
                key: const ValueKey('rotationEmpty'),
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Text(
                  context.l10n.rotationEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              );
            }
            final rows = preview.employees;
            final account = preview.rotationConnections.isEmpty
                ? ''
                : preview.rotationConnections.first.name;
            return Column(
              key: const ValueKey('rotationList'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (account.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(
                      context.l10n.rotationAccount(account),
                      key: const ValueKey('rotationAccount'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // The backend's order, kept exactly.
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  RotationRowTile(row: rows[i]),
                ],
              ],
            );
          },
        );
  }
}

/// One employee's place in the rotation. The next one is highlighted.
class RotationRowTile extends StatelessWidget {
  const RotationRowTile({required this.row, super.key});

  final WorkloadRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final muted = scheme.onSurfaceVariant;
    const tabular = [FontFeature.tabularFigures()];
    final rotation = row.rotation;
    final next = row.routable && (rotation?.isNext ?? false);

    final String standing;
    if (!row.routable) {
      standing = context.l10n.workloadPreviewNotReceiving;
    } else if (rotation?.turnsBehind == null) {
      standing = context.l10n.rotationNever;
    } else if (next) {
      standing = context.l10n.rotationNext;
    } else {
      standing = context.l10n.rotationBehind(rotation!.turnsBehind!);
    }

    return Container(
      key: ValueKey('rotationRow_${row.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.sm,
      ),
      decoration: next
          ? BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.md),
            )
          : null,
      child: Row(
        children: [
          if (next) ...[
            Icon(
              Icons.play_arrow_rounded,
              key: const ValueKey('rotationNextMarker'),
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: Space.xs),
          ],
          Expanded(
            flex: 2,
            child: Text(
              row.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: next ? FontWeight.w700 : null,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          // Shrinks and wraps on a narrow phone rather than run off the edge.
          Flexible(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  standing,
                  key: const ValueKey('rotationStanding'),
                  textAlign: TextAlign.end,
                  style: row.routable
                      ? theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: next ? scheme.primary : null,
                          fontFeatures: tabular,
                        )
                      : theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                if (row.routable)
                  Text(
                    context.l10n.rotationReceivedInfo(row.received),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.mutedForeground,
                      fontFeatures: tabular,
                    ),
                  ),
                Text(
                  context.l10n.workloadPreviewHeld(row.openConversations),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RotationSkeleton extends StatelessWidget {
  const RotationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      key: const ValueKey('rotationLoading'),
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
