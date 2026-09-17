import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/core/utils/attachment_helper.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getTemporaryPath() async => directory.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;

  @override
  Future<String?> getDownloadsPath() async => directory.path;
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requested.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final openFileCalls = <({String path, String? type})>[];
  var mockOpenResult = OpenResult(type: ResultType.done, message: 'done');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('attachment_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    openFileCalls.clear();
    mockOpenResult = OpenResult(type: ResultType.done, message: 'done');

    AttachmentHelper.openFileRunner = (filePath, {type}) async {
      openFileCalls.add((path: filePath, type: type));
      return mockOpenResult;
    };
  });

  tearDown(() async {
    AttachmentHelper.openFileRunner = OpenFilex.open;
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('MessageAttachment and Message JSON parsing', () {
    test('detects type from MIME type when type is missing or generic', () {
      final img = MessageAttachment.fromJson({
        'mime_type': 'image/png',
        'file_name': 'photo',
      });
      expect(img.isImage, isTrue);
      expect(img.fileExtension, 'png');

      final audio = MessageAttachment.fromJson({
        'content_type': 'audio/ogg',
        'name': 'voice',
      });
      expect(audio.isAudio, isTrue);
      expect(audio.fileExtension, 'ogg');

      final video = MessageAttachment.fromJson({
        'mimeType': 'video/mp4',
        'url': 'https://example.com/video.mp4',
      });
      expect(video.isVideo, isTrue);

      final pdf = MessageAttachment.fromJson({
        'mime_type': 'application/pdf',
        'fileName': 'statement.pdf',
      });
      expect(pdf.type, 'FILE');
      expect(pdf.fileExtension, 'pdf');
    });

    test('broadens key parsing for id, name, size, and url', () {
      final att = MessageAttachment.fromJson({
        'id': 'att_123',
        'name': 'document.docx',
        'size': 2048,
        'contentType':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'download_url': '/api/attachments/att_123/download/',
      });
      expect(att.attachmentId, 'att_123');
      expect(att.fileName, 'document.docx');
      expect(att.sizeBytes, 2048);
      expect(att.url, '/api/attachments/att_123/download/');
      expect(att.formattedSize, '2.0 KB');
    });

    test(
      'Message.fromJson synthesizes attachments from media markers and strips raw text',
      () {
        final msg = Message.fromJson({
          'id': 100,
          'channel_id': 1,
          'direction': 'INBOUND',
          'text':
              'Please check this receipt: [[media:IMAGE]] and this agreement: [[media:FILE]]',
          'sent_at': '2026-09-16T10:00:00Z',
        });

        expect(msg.attachments.length, 2);
        expect(msg.attachments[0].type, 'IMAGE');
        expect(msg.attachments[1].type, 'FILE');
        expect(msg.text, 'Please check this receipt: and this agreement:');
        expect(msg.text.contains('[[media:'), isFalse);
      },
    );
  });

  group('AttachmentHelper caching, download, and auto-open', () {
    test('suggestFileName derives clean filenames for different types', () {
      final img = const MessageAttachment(
        attachmentId: 'img1',
        type: 'IMAGE',
        mimeType: 'image/jpeg',
      );
      expect(AttachmentHelper.suggestFileName(img), 'photoimg1.jpg');

      final audio = const MessageAttachment(
        attachmentId: 'aud1',
        type: 'AUDIO',
        mimeType: 'audio/m4a',
      );
      expect(AttachmentHelper.suggestFileName(audio), 'voice_noteaud1.m4a');

      final doc = const MessageAttachment(
        attachmentId: 'doc1',
        type: 'FILE',
        mimeType: 'application/pdf',
      );
      expect(AttachmentHelper.suggestFileName(doc), 'documentdoc1.pdf');

      final named = const MessageAttachment(
        attachmentId: 'doc2',
        type: 'FILE',
        fileName: 'contract_signed.pdf',
      );
      expect(AttachmentHelper.suggestFileName(named), 'contract_signed.pdf');
    });

    test(
      'getUniqueFilePath avoids collisions by appending counter in parentheses',
      () {
        final base = 'report.pdf';
        final path1 = AttachmentHelper.getUniqueFilePath(tempDir, base);
        expect(path1.endsWith('report.pdf'), isTrue);
        File(path1).writeAsStringSync('one');

        final path2 = AttachmentHelper.getUniqueFilePath(tempDir, base);
        expect(path2.endsWith('report (1).pdf'), isTrue);
        File(path2).writeAsStringSync('two');

        final path3 = AttachmentHelper.getUniqueFilePath(tempDir, base);
        expect(path3.endsWith('report (2).pdf'), isTrue);
      },
    );

    test('resolveMimeType maps file extensions to correct MIME types', () {
      final pdfAtt = const MessageAttachment(type: 'FILE');
      expect(
        AttachmentHelper.resolveMimeType(pdfAtt, '/path/to/file.pdf'),
        'application/pdf',
      );

      final docxAtt = const MessageAttachment(type: 'FILE');
      expect(
        AttachmentHelper.resolveMimeType(docxAtt, '/path/to/file.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );

      final xlsxAtt = const MessageAttachment(type: 'FILE');
      expect(
        AttachmentHelper.resolveMimeType(xlsxAtt, '/path/to/file.xlsx'),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      final customAtt = const MessageAttachment(
        type: 'FILE',
        mimeType: 'application/x-custom',
      );
      expect(
        AttachmentHelper.resolveMimeType(customAtt, '/path/to/file.bin'),
        'application/x-custom',
      );
    });

    testWidgets('PDF download then automatic open in default viewer', (
      tester,
    ) async {
      final pdfBytes = [0x25, 0x50, 0x44, 0x46]; // '%PDF'
      final adapter = _StubAdapter((options) {
        return ResponseBody.fromBytes(
          Uint8List.fromList(pdfBytes),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/pdf'],
          },
        );
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final att = const MessageAttachment(
        attachmentId: 'pdf_42',
        type: 'FILE',
        fileName: 'annual_report.pdf',
        mimeType: 'application/pdf',
        url: '/api/attachments/pdf_42/content/',
      );

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
        await AttachmentHelper.openAttachment(
          context: context,
          attachment: att,
          api: client,
        );
      });
      await tester.pumpAndSettle();

      // Downloaded from network
      expect(adapter.requested, hasLength(1));

      // Automatically invoked openFileRunner with file path and PDF MIME type
      expect(openFileCalls, hasLength(1));
      final call = openFileCalls.first;
      expect(call.path.endsWith('annual_report.pdf'), isTrue);
      expect(File(call.path).existsSync(), isTrue);
      expect(File(call.path).readAsBytesSync(), pdfBytes);
      expect(call.type, 'application/pdf');
    });

    testWidgets(
      'Already-downloaded file opens directly without downloading again',
      (tester) async {
        final docBytes = [10, 20, 30, 40];
        final adapter = _StubAdapter((options) {
          return ResponseBody.fromBytes(
            Uint8List.fromList(docBytes),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/pdf'],
            },
          );
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final att = const MessageAttachment(
          attachmentId: 'cached_doc_1',
          type: 'FILE',
          fileName: 'cached_contract.pdf',
          mimeType: 'application/pdf',
          url: '/api/attachments/cached_doc_1/content/',
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SizedBox()),
          ),
        );
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold));

        // First tap: downloads and opens
        await tester.runAsync(() async {
          await AttachmentHelper.openAttachment(
            context: context,
            attachment: att,
            api: client,
          );
        });
        await tester.pumpAndSettle();

        expect(adapter.requested, hasLength(1));
        expect(openFileCalls, hasLength(1));

        // Second tap: already downloaded, opens directly without network request
        await tester.runAsync(() async {
          await AttachmentHelper.openAttachment(
            context: context,
            attachment: att,
            api: client,
          );
        });
        await tester.pumpAndSettle();

        // Still only 1 network request made!
        expect(adapter.requested, hasLength(1));
        // But openFileRunner was called a second time
        expect(openFileCalls, hasLength(2));
      },
    );

    testWidgets('Download failure shows user-visible error message', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({'error': 'Server error'}),
          500,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final att = const MessageAttachment(
        attachmentId: 'failed_att',
        type: 'FILE',
        fileName: 'missing.pdf',
        url: '/api/attachments/failed_att/content/',
      );

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
        await AttachmentHelper.openAttachment(
          context: context,
          attachment: att,
          api: client,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // openFileRunner was NOT called
      expect(openFileCalls, isEmpty);

      // Localized download error message is shown
      expect(
        find.text("Couldn't download attachment. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets(
      'Unsupported/no-handler file type shows clear message to user',
      (tester) async {
        mockOpenResult = OpenResult(
          type: ResultType.noAppToOpen,
          message: 'No app to open',
        );

        final adapter = _StubAdapter((options) {
          return ResponseBody.fromBytes(
            Uint8List.fromList([1, 2, 3]),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/x-unknown-data'],
            },
          );
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final att = const MessageAttachment(
          attachmentId: 'unknown_type_att',
          type: 'FILE',
          fileName: 'custom_data.xyz',
          url: '/api/attachments/unknown_type_att/content/',
        );

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
          await AttachmentHelper.openAttachment(
            context: context,
            attachment: att,
            api: client,
          );
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(openFileCalls, hasLength(1));
        // Clear message is shown instead of silent failure
        expect(
          find.text('No application found to open this file.'),
          findsOneWidget,
        );
      },
    );
  });

  group('MessageBubble attachment UI and state', () {
    testWidgets('shows loading spinner while downloading and then completes', (
      tester,
    ) async {
      final completer = Completer<ResponseBody>();
      final adapter = _StubAdapter((options) => completer.future);
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final msg = Message(
        id: 1,
        direction: 'INBOUND',
        senderType: 'CUSTOMER',
        senderName: 'Customer',
        messageType: 'TEXT',
        deliveryStatus: 'DELIVERED',
        text: '',
        sentAt: DateTime.parse('2026-09-16T10:00:00Z'),
        attachments: const [
          MessageAttachment(
            attachmentId: 'loading_doc',
            type: 'FILE',
            fileName: 'blueprint.pdf',
            sizeBytes: 2048,
            url: '/api/attachments/loading_doc/content/',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: MessageBubble(message: msg)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows download icon and open icon, no spinner
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);

      // Tap the chip to start download
      await tester.tap(find.text('blueprint.pdf'));
      await tester.pump();

      // Progress spinner is visible while download is in flight
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the download
      await tester.runAsync(() async {
        completer.complete(
          ResponseBody.fromBytes(
            Uint8List.fromList([37, 80, 68, 70]),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/pdf'],
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Spinner is gone, openFileRunner was invoked
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(openFileCalls, hasLength(1));
    });

    testWidgets(
      'existing image attachment preview and full-screen viewer remain unchanged',
      (tester) async {
        final msg = Message(
          id: 10,
          direction: 'INBOUND',
          senderType: 'CUSTOMER',
          senderName: 'Customer',
          messageType: 'IMAGE',
          deliveryStatus: 'DELIVERED',
          text: '',
          sentAt: DateTime.parse('2026-09-16T10:00:00Z'),
          attachments: const [
            MessageAttachment(
              attachmentId: 'img_test',
              type: 'IMAGE',
              fileName: 'photo.jpg',
              mimeType: 'image/jpeg',
              url: 'https://cdn.example.com/photo.jpg',
            ),
          ],
        );

        final client = ApiClient.create(cookieJar: CookieJar());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(client)],
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ListView(children: [MessageBubble(message: msg)]),
              ),
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byType(CachedNetworkImage), findsOneWidget);

        // Tapping image opens full-screen image viewer screen
        await tester.tap(find.byType(CachedNetworkImage).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'existing voice note attachment playback controls remain unchanged',
      (tester) async {
        final msg = Message(
          id: 11,
          direction: 'INBOUND',
          senderType: 'CUSTOMER',
          senderName: 'Customer',
          messageType: 'AUDIO',
          deliveryStatus: 'DELIVERED',
          text: '',
          sentAt: DateTime.parse('2026-09-16T10:10:00Z'),
          attachments: const [
            MessageAttachment(
              attachmentId: 'voice_test',
              type: 'AUDIO',
              durationMs: 35000,
              url: '/api/attachments/voice_test/content/',
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: MessageBubble(message: msg)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Voice note'), findsOneWidget);
        expect(find.text('0:35'), findsOneWidget);
        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      },
    );
  });
}
