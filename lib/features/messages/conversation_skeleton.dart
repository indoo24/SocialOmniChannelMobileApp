/// Skeleton loading components for the Conversation screen.
///
/// Closely resembles the real conversation UI:
/// - Conversation header (customer avatar, name, channel badge)
/// - Header action buttons placeholder
/// - Realistic chat thread with varied incoming & outgoing message bubbles
/// - Bottom reply composer area (mode tabs, attachment, text input, send buttons)
library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/shimmer.dart';

/// Skeleton for the Conversation screen AppBar title.
class ConversationHeaderSkeleton extends StatelessWidget {
  const ConversationHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          SkeletonCircle(size: 36),
          SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonText(width: 120, height: 14),
                SizedBox(height: 4),
                Row(
                  children: [
                    SkeletonBox(
                      width: 60,
                      height: 16,
                      borderRadius: Radii.pill,
                    ),
                    SizedBox(width: Space.xs),
                    SkeletonText(width: 60, height: 10),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton placeholder for the header assignee avatar.
class ConversationAssigneeSkeleton extends StatelessWidget {
  const ConversationAssigneeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: Space.xs),
      child: SkeletonCircle(size: 32),
    );
  }
}

/// Skeleton placeholder for header action button.
class ConversationActionSkeleton extends StatelessWidget {
  const ConversationActionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: Space.xs),
      child: SkeletonBox(width: 32, height: 32, borderRadius: Radii.sm),
    );
  }
}

/// Skeleton for the conversation thread and composer body.
class ConversationThreadSkeleton extends StatelessWidget {
  const ConversationThreadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: const [
          Expanded(child: _MessageThreadSkeletonList()),
          ConversationComposerSkeleton(),
        ],
      ),
    );
  }
}

/// A list of realistic conversation message bubbles with alternating directions,
/// varying widths, timestamps, and attachment placeholder.
class _MessageThreadSkeletonList extends StatelessWidget {
  const _MessageThreadSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      children: const [
        // 1. Incoming message with 2 lines
        _MessageBubbleSkeleton(
          isOutbound: false,
          width: 210,
          lines: [180, 120],
        ),
        SizedBox(height: Space.sm),

        // 2. Outgoing message with 2 lines
        _MessageBubbleSkeleton(isOutbound: true, width: 230, lines: [200, 130]),
        SizedBox(height: Space.sm),

        // 3. Short incoming message
        _MessageBubbleSkeleton(isOutbound: false, width: 140, lines: [110]),
        SizedBox(height: Space.sm),

        // 4. Short outgoing reply
        _MessageBubbleSkeleton(isOutbound: true, width: 170, lines: [140]),
        SizedBox(height: Space.sm),

        // 5. Incoming message with an attachment placeholder
        _MessageBubbleSkeleton(
          isOutbound: false,
          width: 220,
          hasAttachment: true,
          lines: [160],
        ),
        SizedBox(height: Space.sm),

        // 6. Outgoing message
        _MessageBubbleSkeleton(isOutbound: true, width: 250, lines: [220, 110]),
        SizedBox(height: Space.sm),

        // 7. Incoming message
        _MessageBubbleSkeleton(isOutbound: false, width: 180, lines: [150]),
      ],
    );
  }
}

/// A single message bubble placeholder mimicking incoming (customer) or outgoing (agent) layout.
class _MessageBubbleSkeleton extends StatelessWidget {
  const _MessageBubbleSkeleton({
    required this.isOutbound,
    required this.width,
    required this.lines,
    this.hasAttachment = false,
  });

  final bool isOutbound;
  final double width;
  final List<double> lines;
  final bool hasAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bubbleColor = isOutbound
        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E7FF))
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isOutbound
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOutbound) ...[
            const SkeletonCircle(size: 28),
            const SizedBox(width: Space.xs),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isOutbound ? 16 : 4),
                  bottomRight: Radius.circular(isOutbound ? 4 : 16),
                ),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF222B3A)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasAttachment) ...[
                    const SkeletonBox(
                      width: double.infinity,
                      height: 100,
                      borderRadius: Radii.md,
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                  for (int i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(height: 5),
                    SkeletonText(width: lines[i], height: 12),
                  ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: const SkeletonText(width: 32, height: 9),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for the bottom reply composer.
class ConversationComposerSkeleton extends StatelessWidget {
  const ConversationComposerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        Space.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode pills: Reply, Internal note, Template
          Row(
            children: const [
              SkeletonBox(width: 60, height: 26, borderRadius: Radii.pill),
              SizedBox(width: Space.xs),
              SkeletonBox(width: 90, height: 26, borderRadius: Radii.pill),
              SizedBox(width: Space.xs),
              SkeletonBox(width: 75, height: 26, borderRadius: Radii.pill),
            ],
          ),
          const SizedBox(height: Space.sm),
          // Composer input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              SkeletonBox(width: 36, height: 38, borderRadius: Radii.sm),
              SizedBox(width: Space.xs),
              SkeletonBox(width: 36, height: 38, borderRadius: Radii.sm),
              SizedBox(width: Space.xs),
              Expanded(child: SkeletonBox(height: 42, borderRadius: Radii.md)),
              SizedBox(width: Space.xs),
              SkeletonCircle(size: 38),
            ],
          ),
        ],
      ),
    );
  }
}

/// Complete full-screen skeleton representation for Conversation Details.
class ConversationDetailsSkeleton extends StatelessWidget {
  const ConversationDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const ConversationHeaderSkeleton(),
        actions: const [
          ConversationActionSkeleton(),
          ConversationAssigneeSkeleton(),
          SizedBox(width: Space.xs),
        ],
      ),
      body: const ConversationThreadSkeleton(),
    );
  }
}
