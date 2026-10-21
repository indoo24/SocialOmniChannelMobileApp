/// Settings → Appearance: the colour theme and light/dark/system mode.
///
/// Both apply at once — the app's [MaterialApp] watches the same providers —
/// and both are stored on the device (see `preferences_controller.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences/preferences_controller.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';

class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final mode = ref.watch(themeModeProvider);
    final selected = ref.watch(colorThemeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.appearanceModeLabel, style: theme.textTheme.bodySmall),
        const SizedBox(height: Space.sm),
        SegmentedButton<ThemeMode>(
          key: const Key('appearanceMode'),
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_outlined),
              label: Text(l10n.themeSystem),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(l10n.themeLight),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(l10n.themeDark),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) =>
              ref.read(themeModeProvider.notifier).update(value.single),
        ),
        const SizedBox(height: Space.lg),
        Text(l10n.colorThemeLabel, style: theme.textTheme.bodySmall),
        const SizedBox(height: Space.sm),
        for (final colorTheme in AppColorTheme.values) ...[
          _ThemeOption(
            colorTheme: colorTheme,
            selected: colorTheme == selected,
            onTap: () =>
                ref.read(colorThemeProvider.notifier).update(colorTheme),
          ),
          const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}

/// The localized name and one-line description of [theme].
(String, String) colorThemeLabels(AppLocalizations l10n, AppColorTheme theme) =>
    switch (theme) {
      AppColorTheme.oceanBlue => (
        l10n.colorThemeOceanBlue,
        l10n.colorThemeOceanBlueDescription,
      ),
      AppColorTheme.emerald => (
        l10n.colorThemeEmerald,
        l10n.colorThemeEmeraldDescription,
      ),
      AppColorTheme.royalPurple => (
        l10n.colorThemeRoyalPurple,
        l10n.colorThemeRoyalPurpleDescription,
      ),
      AppColorTheme.graphiteOrange => (
        l10n.colorThemeGraphiteOrange,
        l10n.colorThemeGraphiteOrangeDescription,
      ),
    };

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.colorTheme,
    required this.selected,
    required this.onTap,
  });

  final AppColorTheme colorTheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final (name, description) = colorThemeLabels(context.l10n, colorTheme);
    // Previewed in the brightness currently on screen.
    final preview = colorTheme.palette(theme.brightness);

    return Semantics(
      button: true,
      selected: selected,
      label: name,
      hint: description,
      excludeSemantics: true,
      child: Material(
        key: Key('colorTheme-${colorTheme.id}'),
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(
            color: selected ? colors.primary : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                _PalettePreview(palette: preview),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(description, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                // A check, not only the border colour, marks the choice.
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.primary : colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thumbnail of the theme: its page, sidebar, a message from each side and
/// an accent button.
class _PalettePreview extends StatelessWidget {
  const _PalettePreview({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget bar(Color color, double width, {double height = 6}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );

    return Container(
      width: 72,
      height: 52,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 14, color: palette.sidebar),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: bar(palette.surface, 30, height: 8),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: bar(palette.outgoingBubble, 26, height: 8),
                  ),
                  bar(palette.primary, 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
