/// Skeleton loading state for the Dashboard.
///
/// Matches the real Dashboard layout closely:
/// - Header greeting and date filter button
/// - Conversations section heading and 4 metric cards
/// - Customer Intelligence section heading and 4 metric cards
/// - "Your last 14 days" performance card
/// - Team workload and recent activity cards
library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/shimmer.dart';

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 720 ? 4 : 2;
    final ratio = width < 360 ? 1.2 : 1.45;

    return AppShimmer(
      child: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          // Header / Conversations section title + date filter button
          Row(
            children: [
              const Expanded(child: SkeletonText(width: 140, height: 18)),
              const SkeletonBox(width: 96, height: 32, borderRadius: Radii.md),
            ],
          ),
          const SizedBox(height: Space.md),

          // 4 Metric cards: Open, Unassigned, Waiting, Resolved
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.md,
            childAspectRatio: ratio,
            children: const [
              _MetricTileSkeleton(),
              _MetricTileSkeleton(),
              _MetricTileSkeleton(),
              _MetricTileSkeleton(),
            ],
          ),

          const SizedBox(height: Space.xl),

          // Customer Intelligence section title
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SkeletonText(width: 160, height: 16),
          ),
          const SizedBox(height: Space.md),

          // 4 Customer Intelligence cards: Qualified, Hot, Claims, Confirmed
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.md,
            childAspectRatio: ratio,
            children: const [
              _MetricTileSkeleton(),
              _MetricTileSkeleton(),
              _MetricTileSkeleton(),
              _MetricTileSkeleton(),
            ],
          ),

          const SizedBox(height: Space.xl),

          // "Your last 14 days" performance section
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SkeletonText(width: 130, height: 16),
          ),
          const SizedBox(height: Space.md),
          const _PerformanceCardSkeleton(),

          const SizedBox(height: Space.xl),

          // Team Workload section title
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SkeletonText(width: 120, height: 16),
          ),
          const SizedBox(height: Space.md),
          const _WorkloadCardSkeleton(),

          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }
}

/// Placeholder for a single [MetricTile].
class _MetricTileSkeleton extends StatelessWidget {
  const _MetricTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(child: SkeletonText(width: 60, height: 11)),
              SizedBox(width: Space.xs),
              SkeletonBox(width: 24, height: 24, borderRadius: Radii.sm),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonText(width: 44, height: 22),
              SizedBox(height: 4),
              SkeletonText(width: 70, height: 9),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder for the "Your last 14 days" [PerformanceCard].
class _PerformanceCardSkeleton extends StatelessWidget {
  const _PerformanceCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 80, height: 10),
                    SizedBox(height: 6),
                    SkeletonText(width: 60, height: 18),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 80, height: 10),
                    SizedBox(height: 6),
                    SkeletonText(width: 60, height: 18),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 80, height: 10),
                    SizedBox(height: 6),
                    SkeletonText(width: 60, height: 18),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: Space.lg),
          Divider(height: 1),
          SizedBox(height: Space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonText(width: 110, height: 12),
              SkeletonText(width: 50, height: 12),
            ],
          ),
          SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonText(width: 130, height: 12),
              SkeletonText(width: 40, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder for the team workload card.
class _WorkloadCardSkeleton extends StatelessWidget {
  const _WorkloadCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _WorkloadRowSkeleton(),
          Divider(height: 1, indent: 60),
          _WorkloadRowSkeleton(),
          Divider(height: 1, indent: 60),
          _WorkloadRowSkeleton(),
        ],
      ),
    );
  }
}

class _WorkloadRowSkeleton extends StatelessWidget {
  const _WorkloadRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      child: Row(
        children: [
          SkeletonCircle(size: 36),
          SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 120, height: 13),
                SizedBox(height: 6),
                SkeletonText(width: 80, height: 10),
              ],
            ),
          ),
          SkeletonBox(width: 24, height: 18, borderRadius: Radii.sm),
        ],
      ),
    );
  }
}
