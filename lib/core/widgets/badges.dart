/// Status, priority and channel badges.
///
/// Same vocabulary and same colour semantics as the web client's Badge
/// component, so a supervisor moving between the two reads them identically.
library;

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../theme/app_palette.dart';
import '../theme/tokens.dart';
import '../utils/formatting.dart';

enum BadgeTone { neutral, success, warning, danger, info }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.dense = false,
    this.subtle = false,
    super.key,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;
  final bool dense;

  /// Secondary metadata (stage, category): outlined instead of filled, so it
  /// stays readable without competing with the status and actionable badges
  /// next to it.
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (toneForeground, surface) = _palette(context, tone);
    final foreground = subtle && tone == BadgeTone.neutral
        ? theme.textTheme.bodySmall?.color ?? toneForeground
        : toneForeground;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : Space.sm,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: subtle ? null : surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: subtle
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: dense ? 10 : 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Status tones mean the same in every colour theme; their tints and the
  /// info tone come from the active theme ([AppColors]).
  static (Color, Color) _palette(BuildContext context, BadgeTone tone) {
    final colors = AppColors.of(context);
    return switch (tone) {
      BadgeTone.success => (colors.success, colors.successSurface),
      BadgeTone.warning => (colors.warning, colors.warningSurface),
      BadgeTone.danger => (colors.danger, colors.dangerSurface),
      BadgeTone.info => (colors.info, colors.infoSurface),
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

  static (String, BadgeTone) stage(BuildContext context, String value) {
    final tone = switch (value) {
      'HOT_LEAD' => BadgeTone.danger,
      'QUALIFIED_LEAD' => BadgeTone.info,
      'PURCHASE_INTENT' => BadgeTone.warning,
      'PURCHASED' || 'AGENT_CONFIRMED' => BadgeTone.success,
      'LOST' || 'DISQUALIFIED' => BadgeTone.neutral,
      _ => BadgeTone.neutral,
    };
    final label = switch (value) {
      'NEW_LEAD' => context.l10n.stageNewLead,
      'QUALIFIED_LEAD' => context.l10n.stageQualifiedLead,
      'HOT_LEAD' => context.l10n.stageHotLead,
      'PURCHASE_INTENT' => context.l10n.stagePurchaseIntent,
      'PURCHASED' => context.l10n.stagePurchased,
      'LOST' => context.l10n.stageLost,
      'DISQUALIFIED' => context.l10n.stageDisqualified,
      _ => humanizeEnum(value),
    };
    return (label, tone);
  }

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

  /// [providerColor] for a glyph or label drawn straight on the page rather
  /// than on its own coloured disc. TikTok's brand black would vanish on the
  /// dark theme's surfaces, so there it takes the text colour instead.
  static Color providerGlyphColor(BuildContext context, String provider) {
    final theme = Theme.of(context);
    if (provider.toUpperCase() == 'TIKTOK' &&
        theme.brightness == Brightness.dark) {
      return theme.colorScheme.onSurface;
    }
    return providerColor(provider.toUpperCase());
  }

  /// The plain server-reported delivery tick, for surfaces with no local
  /// send/failure state of their own (the inbox row's `last_message_*`
  /// fields) — `FAILED` shown the same error red the bubble uses, so a
  /// supervisor scanning the list catches a stuck send without opening it.
  /// A bubble's own [message_bubble.dart] `_DeliveryIcon` additionally
  /// distinguishes a locally pending/failed send, which has no server
  /// status yet to switch on.
  static (IconData, Color?) deliveryStatusIcon(
    BuildContext context,
    String status,
  ) => switch (status) {
    'FAILED' => (Icons.error_outline, Theme.of(context).colorScheme.error),
    // The theme's info colour: blue-ish in every theme, like a read tick.
    'READ' => (Icons.done_all, AppColors.of(context).info),
    'DELIVERED' => (
      Icons.done_all,
      Theme.of(context).textTheme.labelSmall?.color,
    ),
    _ => (Icons.done, Theme.of(context).textTheme.labelSmall?.color),
  };
}
