import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scenario_mobile/core/utils/csv_export.dart';
import 'package:scenario_mobile/core/widgets/export_csv_action.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getTemporaryPath() async => directory.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;

  @override
  Future<String?> getDownloadsPath() async => directory.path;
}

class _FakeSharePlatform extends SharePlatform {
  final List<ShareParams> shared = [];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeSharePlatform fakeShare;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('csv_download_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    fakeShare = _FakeSharePlatform();
    SharePlatform.instance = fakeShare;
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('CSV Export Download to Storage', () {
    testWidgets(
      'saves CSV to accessible directory with date-based name and shows Open snackbar',
      (tester) async {
        final now = DateTime.now();
        final dateStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final expectedFileName = 'conversations_$dateStr.csv';

        File? exportedFile;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SizedBox()),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold));

        await tester.runAsync(() async {
          exportedFile = await exportCsvAndShare(
            context,
            fileNamePrefix: 'conversations',
            fetch: () async => [65, 66, 67], // 'ABC'
            share: false,
          );
        });
        await tester.pumpAndSettle();

        expect(exportedFile, isNotNull);
        expect(exportedFile!.existsSync(), isTrue);
        expect(exportedFile!.path.endsWith(expectedFileName), isTrue);
        expect(exportedFile!.readAsStringSync(), 'ABC');

        // Success SnackBar is shown with "Open" action
        expect(find.text('CSV exported successfully'), findsOneWidget);
        expect(find.text('Open'), findsOneWidget);

        // Sharing was not triggered since share was false
        expect(fakeShare.shared, isEmpty);
      },
    );

    testWidgets('avoids filename collision by appending (1), (2)', (
      tester,
    ) async {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      File? file1;
      File? file2;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));

      await tester.runAsync(() async {
        file1 = await exportCsvAndShare(
          context,
          fileNamePrefix: 'customers',
          fetch: () async => [49], // '1'
          share: false,
        );

        file2 = await exportCsvAndShare(
          context,
          fileNamePrefix: 'customers',
          fetch: () async => [50], // '2'
          share: false,
        );
      });
      await tester.pumpAndSettle();

      expect(file1, isNotNull);
      expect(file2, isNotNull);
      expect(file1!.path.endsWith('customers_$dateStr.csv'), isTrue);
      expect(file2!.path.endsWith('customers_$dateStr (1).csv'), isTrue);
      expect(file1!.readAsStringSync(), '1');
      expect(file2!.readAsStringSync(), '2');
    });

    testWidgets(
      'ExportCsvAction menu contains primary export and secondary share items',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  ExportCsvAction(
                    fileNamePrefix: 'test',
                    fetch: () async => [1, 2, 3],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('export-csv-menu')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('export-csv-item')), findsOneWidget);
        expect(find.byKey(const Key('share-csv-item')), findsOneWidget);
        expect(find.text('Export CSV'), findsOneWidget);
        expect(find.text('Share CSV'), findsOneWidget);
      },
    );
  });
}
