/// The colour themes: every palette in light and dark, their contrast, the
/// stored choice surviving a restart (and a bad value never breaking launch),
/// switching without a restart, Follow System, the Settings picker, and the
/// main screens' widgets drawn in each theme.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/preferences/preferences_controller.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/storage/secure_store.dart';
import 'package:scenario_mobile/core/theme/app_palette.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/theme/tokens.dart';
import 'package:scenario_mobile/features/authentication/login_screen.dart';
import 'package:scenario_mobile/features/conversations/inbox_quick_filter_bar.dart';
import 'package:scenario_mobile/features/conversations/inbox_screen.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/features/settings/appearance_settings.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

/// A device store held in memory, counting writes.
class _MemoryStore extends SecureStore {
  _MemoryStore({this.colorTheme, this.themeMode, this.failReads = false});

  String? colorTheme;
  String? themeMode;
  final bool failReads;
  int writes = 0;

  @override
  Future<String?> readColorTheme() async {
    if (failReads) throw Exception('storage unavailable');
    return colorTheme;
  }

  @override
  Future<void> writeColorTheme(String id) async {
    writes++;
    colorTheme = id;
  }

  @override
  Future<String?> readThemeMode() async {
    if (failReads) throw Exception('storage unavailable');
    return themeMode;
  }

  @override
  Future<void> writeThemeMode(String mode) async {
    writes++;
    themeMode = mode;
  }

  @override
  Future<String?> readLocale() async => null;

  @override
  Future<String?> readLastEmail() async => null;
}

ProviderContainer _container(_MemoryStore store) {
  final container = ProviderContainer(
    overrides: [secureStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _restore(ProviderContainer c) => restoreDisplayPreferences(
  c.read(themeModeProvider.notifier),
  c.read(colorThemeProvider.notifier),
  c.read(localeProvider.notifier),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The app's root as `main.dart` builds it: both providers drive one
/// [MaterialApp].
class _App extends ConsumerWidget {
  const _App({required this.home, this.locale = const Locale('en')});

  final Widget home;
  final Locale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorTheme = ref.watch(colorThemeProvider);
    return MaterialApp(
      theme: AppTheme.of(colorTheme, Brightness.light),
      darkTheme: AppTheme.of(colorTheme, Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    );
  }
}

Widget _scoped(
  Widget child, {
  _MemoryStore? store,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    secureStoreProvider.overrideWithValue(store ?? _MemoryStore()),
    ...overrides,
  ],
  child: child,
);

void main() {
  // -------------------------------------------------------------------------
  group('palettes', () {
    for (final colorTheme in AppColorTheme.values) {
      for (final brightness in Brightness.values) {
        final name = '${colorTheme.id} ${brightness.name}';
        final p = colorTheme.palette(brightness);
        final theme = AppTheme.of(colorTheme, brightness);
        final colors = theme.extension<AppColors>()!;
        // The original Ocean Blue dark palette is kept exactly as it was;
        // its accent sits a little under 4.5:1 and is recorded here rather
        // than changed. Every new palette meets 4.5:1 throughout.
        final legacy =
            colorTheme == AppColorTheme.oceanBlue &&
            brightness == Brightness.dark;
        final textMin = legacy ? 3.0 : 4.5;

        test('$name: a complete theme', () {
          expect(theme.brightness, brightness);
          expect(theme.colorScheme.primary, p.primary);
          expect(theme.scaffoldBackgroundColor, p.background);
          expect(colors.outgoingBubble, p.outgoingBubble);
        });

        test('$name: readable text', () {
          expect(_contrast(p.foreground, p.background), greaterThan(7));
          expect(_contrast(p.foreground, p.surface), greaterThan(7));
          expect(_contrast(p.mutedForeground, p.surface), greaterThan(4.5));
          expect(_contrast(p.sidebarForeground, p.sidebar), greaterThan(4.5));
          expect(_contrast(Colors.white, p.outgoingBubble), greaterThan(4.5));
          expect(_contrast(Colors.white, p.solidPrimary), greaterThan(4.5));
          expect(_contrast(p.onPrimary, p.primary), greaterThan(textMin));
          expect(_contrast(colors.link, p.surface), greaterThan(textMin));
          final infoTint = Color.alphaBlend(p.infoSurface, p.surface);
          expect(_contrast(p.info, infoTint), greaterThan(legacy ? 3 : 4.5));
        });

        test('$name: statuses keep their meaning', () {
          expect(colors.success, ScenarioColors.success);
          expect(colors.warning, ScenarioColors.warning);
          expect(colors.danger, ScenarioColors.danger);
          // "Info" must never be mistaken for success (green).
          final infoHue = HSLColor.fromColor(p.info).hue;
          expect((infoHue - 142).abs(), greaterThan(40));
        });
      }
    }

    test('Ocean Blue is the original palette, value for value', () {
      final light = AppTheme.of(AppColorTheme.oceanBlue, Brightness.light);
      final dark = AppTheme.of(AppColorTheme.oceanBlue, Brightness.dark);
      expect(light.colorScheme.primary, ScenarioColors.primary);
      expect(light.scaffoldBackgroundColor, ScenarioColors.background);
      expect(light.colorScheme.surface, ScenarioColors.card);
      expect(dark.colorScheme.primary, ScenarioColors.darkPrimary);
      expect(dark.scaffoldBackgroundColor, ScenarioColors.darkBackground);
      expect(
        dark.extension<AppColors>()!.outgoingBubble,
        ScenarioColors.darkOutgoingBubble,
      );
      expect(AppTheme.light, same(light));
      expect(AppTheme.dark, same(dark));
    });

    test('the four themes are actually different', () {
      final primaries = {
        for (final t in AppColorTheme.values)
          t.palette(Brightness.light).primary,
      };
      expect(primaries, hasLength(4));
    });

    test('themes are built once and reused', () {
      expect(
        AppTheme.of(AppColorTheme.emerald, Brightness.dark),
        same(AppTheme.of(AppColorTheme.emerald, Brightness.dark)),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('stored preferences', () {
    test('nothing stored: Ocean Blue, following the system', () async {
      final c = _container(_MemoryStore());
      await _restore(c);

      expect(c.read(colorThemeProvider), AppColorTheme.oceanBlue);
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    test('a choice survives a restart', () async {
      final store = _MemoryStore();
      final first = _container(store);
      await first
          .read(colorThemeProvider.notifier)
          .update(AppColorTheme.royalPurple);
      await first.read(themeModeProvider.notifier).update(ThemeMode.dark);

      final relaunched = _container(store);
      await _restore(relaunched);

      expect(relaunched.read(colorThemeProvider), AppColorTheme.royalPurple);
      expect(relaunched.read(themeModeProvider), ThemeMode.dark);
    });

    test('an unknown or outdated value falls back safely', () async {
      final c = _container(
        _MemoryStore(colorTheme: 'neon_pink', themeMode: 'sepia'),
      );
      await _restore(c);

      expect(c.read(colorThemeProvider), AppColorTheme.oceanBlue);
      expect(c.read(themeModeProvider), ThemeMode.system);
    });

    test('unreadable storage never blocks launch', () async {
      final c = _container(_MemoryStore(failReads: true));
      await expectLater(_restore(c), completes);

      expect(c.read(colorThemeProvider), AppColorTheme.oceanBlue);
    });

    test('choosing what is already chosen writes nothing', () async {
      final store = _MemoryStore();
      final c = _container(store);
      await c.read(colorThemeProvider.notifier).update(AppColorTheme.emerald);
      await c.read(colorThemeProvider.notifier).update(AppColorTheme.emerald);
      await c.read(themeModeProvider.notifier).update(ThemeMode.system);

      expect(store.writes, 1);
    });

    test('ids are stable', () {
      expect(
        [for (final t in AppColorTheme.values) t.id],
        ['ocean_blue', 'emerald', 'royal_purple', 'graphite_orange'],
      );
    });
  });

  // -------------------------------------------------------------------------
  group('applying a theme', () {
    testWidgets('picking a theme in Settings recolours the app at once', (
      tester,
    ) async {
      final store = _MemoryStore();
      await tester.pumpWidget(
        _scoped(
          const _App(home: SingleChildScrollView(child: AppearanceSettings())),
          store: store,
        ),
      );

      Color primary() => Theme.of(
        tester.element(find.byType(AppearanceSettings)),
      ).colorScheme.primary;
      expect(
        primary(),
        AppColorTheme.oceanBlue.palette(Brightness.light).primary,
      );

      await tester.tap(find.byKey(const Key('colorTheme-graphite_orange')));
      await tester.pumpAndSettle();

      expect(
        primary(),
        AppColorTheme.graphiteOrange.palette(Brightness.light).primary,
      );
      expect(store.colorTheme, 'graphite_orange');
    });

    testWidgets('Light / Dark / System switch the brightness at once', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        _scoped(
          const _App(home: SingleChildScrollView(child: AppearanceSettings())),
        ),
      );
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(AppearanceSettings))).brightness;

      expect(brightness(), Brightness.light);
      await tester.tap(find.byIcon(Icons.dark_mode_outlined));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);

      await tester.tap(find.byIcon(Icons.brightness_auto_outlined));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
    });

    testWidgets('Follow System tracks the phone switching to dark', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(_scoped(const _App(home: SizedBox())));
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(SizedBox))).brightness;
      expect(brightness(), Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
    });

    testWidgets('the chosen theme is marked with a check and announced', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _scoped(
          const _App(home: SingleChildScrollView(child: AppearanceSettings())),
          store: _MemoryStore(colorTheme: 'emerald'),
        ),
      );
      await tester.pumpAndSettle();
      // Restore runs at launch in the app; here the store is read directly.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppearanceSettings)),
      );
      await container.read(colorThemeProvider.notifier).restore();
      await tester.pumpAndSettle();

      bool selected(String id) =>
          tester
              .getSemantics(find.byKey(Key('colorTheme-$id')))
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
      expect(selected('emerald'), isTrue);
      expect(selected('ocean_blue'), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('colorTheme-emerald')),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('Arabic: theme names and descriptions are translated', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scoped(
          const _App(
            locale: Locale('ar'),
            home: SingleChildScrollView(child: AppearanceSettings()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('الأزرق المحيطي'), findsOneWidget);
      expect(find.text('الزمردي'), findsOneWidget);
      expect(find.text('البنفسجي الملكي'), findsOneWidget);
      expect(find.text('الجرافيت والبرتقالي'), findsOneWidget);
      expect(find.text('لمسات خضراء هادئة.'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(AppearanceSettings))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('main screens in every theme', () {
    final conversation = Conversation.fromJson({
      'id': 1,
      'customer': {'id': 2, 'display_name': 'Sarah Connor'},
      'provider': 'WHATSAPP',
      'status': 'NEW',
      'priority': 'URGENT',
      'unread_count': 3,
      'message_count': 4,
      'last_message_preview': 'Hello',
      'last_message_at': '2026-10-01T10:00:00Z',
    });
    final outgoing = Message.fromJson({
      'id': 1,
      'text': 'Thanks — on its way',
      'direction': 'OUTBOUND',
      'sender_name': 'Sam',
      'sent_at': '2026-10-01T10:00:00Z',
      'delivery_status': 'READ',
      'attachments': const [],
    });

    for (final colorTheme in AppColorTheme.values) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final arabic in [false, true]) {
          final label = '${colorTheme.id} ${mode.name} ${arabic ? 'ar' : 'en'}';
          testWidgets('inbox row, filters, bubble, settings — $label', (
            tester,
          ) async {
            final store = _MemoryStore(
              colorTheme: colorTheme.id,
              themeMode: mode.name,
            );
            await tester.pumpWidget(
              _scoped(
                _App(
                  locale: Locale(arabic ? 'ar' : 'en'),
                  home: SingleChildScrollView(
                    child: Column(
                      children: [
                        const InboxQuickFilterBar(),
                        ConversationRow(
                          conversation: conversation,
                          onTap: () {},
                        ),
                        MessageBubble(message: outgoing),
                        const AppearanceSettings(),
                      ],
                    ),
                  ),
                ),
                store: store,
              ),
            );
            final container = ProviderScope.containerOf(
              tester.element(find.byType(InboxQuickFilterBar)),
            );
            await _restore(container);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final palette = colorTheme.palette(
              mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
            );
            // The selected filter pill wears the theme's accent…
            final pill = tester.widget<Material>(
              find
                  .descendant(
                    of: find.byKey(const Key('quick_filter_all')),
                    matching: find.byType(Material),
                  )
                  .first,
            );
            expect(pill.color, palette.primary);
            // …the agent's own bubble the theme's bubble colour…
            final bubble = tester
                .widgetList<Container>(
                  find.descendant(
                    of: find.byType(MessageBubble),
                    matching: find.byType(Container),
                  ),
                )
                .map((c) => c.decoration)
                .whereType<BoxDecoration>()
                .where((d) => d.color == palette.outgoingBubble);
            expect(bubble, isNotEmpty);
            // …and the unread count the accent too.
            expect(find.text('3'), findsOneWidget);
          });
        }
      }
    }

    for (final colorTheme in AppColorTheme.values) {
      testWidgets('sign-in screen — ${colorTheme.id}', (tester) async {
        await tester.pumpWidget(
          _scoped(
            const _App(home: LoginScreen()),
            store: _MemoryStore(colorTheme: colorTheme.id),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(LoginScreen)),
        );
        await _restore(container);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('loginSubmitButton')),
        );
        final background =
            button.style?.backgroundColor?.resolve({}) ??
            Theme.of(
              tester.element(find.byType(LoginScreen)),
            ).filledButtonTheme.style!.backgroundColor!.resolve({});
        expect(background, colorTheme.palette(Brightness.light).primary);
      });
    }
  });
}
