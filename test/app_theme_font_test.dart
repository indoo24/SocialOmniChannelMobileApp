import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

void main() {
  group('AppTheme uses Cairo as the global font', () {
    // ThemeData.fontFamily is constructor-only: it is folded into the
    // resulting textTheme via TextTheme.apply(), which is where it is
    // actually observable afterwards.
    test('light theme textTheme resolves to Cairo', () {
      final textTheme = AppTheme.light.textTheme;
      expect(textTheme.titleLarge?.fontFamily, equals('Cairo'));
      expect(textTheme.bodyMedium?.fontFamily, equals('Cairo'));
      expect(textTheme.labelSmall?.fontFamily, equals('Cairo'));
    });

    test('dark theme textTheme resolves to Cairo', () {
      final textTheme = AppTheme.dark.textTheme;
      expect(textTheme.titleLarge?.fontFamily, equals('Cairo'));
      expect(textTheme.bodyMedium?.fontFamily, equals('Cairo'));
      expect(textTheme.labelSmall?.fontFamily, equals('Cairo'));
    });

    test('existing typography sizes and weights are unchanged', () {
      final textTheme = AppTheme.light.textTheme;
      expect(textTheme.titleLarge?.fontSize, equals(20));
      expect(textTheme.titleLarge?.fontWeight, equals(FontWeight.w600));
      expect(textTheme.titleLarge?.letterSpacing, equals(-0.3));
      expect(textTheme.titleMedium?.fontSize, equals(15));
      expect(textTheme.titleMedium?.fontWeight, equals(FontWeight.w600));
      expect(textTheme.bodyLarge?.fontSize, equals(15));
      expect(textTheme.bodyMedium?.fontSize, equals(14));
      expect(textTheme.bodySmall?.fontSize, equals(12));
      expect(textTheme.labelSmall?.fontSize, equals(11));
      expect(textTheme.labelSmall?.fontWeight, equals(FontWeight.w500));
    });

    test('AppBar title style is unaffected in size/weight', () {
      final appBarTextStyle = AppTheme.light.appBarTheme.titleTextStyle;
      expect(appBarTextStyle?.fontSize, equals(17));
      expect(appBarTextStyle?.fontWeight, equals(FontWeight.w600));
    });
  });

  group('Cairo renders Arabic and English text without error', () {
    testWidgets('English text renders under the Cairo-themed app', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('Hello, Scenario 123!')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello, Scenario 123!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic text renders under the Cairo-themed app in RTL', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('مرحباً بكم في سيناريو')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('مرحباً بكم في سيناريو'), findsOneWidget);
      final directionality = Directionality.of(
        tester.element(find.text('مرحباً بكم في سيناريو')),
      );
      expect(directionality, equals(TextDirection.rtl));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mixed Arabic/English/numeric text renders without error', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('طلب #123 - Order Confirmed!')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('طلب #123 - Order Confirmed!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme renders Arabic text without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('اختبار الوضع الداكن')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('اختبار الوضع الداكن'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
