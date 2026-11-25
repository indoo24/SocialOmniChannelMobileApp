/// Who a conversation is with, under the conversation app bar.
///
/// The app bar above it is the first row of the header: back, and the
/// conversation's actions. This is the rest of it, in its own rows so
/// nothing has to share width with those actions:
///
///   * the customer — avatar, the full name and the phone number;
///   * where the conversation lives and who holds it — channel, account,
///     owning team and assignee — as compact chips that wrap onto another
///     line rather than being clipped or dropped.
///
/// While the screen is short — the keyboard is up — it folds into one line
/// (avatar, name, phone) so the reply box still fits; the channel, account,
/// team and assignee come back as soon as there is room, are still read out
/// by a screen reader, and are one tap away in the details sheet meanwhile.
///
/// The whole block opens the conversation's details and actions, as the
/// header did before. Everything here is read straight from the
/// conversation the controller holds, so a transfer or an assignment shows
/// as soon as the conversation does.
library;

import 'package:flutter/material.dart';

import '../../core/models/conversation.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/badges.dart';
import '../../l10n/l10n_extensions.dart';
import 'transfer_team_sheet.dart' show ConversationTeamPill;

class ConversationHeaderDetails extends StatelessWidget {
  const ConversationHeaderDetails({
    required this.conversation,
    required this.onOpenDetails,
    this.compact = false,
    super.key,
  });

  final Conversation conversation;

  /// The customer details and conversation actions sheet.
  final VoidCallback onOpenDetails;

  /// One line instead of three — see the library comment.
  final bool compact;

  /// Below this much height for the conversation body, [compact] is used.
  static const compactBelowBodyHeight = 440.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final customer = conversation.customer;
    final phone = customer.phone.trim();
    final account = conversation.channelName.trim();
    final team = conversation.assignedTeam;
    final assignee = conversation.assignedTo;

    final metaLabels = [
      l10n.conversationHeaderChannelSemantics(
        ConversationChannelChip.providerInfo(
          context,
          conversation.provider,
          theme.brightness == Brightness.dark,
        ).$3,
      ),
      if (account.isNotEmpty) l10n.conversationHeaderAccountSemantics(account),
      if (team != null && team.name.trim().isNotEmpty)
        l10n.conversationTeamSemantics(team.name),
      if (assignee != null && assignee.fullName.trim().isNotEmpty)
        l10n.assignedToSemantics(assignee.fullName),
    ];

    final chips = <Widget>[
      ConversationChannelChip(provider: conversation.provider),
      if (account.isNotEmpty)
        _MetaChip(
          key: const ValueKey('conversationHeaderAccount'),
          icon: Icons.inbox_outlined,
          label: account,
          color: colors.mutedForeground,
          semanticsLabel: l10n.conversationHeaderAccountSemantics(account),
        ),
      if (team != null && team.name.trim().isNotEmpty)
        ConversationTeamPill(team: team),
      if (assignee != null && assignee.fullName.trim().isNotEmpty)
        _MetaChip(
          key: const ValueKey('conversationHeaderAssignee'),
          icon: Icons.person_outline_rounded,
          label: assignee.fullName,
          color: colors.mutedForeground,
          semanticsLabel: l10n.assignedToSemantics(assignee.fullName),
        ),
    ];

    return Material(
      color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      shape: Border(bottom: BorderSide(color: colors.border)),
      child: Tooltip(
        message: l10n.customerDetailsTitle,
        child: InkWell(
          key: const Key('conversation_header_customer_area'),
          onTap: onOpenDetails,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.lg,
              Space.xs,
              Space.sm,
              Space.sm + Space.xxs,
            ),
            child: compact
                ? _compactRow(context, phone, metaLabels)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          // Its initials would only repeat the name aloud.
                          ExcludeSemantics(
                            child: InitialsAvatar(
                              initials: customer.initials,
                              imageUrl: customer.avatarUrl,
                              size: 40,
                              provider: conversation.provider,
                            ),
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    customer.displayName,
                                    key: const ValueKey(
                                      'conversationHeaderName',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                        ),
                                  ),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: Space.xxs),
                                  _PhoneLine(phone: phone),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: Space.xs),
                          // Says the block opens something.
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: colors.mutedForeground,
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      Wrap(
                        key: const ValueKey('conversationHeaderMeta'),
                        spacing: Space.xs + Space.xxs,
                        runSpacing: Space.xs + Space.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: chips,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Avatar, name and phone on one line; the rest is still read out.
  Widget _compactRow(
    BuildContext context,
    String phone,
    List<String> metaLabels,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final customer = conversation.customer;
    return Row(
      key: const ValueKey('conversationHeaderCompact'),
      children: [
        ExcludeSemantics(
          child: InitialsAvatar(
            initials: customer.initials,
            imageUrl: customer.avatarUrl,
            size: 28,
            provider: conversation.provider,
          ),
        ),
        const SizedBox(width: Space.sm),
        Flexible(
          flex: 3,
          child: Semantics(
            header: true,
            child: Text(
              customer.displayName,
              key: const ValueKey('conversationHeaderName'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(width: Space.sm),
          Flexible(flex: 2, child: _PhoneLine(phone: phone)),
        ],
        // Folded away visually, not from a screen reader.
        Semantics(label: metaLabels.join(', '), child: const SizedBox.shrink()),
        const Spacer(),
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: colors.mutedForeground,
        ),
      ],
    );
  }
}

/// The customer's number, whole: it shrinks to fit a very narrow screen
/// rather than being cut off, since a partial number is no use. Always
/// left-to-right, so in Arabic a leading `+` stays at the front.
class _PhoneLine extends StatelessWidget {
  const _PhoneLine({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      label: context.l10n.conversationHeaderPhoneSemantics(phone),
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('conversationHeaderPhone'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phone_outlined, size: 13, color: colors.mutedForeground),
          const SizedBox(width: Space.xs),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                phone,
                maxLines: 1,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact label with an icon, styled like [ConversationTeamPill] so the
/// row reads as one set. Never wider than the row: a long label ellipsizes
/// inside its own chip.
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.semanticsLabel,
    this.background,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String semanticsLabel;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: background ?? colors.muted,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The conversation's channel — WhatsApp, Messenger, Instagram, TikTok —
/// in its own colours.
class ConversationChannelChip extends StatelessWidget {
  const ConversationChannelChip({required this.provider, super.key});

  final String provider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, color, label) = providerInfo(context, provider, isDark);
    return _MetaChip(
      key: const ValueKey('conversationHeaderChannel'),
      icon: icon,
      label: label,
      color: color,
      background: color.withValues(alpha: isDark ? 0.16 : 0.1),
      semanticsLabel: context.l10n.conversationHeaderChannelSemantics(label),
    );
  }

  /// Glyph, text colour and name of the channel. The text colours are darker
  /// (light theme) or lighter (dark theme) than the brand colours, which
  /// are too faint as small text on either background.
  static (IconData, Color, String) providerInfo(
    BuildContext context,
    String provider,
    bool isDark,
  ) {
    final key = provider.toUpperCase();
    final label = switch (key) {
      'MESSENGER' => 'Messenger',
      'TELEGRAM' => 'Telegram',
      _ => ConversationBadges.providerLabel(context, key),
    };
    return switch (key) {
      'WHATSAPP' => (
        Icons.chat_bubble_rounded,
        isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
        label,
      ),
      'FACEBOOK' || 'MESSENGER' => (
        Icons.facebook,
        isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
        label,
      ),
      'INSTAGRAM' => (
        Icons.camera_alt_outlined,
        isDark ? const Color(0xFFFB7185) : const Color(0xFFBE123C),
        label,
      ),
      'TIKTOK' => (
        Icons.music_note,
        Theme.of(context).colorScheme.onSurface,
        label,
      ),
      'TELEGRAM' => (
        Icons.send_rounded,
        isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1),
        label,
      ),
      _ => (
        Icons.chat_bubble_outline_rounded,
        Theme.of(context).colorScheme.primary,
        label,
      ),
    };
  }
}
