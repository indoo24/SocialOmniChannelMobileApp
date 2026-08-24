/// Status, priority and channel badges.
///
/// Same vocabulary and same colour semantics as the web client's Badge
/// component, so a supervisor moving between the two reads them identically.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
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

  static (String, BadgeTone) status(BuildContext context, String value) =>
      switch (value) {
        'NEW' => (context.l10n.statusNew, BadgeTone.info),
        'OPEN' => (context.l10n.statusOpen, BadgeTone.success),
        'WAITING_CUSTOMER' => (
          context.l10n.statusWaitingCustomer,
          BadgeTone.warning,
        ),
        'WAITING_INTERNAL' => (
          context.l10n.statusWaitingInternal,
          BadgeTone.warning,
        ),
        'RESOLVED' => (context.l10n.statusResolved, BadgeTone.neutral),
        'CLOSED' => (context.l10n.statusClosed, BadgeTone.neutral),
        _ => (value, BadgeTone.neutral),
      };

  static (String, BadgeTone) priority(BuildContext context, String value) =>
      switch (value) {
        'URGENT' => (context.l10n.priorityUrgent, BadgeTone.danger),
        'HIGH' => (context.l10n.priorityHigh, BadgeTone.warning),
        'NORMAL' => (context.l10n.priorityNormal, BadgeTone.neutral),
        'LOW' => (context.l10n.priorityLow, BadgeTone.neutral),
        _ => (value, BadgeTone.neutral),
      };

  /// Priority is only worth pixels when it is not the default. The web inbox
  /// makes the same call — a row of "Normal" badges is noise.
  static bool showsPriority(String value) =>
      value == 'URGENT' || value == 'HIGH';

  static IconData providerIcon(String provider) => switch (provider) {
    'WHATSAPP' => Icons.chat_bubble,
    'FACEBOOK' => Icons.facebook,
    'INSTAGRAM' => Icons.camera_alt_outlined,
    'TIKTOK' => Icons.music_note,
    _ => Icons.science_outlined,
  };

  static String providerLabel(BuildContext context, String provider) =>
      switch (provider) {
        'WHATSAPP' => context.l10n.providerWhatsapp,
        'FACEBOOK' => context.l10n.providerFacebook,
        'INSTAGRAM' => context.l10n.providerInstagram,
        'TIKTOK' => context.l10n.providerTiktok,
        'MOCK' => context.l10n.providerSandbox,
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
