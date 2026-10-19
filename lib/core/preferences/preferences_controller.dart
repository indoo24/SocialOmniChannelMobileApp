/// Device display preferences: colour theme, theme mode and language.
///
/// Same pattern as [AuthController]'s session restore: each notifier starts
/// with a safe default so the first frame never blocks on a storage read,
/// then [restore] (called once from `main.dart` at launch) asynchronously
/// applies whatever was persisted. Persisted via [SecureStore] rather than a
/// new dependency — not because these are sensitive, but because it is
/// already the app's one local key-value store.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_palette.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> restore() async {
    final saved = await ref.read(secureStoreProvider).readThemeMode();
    final mode = _fromKey(saved);
    if (mode != null) state = mode;
  }

  Future<void> update(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(secureStoreProvider).writeThemeMode(_toKey(mode));
  }

  static String _toKey(ThemeMode mode) => mode.name;

  static ThemeMode? _fromKey(String? key) => switch (key) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Which [AppColorTheme] the app is drawn in — independent of [ThemeMode],
/// which picks its light or dark variant. Starts at the original Ocean Blue,
/// so an installation that never chose keeps looking as it always has, and a
/// stored id the app no longer knows falls back to it too.
class ColorThemeController extends Notifier<AppColorTheme> {
  @override
  AppColorTheme build() => AppColorTheme.fallback;

  Future<void> restore() async {
    final saved = await ref.read(secureStoreProvider).readColorTheme();
    final theme = AppColorTheme.fromId(saved);
    if (theme != null) state = theme;
  }

  Future<void> update(AppColorTheme theme) async {
    if (theme == state) return;
    state = theme;
    await ref.read(secureStoreProvider).writeColorTheme(theme.id);
  }
}

final colorThemeProvider =
    NotifierProvider<ColorThemeController, AppColorTheme>(
      ColorThemeController.new,
    );

/// English and Arabic only, per the product requirement — not a "system"
/// option like theme, since the app has no strings for any other language
/// to fall back to.
class LocaleController extends Notifier<Locale> {
  static const fallback = Locale('en');
  static const supported = [Locale('en'), Locale('ar')];

  @override
  Locale build() => fallback;

  Future<void> restore() async {
    final saved = await ref.read(secureStoreProvider).readLocale();
    if (saved != null && supported.any((l) => l.languageCode == saved)) {
      state = Locale(saved);
    }
  }

  Future<void> update(Locale locale) async {
    if (locale == state) return;
    state = locale;
    await ref.read(secureStoreProvider).writeLocale(locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);

/// Restores every display preference. Never throws: an unreadable store
/// leaves the defaults in place rather than holding the app up.
Future<void> restoreDisplayPreferences(
  ThemeModeController themeMode,
  ColorThemeController colorTheme,
  LocaleController locale,
) async {
  Future<void> safely(Future<void> Function() restore) async {
    try {
      await restore();
    } catch (_) {
      // Defaults stay; nothing here is worth blocking launch over.
    }
  }

  await Future.wait([
    safely(themeMode.restore),
    safely(colorTheme.restore),
    safely(locale.restore),
  ]);
}
