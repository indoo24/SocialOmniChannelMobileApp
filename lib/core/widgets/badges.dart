/// Status, priority and channel badges.
///
/// Same vocabulary and same colour semantics as the web client's Badge
/// component, so a supervisor moving between the two reads them identically.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum BadgeTone { neutral, success, warning, danger, info }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.dense = false,
    super.key,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (foreground, surface) = _palette(context, tone);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : Space.sm,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  static (Color, Color) _palette(BuildContext context, BadgeTone tone) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      BadgeTone.success => (
          ScenarioColors.success,
          isDark
              ? ScenarioColors.success.withValues(alpha: 0.18)
              : ScenarioColors.successSurface,
        ),
      BadgeTone.warning => (
          ScenarioColors.warning,
          isDark
              ? ScenarioColors.warning.withValues(alpha: 0.18)
              : ScenarioColors.warningSurface,
        ),
      BadgeTone.danger => (
          ScenarioColors.danger,
          isDark
              ? ScenarioColors.danger.withValues(alpha: 0.18)
              : ScenarioColors.dangerSurface,
        ),
      BadgeTone.info => (
          ScenarioColors.info,
          isDark
              ? ScenarioColors.info.withValues(alpha: 0.18)
              : ScenarioColors.infoSurface,
        ),
      BadgeTone.neutral => (
          Theme.of(context).colorScheme.onSurfaceVariant,
          Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
    };
  }
}

/// Maps backend enum values to label + tone, in one place.
///
/// The backend sends `NEW`, `WAITING_CUSTOMER` and so on. Presenting them
/// verbatim would leak database vocabulary into the UI; the web client maps
/// them to sentence case, so this does too.
class ConversationBadges {
  const ConversationBadges._();

  static (String, BadgeTone) status(String value) => switch (value) {
        'NEW' => ('New', BadgeTone.info),
        'OPEN' => ('Open', BadgeTone.success),
        'WAITING_CUSTOMER' => ('Waiting on customer', BadgeTone.warning),
        'WAITING_INTERNAL' => ('Waiting internally', BadgeTone.warning),
        'RESOLVED' => ('Resolved', BadgeTone.neutral),
        'CLOSED' => ('Closed', BadgeTone.neutral),
        _ => (value, BadgeTone.neutral),
      };

  static (String, BadgeTone) priority(String value) => switch (value) {
        'URGENT' => ('Urgent', BadgeTone.danger),
        'HIGH' => ('High', BadgeTone.warning),
        'NORMAL' => ('Normal', BadgeTone.neutral),
        'LOW' => ('Low', BadgeTone.neutral),
        _ => (value, BadgeTone.neutral),
      };

  /// Priority is only worth pixels when it is not the default. The web inbox
  /// makes the same call — a row of "Normal" badges is noise.
  static bool showsPriority(String value) => value == 'URGENT' || value == 'HIGH';

  static IconData providerIcon(String provider) => switch (provider) {
        'WHATSAPP' => Icons.chat_bubble,
        'FACEBOOK' => Icons.facebook,
        'INSTAGRAM' => Icons.camera_alt_outlined,
        'TIKTOK' => Icons.music_note,
        _ => Icons.science_outlined,
      };

  static String providerLabel(String provider) => switch (provider) {
        'WHATSAPP' => 'WhatsApp',
        'FACEBOOK' => 'Messenger',
        'INSTAGRAM' => 'Instagram',
        'TIKTOK' => 'TikTok',
        'MOCK' => 'Sandbox',
        _ => provider,
      };

  static Color providerColor(String provider) => switch (provider) {
        'WHATSAPP' => const Color(0xFF25D366),
        'FACEBOOK' => const Color(0xFF0866FF),
        'INSTAGRAM' => const Color(0xFFE1306C),
        'TIKTOK' => const Color(0xFF010101),
        _ => const Color(0xFF0F766E),
      };
}
