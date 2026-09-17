/// Skeleton loading states for Settings tabs.
///
/// Provides layout-matched skeletons for:
/// - Channels tab (platform cards, status badges, buttons, account details)
/// - Assignment tab (policy cards, switches, capacity and timeout controls)
/// - Customer fields tab (headers, field cards, keys, type badges, action icons)
/// - Saved replies tab (headers, reply cards, shortcuts, categories, content boxes)
/// - Full Settings screen skeleton
library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/shimmer.dart';

/// Full screen skeleton for the Settings screen before user permissions/profile load.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Scaffold(
        appBar: AppBar(
          title: const SkeletonText(width: 90, height: 18),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              child: Row(
                children: const [
                  SkeletonBox(width: 80, height: 32, borderRadius: Radii.md),
                  SizedBox(width: Space.sm),
                  SkeletonBox(width: 95, height: 32, borderRadius: Radii.md),
                  SizedBox(width: Space.sm),
                  SkeletonBox(width: 105, height: 32, borderRadius: Radii.md),
                  SizedBox(width: Space.sm),
                  SkeletonBox(width: 75, height: 32, borderRadius: Radii.md),
                ],
              ),
            ),
          ),
        ),
        body: const ChannelsSkeleton(),
      ),
    );
  }
}

/// Skeleton for the Channels settings tab.
class ChannelsSkeleton extends StatelessWidget {
  const ChannelsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: const [
          _PlatformCardSkeleton(accountsCount: 2),
          SizedBox(height: Space.lg),
          _PlatformCardSkeleton(accountsCount: 1),
          SizedBox(height: Space.lg),
          _PlatformCardSkeleton(accountsCount: 0),
        ],
      ),
    );
  }
}

class _PlatformCardSkeleton extends StatelessWidget {
  const _PlatformCardSkeleton({required this.accountsCount});

  final int accountsCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonCircle(size: 40),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 140, height: 16),
                    SizedBox(height: 6),
                    SkeletonText(width: 220, height: 12),
                  ],
                ),
              ),
              const SkeletonBox(
                width: 75,
                height: 22,
                borderRadius: Radii.pill,
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              SkeletonBox(width: 130, height: 36, borderRadius: Radii.md),
              SkeletonBox(width: 36, height: 36, borderRadius: Radii.sm),
            ],
          ),
          if (accountsCount > 0) ...[
            const SizedBox(height: Space.md),
            const Divider(height: 1),
            const SizedBox(height: Space.md),
            for (int i = 0; i < accountsCount; i++) ...[
              if (i > 0) const SizedBox(height: Space.sm),
              const _ChannelAccountRowSkeleton(),
            ],
          ],
        ],
      ),
    );
  }
}

class _ChannelAccountRowSkeleton extends StatelessWidget {
  const _ChannelAccountRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: const [
          SkeletonCircle(size: 28),
          SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 110, height: 13),
                SizedBox(height: 4),
                SkeletonText(width: 70, height: 10),
              ],
            ),
          ),
          SkeletonBox(width: 60, height: 20, borderRadius: Radii.pill),
        ],
      ),
    );
  }
}

/// Skeleton for the Assignment & routing policy tab.
class AssignmentSkeleton extends StatelessWidget {
  const AssignmentSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: const [
          _AssignmentCardSkeleton(hasSwitch: true),
          SizedBox(height: Space.lg),
          _AssignmentCardSkeleton(hasSwitch: true),
          SizedBox(height: Space.lg),
          _AssignmentCardSkeleton(hasInput: true),
          SizedBox(height: Space.lg),
          _AssignmentCardSkeleton(hasInput: true),
          SizedBox(height: Space.lg),
          _AssignmentCardSkeleton(hasInput: true),
        ],
      ),
    );
  }
}

class _AssignmentCardSkeleton extends StatelessWidget {
  const _AssignmentCardSkeleton({
    this.hasSwitch = false,
    this.hasInput = false,
  });

  final bool hasSwitch;
  final bool hasInput;

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SkeletonText(width: 150, height: 16),
              if (hasSwitch)
                const SkeletonBox(
                  width: 44,
                  height: 24,
                  borderRadius: Radii.pill,
                )
              else
                const SkeletonBox(
                  width: 65,
                  height: 20,
                  borderRadius: Radii.pill,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          const SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: 4),
          const SkeletonText(width: 220, height: 12),
          if (hasInput) ...[
            const SizedBox(height: Space.md),
            const SkeletonBox(
              width: double.infinity,
              height: 44,
              borderRadius: Radii.md,
            ),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for the Customer fields tab.
class CustomerFieldsSkeleton extends StatelessWidget {
  const CustomerFieldsSkeleton({this.scrollable = true, super.key});

  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: const [
        SkeletonText(width: 170, height: 20),
        SizedBox(height: Space.sm),
        SkeletonText(width: 270, height: 12),
        SizedBox(height: Space.lg),
        SkeletonBox(width: 120, height: 42, borderRadius: Radii.md),
        SizedBox(height: Space.lg),
        _CustomerFieldCardSkeleton(),
        SizedBox(height: Space.md),
        _CustomerFieldCardSkeleton(),
        SizedBox(height: Space.md),
        _CustomerFieldCardSkeleton(),
      ],
    );

    if (!scrollable) {
      return AppShimmer(child: content);
    }

    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: [content],
      ),
    );
  }
}

class _CustomerFieldCardSkeleton extends StatelessWidget {
  const _CustomerFieldCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 130, height: 15),
                    SizedBox(height: 6),
                    SkeletonText(width: 90, height: 11),
                  ],
                ),
              ),
              SkeletonBox(width: 65, height: 20, borderRadius: Radii.pill),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: const [
              SkeletonBox(width: 32, height: 32, borderRadius: Radii.sm),
              SizedBox(width: Space.xs),
              SkeletonBox(width: 32, height: 32, borderRadius: Radii.sm),
              Spacer(),
              SkeletonBox(width: 44, height: 24, borderRadius: Radii.pill),
              SizedBox(width: Space.sm),
              SkeletonBox(width: 32, height: 32, borderRadius: Radii.sm),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton for the Saved replies tab.
class SavedRepliesSkeleton extends StatelessWidget {
  const SavedRepliesSkeleton({this.scrollable = true, super.key});

  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: const [
        SkeletonText(width: 150, height: 20),
        SizedBox(height: Space.sm),
        SkeletonText(width: 250, height: 12),
        SizedBox(height: Space.lg),
        SkeletonBox(width: 130, height: 42, borderRadius: Radii.md),
        SizedBox(height: Space.lg),
        _SavedReplyCardSkeleton(),
        SizedBox(height: Space.md),
        _SavedReplyCardSkeleton(),
      ],
    );

    if (!scrollable) {
      return AppShimmer(child: content);
    }

    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: [content],
      ),
    );
  }
}

class _SavedReplyCardSkeleton extends StatelessWidget {
  const _SavedReplyCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SkeletonCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 140, height: 15),
                    SizedBox(height: 6),
                    SkeletonText(width: 80, height: 11),
                    SizedBox(height: 4),
                    SkeletonText(width: 65, height: 11),
                  ],
                ),
              ),
              SkeletonBox(width: 70, height: 20, borderRadius: Radii.pill),
            ],
          ),
          const SizedBox(height: Space.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: double.infinity, height: 11),
                SizedBox(height: 6),
                SkeletonText(width: 180, height: 11),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: const [
              SkeletonBox(width: 32, height: 32, borderRadius: Radii.sm),
              SizedBox(width: Space.xs),
              SkeletonBox(width: 32, height: 32, borderRadius: Radii.sm),
            ],
          ),
        ],
      ),
    );
  }
}
