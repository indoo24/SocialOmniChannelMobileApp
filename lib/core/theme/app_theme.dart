/// The Material theme assembled from the web design tokens.
///
/// Deliberately not Material 3's default palette generation: the web client
/// has an exact indigo and an exact set of greys, and letting Flutter derive a
/// scheme from a seed colour would produce something adjacent but visibly
/// different. Every colour here is pinned.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: ScenarioColors.background,
        surface: ScenarioColors.card,
        onSurface: ScenarioColors.foreground,
        primary: ScenarioColors.primary,
        onPrimary: ScenarioColors.primaryForeground,
        muted: ScenarioColors.muted,
        mutedForeground: ScenarioColors.mutedForeground,
        border: ScenarioColors.border,
        destructive: ScenarioColors.destructive,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: ScenarioColors.darkBackground,
        surface: ScenarioColors.darkCard,
        onSurface: ScenarioColors.darkForeground,
        primary: ScenarioColors.darkPrimary,
        onPrimary: ScenarioColors.darkPrimaryForeground,
        muted: ScenarioColors.darkMuted,
        mutedForeground: ScenarioColors.darkMutedForeground,
        border: ScenarioColors.darkBorder,
        destructive: ScenarioColors.darkDestructive,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color primary,
    required Color onPrimary,
    required Color muted,
    required Color mutedForeground,
    required Color border,
    required Color destructive,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: muted,
      onSecondary: onSurface,
      error: destructive,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: muted,
      outline: border,
      outlineVariant: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      // Inter is the web client's face. Falling back to the platform default
      // rather than bundling a 400KB font for a first release; the hierarchy
      // below is what actually carries the visual identity.
      fontFamily: 'Inter',
      fontFamilyFallback: const ['SF Pro Text', 'Roboto', 'system-ui'],
      textTheme: _textTheme(onSurface, mutedForeground),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        shape: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: destructive),
        ),
        hintStyle: TextStyle(color: mutedForeground, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: border),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: mutedForeground,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: muted,
        labelStyle: TextStyle(color: onSurface, fontSize: 12),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ScenarioColors.sidebar,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Color foreground, Color muted) => TextTheme(
        titleLarge: TextStyle(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: foreground,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: foreground, fontSize: 15, height: 1.4),
        bodyMedium: TextStyle(color: foreground, fontSize: 14, height: 1.4),
        bodySmall: TextStyle(color: muted, fontSize: 12, height: 1.35),
        labelSmall: TextStyle(
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
}
