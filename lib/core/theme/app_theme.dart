/// The Material theme assembled from the web design tokens, for each colour
/// theme in each brightness ([AppColorTheme], [AppPalette]).
///
/// Deliberately not Material 3's default palette generation: the web client
/// has an exact indigo and an exact set of greys, and letting Flutter derive a
/// scheme from a seed colour would produce something adjacent but visibly
/// different. Every colour here is pinned, per palette.
library;

import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'tokens.dart';

class AppTheme {
  const AppTheme._();

  /// The original (Ocean Blue) themes.
  static ThemeData get light => of(AppColorTheme.fallback, Brightness.light);
  static ThemeData get dark => of(AppColorTheme.fallback, Brightness.dark);

  static final _cache = <(AppColorTheme, Brightness), ThemeData>{};

  /// The app's typeface. [ThemeData.fontFamily] reaches the text theme, but
  /// not component styles written out in full below (app bar title, button
  /// label, chip, hint, snack bar) — those name it themselves, or fall back
  /// to the platform font.
  static const _font = 'Cairo';

  /// [colorTheme] in [brightness]. Built once per pair and reused, so
  /// switching themes or rebuilding the app never re-creates them.
  static ThemeData of(AppColorTheme colorTheme, Brightness brightness) =>
      _cache.putIfAbsent((
        colorTheme,
        brightness,
      ), () => _build(colorTheme.palette(brightness)));

  static ThemeData _build(AppPalette palette) {
    final brightness = palette.brightness;
    final background = palette.background;
    final surface = palette.surface;
    final onSurface = palette.foreground;
    final primary = palette.primary;
    final onPrimary = palette.onPrimary;
    final muted = palette.muted;
    final mutedForeground = palette.mutedForeground;
    final border = palette.border;
    final destructive = palette.destructive;

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
      // Cairo, bundled under assets/fonts/ (Regular/Medium/SemiBold/Bold),
      // renders both Arabic and Latin script from one face — the app's
      // typography hierarchy lives in the sizes/weights below, not here.
      fontFamily: _font,
      fontFamilyFallback: const ['SF Pro Text', 'Roboto', 'system-ui'],
      textTheme: _textTheme(onSurface, mutedForeground),
      extensions: [AppColors.fromPalette(palette)],
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _font,
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
        hintStyle: TextStyle(
          fontFamily: _font,
          color: mutedForeground,
          fontSize: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
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
        labelStyle: TextStyle(
          fontFamily: _font,
          color: onSurface,
          fontSize: 12,
        ),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.sidebar,
        contentTextStyle: const TextStyle(
          fontFamily: _font,
          color: Colors.white,
          fontSize: 14,
        ),
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
