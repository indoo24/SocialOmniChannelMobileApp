/// The colour themes an agent can choose from, and the semantic colours every
/// screen draws with.
///
/// Each theme is designed for light and dark separately rather than derived
/// from one accent: surfaces, text and borders are tuned per theme so the
/// accent reads well on them. What does *not* change between themes is what
/// carries meaning — success is green, warning amber, danger red in every
/// theme, and each theme's "info" is a blue or indigo that stays clear of its
/// own accent so "New" never looks like "Open".
///
/// Ocean Blue is the original Scenario palette, value for value, so existing
/// installations look exactly as before.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Converts the CSS-style `hsl(H S% L%)` triples the palettes are written in.
Color _hsl(double h, double s, double l) =>
    HSLColor.fromAHSL(1.0, h, s / 100, l / 100).toColor();

/// A selectable colour theme. [id] is what is stored on the device; never
/// rename one, or saved choices fall back to the default.
enum AppColorTheme {
  oceanBlue('ocean_blue'),
  emerald('emerald'),
  royalPurple('royal_purple'),
  graphiteOrange('graphite_orange');

  const AppColorTheme(this.id);

  final String id;

  static const fallback = AppColorTheme.oceanBlue;

  /// The theme stored as [id], or null for a missing or unknown value.
  static AppColorTheme? fromId(String? id) {
    for (final theme in values) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  AppPalette palette(Brightness brightness) => AppPalette.of(this, brightness);
}

/// Every colour one theme uses in one brightness.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.foreground,
    required this.primary,
    required this.onPrimary,
    required this.solidPrimary,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarAccent,
    required this.outgoingBubble,
    required this.info,
    required this.infoSurface,
    required this.destructive,
  });

  final Brightness brightness;

  /// The page behind everything.
  final Color background;

  /// Cards, sheets, dialogs, app bars, input fields, incoming bubbles.
  final Color surface;
  final Color foreground;

  /// The accent: primary buttons, selection, links, unread counts.
  final Color primary;
  final Color onPrimary;

  /// The accent as a fill under white text, in either brightness — the
  /// sidebar's highlights, solid accent buttons. In light themes it is
  /// [primary]; dark themes keep the deeper tone, since their lighter
  /// [primary] cannot carry white text.
  final Color solidPrimary;

  /// Quiet fills: chips, placeholders, unselected pills.
  final Color muted;

  /// Secondary text: previews, timestamps, captions.
  final Color mutedForeground;
  final Color border;

  /// The navigation drawer (the web client's sidebar) and snack bars: a
  /// dark slab in both brightnesses.
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarAccent;

  /// The agent's own messages; always carries white text.
  final Color outgoingBubble;

  /// Informational badges ("New", "You") and read ticks.
  final Color info;
  final Color infoSurface;
  final Color destructive;

  bool get isDark => brightness == Brightness.dark;

  static AppPalette of(AppColorTheme theme, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (theme) {
      AppColorTheme.oceanBlue => dark ? _oceanDark : _oceanLight,
      AppColorTheme.emerald => dark ? _emeraldDark : _emeraldLight,
      AppColorTheme.royalPurple => dark ? _purpleDark : _purpleLight,
      AppColorTheme.graphiteOrange => dark ? _graphiteDark : _graphiteLight,
    };
  }

  // --- Ocean Blue: the original palette (tokens.dart) ---------------------
  static final _oceanLight = AppPalette(
    brightness: Brightness.light,
    background: ScenarioColors.background,
    surface: ScenarioColors.card,
    foreground: ScenarioColors.foreground,
    primary: ScenarioColors.primary,
    onPrimary: ScenarioColors.primaryForeground,
    solidPrimary: ScenarioColors.primary,
    muted: ScenarioColors.muted,
    mutedForeground: ScenarioColors.mutedForeground,
    border: ScenarioColors.border,
    sidebar: ScenarioColors.sidebar,
    sidebarForeground: ScenarioColors.sidebarForeground,
    sidebarAccent: ScenarioColors.sidebarAccent,
    outgoingBubble: ScenarioColors.primary,
    info: ScenarioColors.info,
    infoSurface: ScenarioColors.infoSurface,
    destructive: ScenarioColors.destructive,
  );

  static final _oceanDark = AppPalette(
    brightness: Brightness.dark,
    background: ScenarioColors.darkBackground,
    surface: ScenarioColors.darkCard,
    foreground: ScenarioColors.darkForeground,
    primary: ScenarioColors.darkPrimary,
    onPrimary: ScenarioColors.darkPrimaryForeground,
    solidPrimary: ScenarioColors.primary,
    muted: ScenarioColors.darkMuted,
    mutedForeground: ScenarioColors.darkMutedForeground,
    border: ScenarioColors.darkBorder,
    sidebar: ScenarioColors.sidebar,
    sidebarForeground: ScenarioColors.sidebarForeground,
    sidebarAccent: ScenarioColors.sidebarAccent,
    outgoingBubble: ScenarioColors.darkOutgoingBubble,
    info: ScenarioColors.darkPrimary,
    infoSurface: ScenarioColors.info.withValues(alpha: 0.18),
    destructive: ScenarioColors.darkDestructive,
  );

  // --- Emerald: calm greens; info is blue so it never reads as "Open" -----
  static final _emeraldLight = AppPalette(
    brightness: Brightness.light,
    background: _hsl(150, 20, 98),
    surface: _hsl(0, 0, 100),
    foreground: _hsl(165, 35, 10),
    primary: _hsl(161, 84, 27),
    onPrimary: _hsl(0, 0, 100),
    solidPrimary: _hsl(161, 84, 27),
    muted: _hsl(150, 24, 95),
    mutedForeground: _hsl(162, 10, 38),
    border: _hsl(150, 18, 88),
    sidebar: _hsl(165, 40, 10),
    sidebarForeground: _hsl(150, 18, 82),
    sidebarAccent: _hsl(162, 32, 18),
    outgoingBubble: _hsl(161, 84, 27),
    info: _hsl(217, 85, 48),
    infoSurface: _hsl(214, 100, 96),
    destructive: ScenarioColors.destructive,
  );

  static final _emeraldDark = AppPalette(
    brightness: Brightness.dark,
    background: _hsl(165, 35, 6),
    surface: _hsl(165, 28, 10),
    foreground: _hsl(150, 20, 95),
    primary: _hsl(158, 60, 52),
    onPrimary: _hsl(165, 45, 7),
    solidPrimary: _hsl(161, 84, 27),
    muted: _hsl(163, 22, 16),
    mutedForeground: _hsl(155, 12, 66),
    border: _hsl(163, 20, 20),
    sidebar: _hsl(165, 40, 9),
    sidebarForeground: _hsl(150, 18, 82),
    sidebarAccent: _hsl(162, 30, 18),
    outgoingBubble: _hsl(161, 84, 26),
    info: _hsl(213, 94, 70),
    infoSurface: _hsl(217, 85, 48).withValues(alpha: 0.2),
    destructive: ScenarioColors.darkDestructive,
  );

  // --- Royal Purple: deep violet accents ----------------------------------
  static final _purpleLight = AppPalette(
    brightness: Brightness.light,
    background: _hsl(270, 20, 98),
    surface: _hsl(0, 0, 100),
    foreground: _hsl(266, 40, 12),
    primary: _hsl(271, 70, 48),
    onPrimary: _hsl(0, 0, 100),
    solidPrimary: _hsl(271, 70, 48),
    muted: _hsl(270, 30, 96),
    mutedForeground: _hsl(266, 12, 44),
    border: _hsl(270, 24, 91),
    sidebar: _hsl(266, 45, 12),
    sidebarForeground: _hsl(268, 24, 84),
    sidebarAccent: _hsl(266, 35, 22),
    outgoingBubble: _hsl(271, 70, 48),
    info: _hsl(217, 85, 48),
    infoSurface: _hsl(214, 100, 96),
    destructive: ScenarioColors.destructive,
  );

  static final _purpleDark = AppPalette(
    brightness: Brightness.dark,
    background: _hsl(266, 40, 7),
    surface: _hsl(266, 34, 11),
    foreground: _hsl(270, 30, 96),
    primary: _hsl(270, 85, 76),
    onPrimary: _hsl(266, 45, 10),
    solidPrimary: _hsl(271, 70, 48),
    muted: _hsl(266, 26, 17),
    mutedForeground: _hsl(268, 15, 68),
    border: _hsl(266, 24, 21),
    sidebar: _hsl(266, 45, 10),
    sidebarForeground: _hsl(268, 24, 84),
    sidebarAccent: _hsl(266, 35, 22),
    outgoingBubble: _hsl(271, 65, 45),
    info: _hsl(213, 94, 70),
    infoSurface: _hsl(217, 85, 48).withValues(alpha: 0.2),
    destructive: ScenarioColors.darkDestructive,
  );

  // --- Graphite Orange: neutral greys with a burnt-orange accent ----------
  static final _graphiteLight = AppPalette(
    brightness: Brightness.light,
    background: _hsl(30, 10, 97),
    surface: _hsl(0, 0, 100),
    foreground: _hsl(220, 14, 12),
    primary: _hsl(18, 88, 40),
    onPrimary: _hsl(0, 0, 100),
    solidPrimary: _hsl(18, 88, 40),
    muted: _hsl(30, 10, 94),
    mutedForeground: _hsl(220, 8, 40),
    border: _hsl(30, 8, 87),
    sidebar: _hsl(220, 14, 12),
    sidebarForeground: _hsl(220, 10, 82),
    sidebarAccent: _hsl(220, 12, 21),
    outgoingBubble: _hsl(18, 88, 40),
    info: _hsl(217, 85, 48),
    infoSurface: _hsl(214, 100, 96),
    destructive: ScenarioColors.destructive,
  );

  static final _graphiteDark = AppPalette(
    brightness: Brightness.dark,
    background: _hsl(220, 13, 7),
    surface: _hsl(220, 12, 11),
    foreground: _hsl(30, 10, 95),
    primary: _hsl(25, 95, 60),
    onPrimary: _hsl(220, 15, 8),
    solidPrimary: _hsl(18, 88, 40),
    muted: _hsl(220, 10, 17),
    mutedForeground: _hsl(220, 8, 67),
    border: _hsl(220, 10, 21),
    sidebar: _hsl(220, 14, 10),
    sidebarForeground: _hsl(220, 10, 82),
    sidebarAccent: _hsl(220, 12, 21),
    outgoingBubble: _hsl(18, 85, 38),
    info: _hsl(213, 94, 70),
    infoSurface: _hsl(217, 85, 48).withValues(alpha: 0.2),
    destructive: ScenarioColors.darkDestructive,
  );
}

/// The semantic colours of the active theme, for widgets that draw beyond
/// what [ColorScheme] names: the sidebar, bubbles, status badges and the
/// like. Read with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.foreground,
    required this.primary,
    required this.onPrimary,
    required this.solidPrimary,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarAccent,
    required this.outgoingBubble,
    required this.onOutgoingBubble,
    required this.incomingBubble,
    required this.link,
    required this.info,
    required this.infoSurface,
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.danger,
    required this.dangerSurface,
    required this.unreadBadge,
    required this.onUnreadBadge,
  });

  factory AppColors.fromPalette(AppPalette p) {
    // Status colours mean the same in every theme; only their tint surfaces
    // follow the brightness.
    Color tint(Color c, Color lightSurface) =>
        p.isDark ? c.withValues(alpha: 0.18) : lightSurface;
    return AppColors(
      background: p.background,
      surface: p.surface,
      foreground: p.foreground,
      primary: p.primary,
      onPrimary: p.onPrimary,
      solidPrimary: p.solidPrimary,
      muted: p.muted,
      mutedForeground: p.mutedForeground,
      border: p.border,
      sidebar: p.sidebar,
      sidebarForeground: p.sidebarForeground,
      sidebarAccent: p.sidebarAccent,
      outgoingBubble: p.outgoingBubble,
      onOutgoingBubble: Colors.white,
      incomingBubble: p.surface,
      link: p.primary,
      info: p.info,
      infoSurface: p.infoSurface,
      success: ScenarioColors.success,
      successSurface: tint(
        ScenarioColors.success,
        ScenarioColors.successSurface,
      ),
      warning: ScenarioColors.warning,
      warningSurface: tint(
        ScenarioColors.warning,
        ScenarioColors.warningSurface,
      ),
      danger: ScenarioColors.danger,
      dangerSurface: tint(ScenarioColors.danger, ScenarioColors.dangerSurface),
      unreadBadge: p.primary,
      onUnreadBadge: p.onPrimary,
    );
  }

  final Color background;
  final Color surface;
  final Color foreground;
  final Color primary;
  final Color onPrimary;

  /// See [AppPalette.solidPrimary]: the accent under white text.
  final Color solidPrimary;
  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarAccent;
  final Color outgoingBubble;
  final Color onOutgoingBubble;
  final Color incomingBubble;

  /// Links on the page and in incoming bubbles. (On the agent's own bubble a
  /// link is the bubble's white, underlined.)
  final Color link;
  final Color info;
  final Color infoSurface;
  final Color success;
  final Color successSurface;
  final Color warning;
  final Color warningSurface;
  final Color danger;
  final Color dangerSurface;
  final Color unreadBadge;
  final Color onUnreadBadge;

  /// The active theme's colours. Falls back to Ocean Blue for a theme built
  /// without the extension (a bare `ThemeData()` in a test, say).
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        AppColors.fromPalette(AppColorTheme.fallback.palette(theme.brightness));
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      foreground: l(foreground, other.foreground),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      solidPrimary: l(solidPrimary, other.solidPrimary),
      muted: l(muted, other.muted),
      mutedForeground: l(mutedForeground, other.mutedForeground),
      border: l(border, other.border),
      sidebar: l(sidebar, other.sidebar),
      sidebarForeground: l(sidebarForeground, other.sidebarForeground),
      sidebarAccent: l(sidebarAccent, other.sidebarAccent),
      outgoingBubble: l(outgoingBubble, other.outgoingBubble),
      onOutgoingBubble: l(onOutgoingBubble, other.onOutgoingBubble),
      incomingBubble: l(incomingBubble, other.incomingBubble),
      link: l(link, other.link),
      info: l(info, other.info),
      infoSurface: l(infoSurface, other.infoSurface),
      success: l(success, other.success),
      successSurface: l(successSurface, other.successSurface),
      warning: l(warning, other.warning),
      warningSurface: l(warningSurface, other.warningSurface),
      danger: l(danger, other.danger),
      dangerSurface: l(dangerSurface, other.dangerSurface),
      unreadBadge: l(unreadBadge, other.unreadBadge),
      onUnreadBadge: l(onUnreadBadge, other.onUnreadBadge),
    );
  }
}
