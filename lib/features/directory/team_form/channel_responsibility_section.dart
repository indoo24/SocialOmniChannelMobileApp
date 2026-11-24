/// "Channel responsibilities" — which channels or accounts a team is
/// offered new conversations from, one expandable section per channel.
///
/// Per channel, the backend's own options (`TeamResponsibilityInput`):
///   * scope — none (provider left out), `all` accounts (including ones
///     connected later) or `selected` accounts (`channel_connection_ids`);
///   * `strict` — flexible (offered first, then routing settings decide) or
///     strict (never leaves the named people; stays unassigned).
///
/// Every value lives in the form's [ResponsibilityDrafts]; this widget only
/// draws them, so collapsing a section never loses anything.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/badges.dart';
import '../../../l10n/l10n_extensions.dart';
import 'team_responsibility_state.dart';

/// Above this many accounts a channel offers a search box (the web's own
/// threshold).
const _accountSearchThreshold = 5;

/// "WhatsApp numbers", "Facebook Pages"… — how each channel calls its
/// accounts.
String teamAccountsNoun(BuildContext context, String provider) =>
    switch (provider) {
      'WHATSAPP' => context.l10n.teamAccountsWhatsapp,
      'FACEBOOK' => context.l10n.teamAccountsFacebook,
      'INSTAGRAM' => context.l10n.teamAccountsInstagram,
      'TIKTOK' => context.l10n.teamAccountsTiktok,
      _ => provider,
    };

class ChannelResponsibilitySection extends StatelessWidget {
  const ChannelResponsibilitySection({
    required this.drafts,
    required this.accounts,
    required this.accountsLoading,
    required this.accountsFailed,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.enabled,
    this.providerErrors = const {},
    this.error,
    this.redundantProviders = const [],
    this.sectionKeys = const {},
    super.key,
  });

  final ResponsibilityDrafts drafts;

  /// Account options per provider.
  final Map<String, List<ResponsibilityAccountOption>> accounts;
  final bool accountsLoading;
  final bool accountsFailed;
  final Set<String> expanded;
  final ValueChanged<String> onToggleExpanded;
  final void Function(String provider, ChannelResponsibilityDraft draft)
  onChanged;
  final bool enabled;

  /// A message under one channel — e.g. "selected" with nothing ticked.
  final Map<String, String> providerErrors;

  /// A message for the whole section (the server's `responsibilities`).
  final String? error;

  /// See [redundantRuleProviders].
  final List<String> redundantProviders;

  /// Lets the form scroll a channel with an error into view.
  final Map<String, GlobalKey> sectionKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.teamResponsibilitiesTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(l10n.teamResponsibilitiesDescription, style: muted),
        const SizedBox(height: Space.xxs),
        Text(
          l10n.teamResponsibilityNotVisibility,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        if (redundantProviders.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Container(
            key: const ValueKey('teamResponsibilityRedundant'),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Text(
              l10n.teamResponsibilityRedundantRules(
                redundantProviders
                    .map((p) => ConversationBadges.providerLabel(context, p))
                    .join(', '),
              ),
              style: muted,
            ),
          ),
        ],
        const SizedBox(height: Space.md),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Column(
            children: [
              for (final provider in routableProviders) ...[
                if (provider != routableProviders.first)
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ChannelResponsibilityTile(
                  key:
                      sectionKeys[provider] ??
                      ValueKey('teamChannelTile_$provider'),
                  provider: provider,
                  draft: drafts[provider] ?? const ChannelResponsibilityDraft(),
                  accounts: accounts[provider] ?? const [],
                  accountsLoading: accountsLoading,
                  accountsFailed: accountsFailed,
                  expanded: expanded.contains(provider),
                  onToggleExpanded: () => onToggleExpanded(provider),
                  onChanged: (draft) => onChanged(provider, draft),
                  enabled: enabled,
                  error: providerErrors[provider],
                ),
              ],
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            error!,
            key: const ValueKey('teamResponsibilityError'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// One channel: a header that says what is chosen, and — when expanded —
/// the scope, the mode and the accounts.
class ChannelResponsibilityTile extends StatefulWidget {
  const ChannelResponsibilityTile({
    required this.provider,
    required this.draft,
    required this.accounts,
    required this.accountsLoading,
    required this.accountsFailed,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.enabled,
    this.error,
    super.key,
  });

  final String provider;
  final ChannelResponsibilityDraft draft;
  final List<ResponsibilityAccountOption> accounts;
  final bool accountsLoading;
  final bool accountsFailed;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<ChannelResponsibilityDraft> onChanged;
  final bool enabled;
  final String? error;

  @override
  State<ChannelResponsibilityTile> createState() =>
      _ChannelResponsibilityTileState();
}

class _ChannelResponsibilityTileState extends State<ChannelResponsibilityTile> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _summary(BuildContext context) {
    final l10n = context.l10n;
    final noun = teamAccountsNoun(context, widget.provider);
    return switch (widget.draft.mode) {
      ResponsibilityMode.none => l10n.teamResponsibilityNone,
      ResponsibilityMode.all => l10n.teamResponsibilityAllOf(noun),
      ResponsibilityMode.selected => l10n.teamResponsibilitySelectedCount(
        widget.draft.connectionIds.length,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final provider = widget.provider;
    final name = ConversationBadges.providerLabel(context, provider);
    final hasError = widget.error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: widget.expanded,
          child: InkWell(
            key: ValueKey('teamChannel_$provider'),
            onTap: widget.onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  Icon(
                    ConversationBadges.providerIcon(provider),
                    size: 22,
                    color: ConversationBadges.providerColor(provider),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _summary(context),
                          key: ValueKey('teamChannelSummary_$provider'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hasError
                                ? theme.colorScheme.error
                                : colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: widget.expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: AlignmentDirectional.topCenter,
          child: widget.expanded
              ? _body(context, name)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, String providerName) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final draft = widget.draft;
    final provider = widget.provider;
    final noun = teamAccountsNoun(context, provider);
    final accounts = widget.accounts;
    final noAccounts =
        !widget.accountsLoading && !widget.accountsFailed && accounts.isEmpty;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedForeground,
    );

    final modes = [
      (ResponsibilityMode.none, l10n.teamResponsibilityNone),
      (ResponsibilityMode.all, l10n.teamResponsibilityAllOf(noun)),
      (ResponsibilityMode.selected, l10n.teamResponsibilitySelectedOf(noun)),
    ];

    return Container(
      key: ValueKey('teamChannelBody_$provider'),
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.xs,
        Space.xs,
        Space.md,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<ResponsibilityMode>(
            groupValue: draft.mode,
            onChanged: (mode) {
              if (!widget.enabled || mode == null) return;
              widget.onChanged(draft.withMode(mode));
            },
            child: Column(
              children: [
                for (final (mode, label) in modes)
                  RadioListTile<ResponsibilityMode>(
                    key: ValueKey('teamChannelMode_${provider}_${mode.name}'),
                    value: mode,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    // "Selected" needs something to select.
                    enabled:
                        widget.enabled &&
                        !(mode == ResponsibilityMode.selected && noAccounts),
                    title: Text(label, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
          ),
          if (draft.mode == ResponsibilityMode.all)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.xl + Space.lg,
                bottom: Space.sm,
              ),
              child: Text(l10n.teamResponsibilityIncludesFuture, style: hint),
            ),
          if (draft.mode != ResponsibilityMode.none)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.md,
                top: Space.xs,
                bottom: Space.sm,
              ),
              child: _StrictPicker(
                provider: provider,
                providerName: providerName,
                strict: draft.strict,
                enabled: widget.enabled,
                onChanged: (value) => widget.onChanged(draft.withStrict(value)),
              ),
            ),
          if (widget.accountsLoading)
            const Padding(
              padding: EdgeInsets.all(Space.md),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (widget.accountsFailed && accounts.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.md),
              child: Text(
                l10n.teamResponsibilityAccountsLoadFailed,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            )
          else if (noAccounts)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.md),
              child: Text(l10n.teamResponsibilityNoAccounts(noun), style: hint),
            )
          else if (draft.mode == ResponsibilityMode.selected)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.md),
              child: _accountList(context),
            ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.md,
                top: Space.sm,
              ),
              child: Text(
                widget.error!,
                key: ValueKey('teamChannelError_$provider'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _accountList(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final provider = widget.provider;
    final accounts = widget.accounts;
    final shown = accounts.where((a) => a.matches(_query)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (accounts.length > _accountSearchThreshold) ...[
          TextField(
            key: ValueKey('teamChannelSearch_$provider'),
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.teamResponsibilitySearchAccounts,
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Text(
                    l10n.teamResponsibilityNoAccountMatch(_query.trim()),
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final account in shown)
                      InkWell(
                        key: ValueKey('teamAccount_${account.id}'),
                        onTap: widget.enabled
                            ? () => widget.onChanged(
                                widget.draft.toggle(account.id),
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: Space.sm,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                key: ValueKey('teamAccountCheck_${account.id}'),
                                value: widget.draft.selectedIds.contains(
                                  account.id,
                                ),
                                semanticLabel: account.name,
                                onChanged: widget.enabled
                                    ? (_) => widget.onChanged(
                                        widget.draft.toggle(account.id),
                                      )
                                    : null,
                              ),
                              Expanded(
                                child: Text(
                                  account.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              if (account.detail.isNotEmpty) ...[
                                const SizedBox(width: Space.xs),
                                Flexible(
                                  child: Text(
                                    account.detail,
                                    textDirection: TextDirection.ltr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.mutedForeground,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (!account.connected) ...[
                                const SizedBox(width: Space.xs),
                                _MutedBadge(
                                  l10n.teamResponsibilityNotConnected,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// "Mode: Flexible | Strict", with what the chosen one means.
class _StrictPicker extends StatelessWidget {
  const _StrictPicker({
    required this.provider,
    required this.providerName,
    required this.strict,
    required this.enabled,
    required this.onChanged,
  });

  final String provider;
  final String providerName;
  final bool strict;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.teamResponsibilityModeLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.xs),
        Semantics(
          label: '$providerName: ${l10n.teamResponsibilityModeLabel}',
          child: SegmentedButton<bool>(
            key: ValueKey('teamChannelStrict_$provider'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  l10n.teamResponsibilityFlexible,
                  key: ValueKey('teamChannelFlexible_$provider'),
                ),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  l10n.teamResponsibilityStrict,
                  key: ValueKey('teamChannelStrictOption_$provider'),
                ),
              ),
            ],
            selected: {strict},
            onSelectionChanged: enabled
                ? (values) => onChanged(values.first)
                : null,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          strict
              ? l10n.teamResponsibilityStrictHint
              : l10n.teamResponsibilityFlexibleHint,
          key: ValueKey('teamChannelStrictHint_$provider'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _MutedBadge extends StatelessWidget {
  const _MutedBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
      ),
    );
  }
}
