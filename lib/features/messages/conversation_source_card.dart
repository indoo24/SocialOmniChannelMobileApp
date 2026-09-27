/// The conversation-source card: where the customer came from (a Meta ad or
/// post), shown once at the top of the thread — the mobile counterpart of the
/// web inbox's conversation-source card, driven by the same
/// `ConversationDetail.attribution` fields (see [ConversationAttribution]).
///
/// It is conversation-level content, not a message: it belongs to no bubble,
/// is placed by the message list at the top of the history, and appears only
/// once that history has been loaded back to its start.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/app_log.dart';
import '../../core/models/conversation_attribution.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatting.dart';
import '../../l10n/l10n_extensions.dart';

/// Opens a referral's source link. Replaceable in tests.
@visibleForTesting
Future<bool> Function(Uri uri) openSourceUrl = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class ConversationSourceCard extends StatelessWidget {
  const ConversationSourceCard({required this.attribution, super.key});

  final ConversationAttribution attribution;

  @override
  Widget build(BuildContext context) {
    final mostRecent = attribution.mostRecent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.xs,
        Space.md,
        Space.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PrimaryReferral(referral: attribution.primary),
              if (mostRecent != null) _MostRecentLine(referral: mostRecent),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _open(Uri uri) async {
  try {
    final opened = await openSourceUrl(uri);
    if (!opened) {
      AppLog.debug('ConversationSource', 'no app to open ${uri.host}');
    }
  } catch (error) {
    AppLog.debug('ConversationSource', 'opening source failed: $error');
  }
}

class _PrimaryReferral extends StatelessWidget {
  const _PrimaryReferral({required this.referral});

  final ConversationReferral referral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurfaceVariant;
    final isAd = referral.source == ReferralSource.metaPaidAd;
    final uri = referral.openableUrl;

    final kind = switch (referral.source) {
      ReferralSource.metaPaidAd => l10n.conversationSourceFromAd,
      ReferralSource.metaOrganicPost => l10n.conversationSourceFromPost,
      ReferralSource.unknown => l10n.conversationSourceUnknown,
    };
    final platform = referral.platformName;
    // Upper-cased like the web card's label ("CAME FROM A META AD ON
    // FACEBOOK"); Arabic script is unaffected, only the Latin names change.
    final label =
        (platform == null
                ? kind
                : '$kind ${l10n.conversationSourceOnPlatform(platform)}')
            .toUpperCase();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isAd ? Icons.campaign_outlined : Icons.article_outlined,
              size: 16,
              color: isAd ? theme.colorScheme.primary : muted,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (uri != null) ...[
              const SizedBox(width: Space.sm),
              Icon(Icons.open_in_new_rounded, size: 14, color: muted),
            ],
          ],
        ),
        if (referral.headline.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            referral.headline,
            key: const ValueKey('conversationSourceHeadline'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
        if (referral.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            referral.summaryTruncated
                ? '${referral.summary}…'
                : referral.summary,
            key: const ValueKey('conversationSourceSummary'),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.45,
            ),
          ),
        ],
      ],
    );

    final radius = BorderRadius.circular(Radii.lg);
    final card = CustomPaint(
      painter: _DashedBorderPainter(
        color: theme.colorScheme.outlineVariant,
        radius: Radii.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 4,
        ),
        child: content,
      ),
    );

    return Material(
      key: const ValueKey('conversationSourceCard'),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: radius,
      child: uri == null
          ? card
          : Semantics(
              link: true,
              label: isAd
                  ? l10n.conversationSourceOpenAd
                  : l10n.conversationSourceOpenPost,
              child: InkWell(
                borderRadius: radius,
                onTap: () => _open(uri),
                child: card,
              ),
            ),
    );
  }
}

/// "Most recent: {headline} · Seen {date}" — the later referral on a thread
/// that has had more than one.
class _MostRecentLine extends StatelessWidget {
  const _MostRecentLine({required this.referral});

  final ConversationReferral referral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurfaceVariant;
    final uri = referral.openableUrl;
    final observed = referral.observedAt;

    final text = Text.rich(
      TextSpan(
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted,
          decoration: uri != null ? TextDecoration.underline : null,
          decorationColor: muted,
        ),
        children: [
          TextSpan(
            text: '${l10n.conversationSourceMostRecent}: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: referral.headline.isNotEmpty
                ? referral.headline
                : l10n.conversationSourceTitle,
          ),
          if (observed != null)
            TextSpan(
              text:
                  ' · ${l10n.conversationSourceSeenOn(formatDateTime(context, observed))}',
            ),
        ],
      ),
      key: const ValueKey('conversationSourceMostRecent'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: uri == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: text,
            )
          : InkWell(
              onTap: () => _open(uri),
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: 2,
                ),
                child: text,
              ),
            ),
    );
  }
}

/// The small "Conversation source" pill shown over the thread while the
/// source card is out of view; tapping it scrolls to the card.
class ConversationSourceJumpButton extends StatelessWidget {
  const ConversationSourceJumpButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.conversationSourceJumpTo,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        elevation: 1,
        shape: StadiumBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.campaign_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.conversationSourceShortcut,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_upward_rounded,
                  size: 12,
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

/// A dashed rounded-rectangle outline — the web card's `border-dashed`.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
