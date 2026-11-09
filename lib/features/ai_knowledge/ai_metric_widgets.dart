/// The building blocks the AI section's tabs share: a tab's opening line,
/// titled sections, a grid of compact metric tiles, a list of choices, and
/// the "not available" state.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/states.dart';
import '../../l10n/l10n_extensions.dart';

/// The line under the tab bar that says what a tab is for.
class AiTabHint extends StatelessWidget {
  const AiTabHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.of(context).mutedForeground,
        ),
      ),
    );
  }
}

/// "Not available", for a role or organization outside the AI pilot.
class AiNotAvailable extends StatelessWidget {
  const AiNotAvailable({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      key: const Key('ai-knowledge-not-available'),
      icon: Icons.lock_outline,
      title: context.l10n.aiNotAvailableTitle,
      message: context.l10n.aiNotAvailableMessage,
    );
  }
}

/// A heading with its icon and what sits under it, with no card around it.
class AiHeadedSection extends StatelessWidget {
  const AiHeadedSection({
    required this.icon,
    required this.title,
    required this.child,
    super.key,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        child,
      ],
    );
  }
}

/// A radio list drawn as bordered cards: each choice with its label, an
/// optional line under it, and an optional badge ("Recommended").
class AiChoiceCards extends StatelessWidget {
  const AiChoiceCards({
    required this.groupKey,
    required this.values,
    required this.current,
    required this.enabled,
    required this.label,
    required this.onChanged,
    this.hint,
    this.badge,
    super.key,
  });

  final String groupKey;
  final List<String> values;
  final String current;
  final bool enabled;
  final String Function(String) label;
  final String Function(String)? hint;
  final String? Function(String)? badge;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    // A value this app does not know is still shown as the server has it.
    final options = [
      ...values,
      if (current.isNotEmpty && !values.contains(current)) current,
    ];
    void choose(String? value) {
      if (enabled && value != null && value != current) onChanged(value);
    }

    return RadioGroup<String>(
      groupValue: current,
      onChanged: choose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final value in options) ...[
            InkWell(
              key: Key('ai-$groupKey-$value'),
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: enabled ? () => choose(value) : null,
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Space.xs,
                  Space.xs,
                  Space.md,
                  Space.xs,
                ),
                decoration: BoxDecoration(
                  color: value == current
                      ? theme.colorScheme.primary.withValues(alpha: 0.05)
                      : null,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: value == current
                        ? theme.colorScheme.primary
                        : colors.border,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<String>(value: value, enabled: enabled),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: Space.xs,
                              runSpacing: Space.xxs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  label(value),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (badge?.call(value) case final text?)
                                  StatusBadge(
                                    label: text,
                                    dense: true,
                                    tone: BadgeTone.info,
                                  ),
                              ],
                            ),
                            if (hint?.call(value) case final text?
                                when text.isNotEmpty)
                              Text(
                                text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (value != options.last) const SizedBox(height: Space.xs),
          ],
        ],
      ),
    );
  }
}

/// A titled block on the card surface the AI screens use.
class AiSectionCard extends StatelessWidget {
  const AiSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    // A Material rather than a decorated box: the switches, radios and list
    // rows these sections hold draw their ink on the nearest Material.
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: Space.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: Space.xxs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// One number on the dashboard: what it is, its value, and an optional
/// line under it (`3 of 12 drafts`). With [onTap] it opens what changes it.
class AiMetricTile extends StatelessWidget {
  const AiMetricTile({
    required this.label,
    required this.value,
    this.hint,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      label: hint == null ? '$label: $value' : '$label: $value, $hint',
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: Space.xxs),
              Text(
                value,
                // Numbers, percentages and durations read left to right in
                // either language.
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiles two to a row on a phone, four once there is room.
class AiMetricGrid extends StatelessWidget {
  const AiMetricGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 560 ? 4 : 2;
        final width = (constraints.maxWidth - Space.sm * (perRow - 1)) / perRow;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
