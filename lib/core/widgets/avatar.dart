/// Avatars with initials fallback and a channel indicator.
///
/// The web inbox shows the customer's avatar with a small platform glyph
/// attached, so an agent can tell WhatsApp from Instagram at a glance without
/// reading. Same idea here.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../utils/safe_url.dart';
import 'badges.dart';

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.initials,
    this.imageUrl = '',
    this.size = 40,
    this.provider,
    super.key,
  });

  final String initials;
  final String imageUrl;
  final double size;

  /// When set, a small channel glyph is drawn over the corner.
  final String? provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Every avatar in the app renders through this widget, so sanitising here
    // covers all of them — including the customer avatars whose URLs came from
    // WhatsApp or Instagram rather than from Scenario. A rejected URL is
    // indistinguishable from an absent one: both fall through to initials.
    final safeUrl = SafeUrl.forImage(imageUrl);

    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: safeUrl.isEmpty
            ? _initials(theme)
            : CachedNetworkImage(
                imageUrl: safeUrl,
                fit: BoxFit.cover,
                // Platform CDN URLs are signed and expire. A broken image must
                // degrade to initials, never to a broken-image glyph.
                errorWidget: (_, _, _) => _initials(theme),
                placeholder: (_, _) => _initials(theme),
              ),
      ),
    );

    if (provider == null) return avatar;

    final badgeSize = size * 0.42;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: ConversationBadges.providerColor(provider!),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
              child: Icon(
                ConversationBadges.providerIcon(provider!),
                size: badgeSize * 0.55,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials(ThemeData theme) => Container(
    color: theme.colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Text(
      initials.isEmpty ? '?' : initials,
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Small presence dot for employee rows.
class PresenceDot extends StatelessWidget {
  const PresenceDot({required this.availability, this.size = 8, super.key});

  final String availability;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (availability) {
      'ONLINE' => ScenarioColors.success,
      'AWAY' => ScenarioColors.warning,
      'BREAK' => ScenarioColors.warning,
      _ => Theme.of(context).colorScheme.outline,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
