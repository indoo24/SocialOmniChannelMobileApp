/// Skeleton loading state for the Inbox and conversation lists.
///
/// Matches the real Inbox screen:
/// - Platform account filter pills
/// - Quick filter pills (All, Mine, Unassigned, Unread, Open)
/// - Conversation rows with avatar, customer name, timestamp, preview text, and status chips
library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/shimmer.dart';
import '../../core/widgets/states.dart';

class InboxSkeleton extends StatelessWidget {
  const InboxSkeleton({
    this.itemCount = 8,
    this.includeFilterBars = true,
    super.key,
  });

  final int itemCount;
  final bool includeFilterBars;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: [
          if (includeFilterBars) ...[
            const _InboxPlatformFilterSkeleton(),
            const _InboxQuickFilterSkeleton(),
          ],
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
              itemBuilder: (_, _) => const ConversationSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton row for platform account selectors (WhatsApp, Instagram, etc.).
class _InboxPlatformFilterSkeleton extends StatelessWidget {
  const _InboxPlatformFilterSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SkeletonBox(width: 110, height: 32, borderRadius: Radii.pill),
          SizedBox(width: Space.xs),
          SkeletonBox(width: 120, height: 32, borderRadius: Radii.pill),
        ],
      ),
    );
  }
}

/// Skeleton row for quick filter pills (All, Mine, Unassigned, Unread, Open).
class _InboxQuickFilterSkeleton extends StatelessWidget {
  const _InboxQuickFilterSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SkeletonBox(width: 50, height: 32, borderRadius: Radii.pill),
          SizedBox(width: Space.xs),
          SkeletonBox(width: 55, height: 32, borderRadius: Radii.pill),
          SizedBox(width: Space.xs),
          SkeletonBox(width: 90, height: 32, borderRadius: Radii.pill),
          SizedBox(width: Space.xs),
          SkeletonBox(width: 65, height: 32, borderRadius: Radii.pill),
          SizedBox(width: Space.xs),
          SkeletonBox(width: 55, height: 32, borderRadius: Radii.pill),
        ],
      ),
    );
  }
}
