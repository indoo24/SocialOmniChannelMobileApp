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

  group('Regression: WhatsApp image-as-document and attachment handling', () {
    // 1. Normal PDF document → downloads and opens.
    testWidgets('1. Normal PDF document downloads and opens', (tester) async {
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

      final att = MessageAttachment.fromJson({
        'id': 'pdf_doc_1',
        'type': 'FILE',
        'file_name': 'document.pdf',
        'mime_type': 'application/pdf',
        'content_url': '/api/attachments/pdf_doc_1/content/',
        'status': 'READY',
      });

      expect(att.isDocument, isTrue);
      expect(att.isImage, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final context = tester.element(find.byType(Scaffold));

      await tester.runAsync(() async {
        await AttachmentHelper.openAttachment(
          context: context,
          attachment: att,
          api: client,
        );
      });

      expect(adapter.requested, hasLength(1));
      expect(openFileCalls, hasLength(1));
      expect(openFileCalls.first.type, 'application/pdf');
      expect(openFileCalls.first.path.endsWith('document.pdf'), isTrue);
    });

    // 2. `document` with MIME `image/jpeg` → downloads and opens.
    testWidgets(
      '2. WhatsApp document with MIME image/jpeg downloads and opens',
      (tester) async {
        final jpegBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
        final adapter = _StubAdapter((options) {
          return ResponseBody.fromBytes(
            Uint8List.fromList(jpegBytes),
            200,
            headers: {
              Headers.contentTypeHeader: ['image/jpeg'],
            },
          );
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final att = MessageAttachment.fromJson({
          'id': 'wa_doc_jpeg',
          'type': 'FILE',
          'file_name': 'IMG-20260921-WA0010.jpg',
          'mime_type': 'image/jpeg',
          'content_url': '/api/attachments/wa_doc_jpeg/content/',
          'status': 'READY',
          'metadata': {'whatsapp_type': 'document'},
        });

        // Key classification assertions
        expect(att.isDocument, isTrue);
        expect(att.hasImageFile, isTrue);
        expect(att.fileExtension, 'jpg');

        final msg = Message(
          id: 201,
          direction: 'INBOUND',
          senderType: 'CUSTOMER',
          senderName: 'Customer',
          messageType: 'FILE',
          deliveryStatus: 'DELIVERED',
          text: '',
          sentAt: DateTime.parse('2026-09-22T10:00:00Z'),
          attachments: [att],
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

        // Must render as document chip, NOT inline image
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.text('IMG-20260921-WA0010.jpg'), findsOneWidget);
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);

        // Tap the chip to download & open
        await tester.tap(find.text('IMG-20260921-WA0010.jpg'));
        await tester.pump();

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(adapter.requested, hasLength(1));
        expect(openFileCalls, hasLength(1));
        expect(openFileCalls.first.type, 'image/jpeg');
        expect(openFileCalls.first.path.endsWith('.jpg'), isTrue);
        expect(File(openFileCalls.first.path).existsSync(), isTrue);
        expect(File(openFileCalls.first.path).readAsBytesSync(), jpegBytes);
      },
    );

    // 3. `document` with MIME `image/png` → downloads and opens.
    testWidgets(
      '3. WhatsApp document with MIME image/png downloads and opens',
      (tester) async {
        final pngBytes = [0x89, 0x50, 0x4E, 0x47];
        final adapter = _StubAdapter((options) {
          return ResponseBody.fromBytes(
            Uint8List.fromList(pngBytes),
            200,
            headers: {
              Headers.contentTypeHeader: ['image/png'],
            },
          );
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final att = MessageAttachment.fromJson({
          'id': 'wa_doc_png',
          'type': 'FILE',
          'file_name': 'screenshot.png',
          'mime_type': 'image/png',
          'content_url': '/api/attachments/wa_doc_png/content/',
          'status': 'READY',
          'metadata': {'whatsapp_type': 'document'},
        });

        expect(att.isDocument, isTrue);
        expect(att.hasImageFile, isTrue);

        final msg = Message(
          id: 202,
          direction: 'INBOUND',
          senderType: 'CUSTOMER',
          senderName: 'Customer',
          messageType: 'FILE',
          deliveryStatus: 'DELIVERED',
          text: '',
          sentAt: DateTime.parse('2026-09-22T10:00:00Z'),
          attachments: [att],
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

        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.text('screenshot.png'), findsOneWidget);

        await tester.tap(find.text('screenshot.png'));
        await tester.pump();

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(adapter.requested, hasLength(1));
        expect(openFileCalls, hasLength(1));
        expect(openFileCalls.first.type, 'image/png');
        expect(openFileCalls.first.path.endsWith('.png'), isTrue);
      },
    );

    // 4. Image sent normally as image → existing image preview behavior remains unchanged.
    testWidgets(
      '4. Image sent normally as image renders inline preview and opens full-screen',
      (tester) async {
        final att = MessageAttachment.fromJson({
          'id': 'normal_img',
          'type': 'IMAGE',
          'file_name': 'vacation.jpg',
          'mime_type': 'image/jpeg',
          'url': 'https://cdn.example.com/vacation.jpg',
          'status': 'READY',
        });

        expect(att.isDocument, isFalse);
        expect(att.isImage, isTrue);
        expect(att.isInlineImage, isTrue);

        final msg = Message(
          id: 203,
          direction: 'INBOUND',
          senderType: 'CUSTOMER',
          senderName: 'Customer',
          messageType: 'IMAGE',
          deliveryStatus: 'DELIVERED',
          text: '',
          sentAt: DateTime.parse('2026-09-22T10:00:00Z'),
          attachments: [att],
        );

        final client = ApiClient.create(cookieJar: CookieJar());
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
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byType(CachedNetworkImage), findsOneWidget);
        expect(find.text('vacation.jpg'), findsNothing);

        await tester.tap(find.byType(CachedNetworkImage).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(InteractiveViewer), findsOneWidget);
      },
    );

    // 5. Document without MIME type but image filename extension → graceful fallback.
    testWidgets(
      '5. Document without MIME type but image filename extension falls back gracefully',
      (tester) async {
        final jpegBytes = [0xFF, 0xD8, 0xFF];
        final adapter = _StubAdapter((options) {
          return ResponseBody.fromBytes(Uint8List.fromList(jpegBytes), 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        final att = MessageAttachment.fromJson({
          'id': 'no_mime_img',
          'type': 'FILE',
          'file_name': 'untyped_photo.jpeg',
          'mime_type': '',
          'content_url': '/api/attachments/no_mime_img/content/',
        });

        expect(att.fileExtension, 'jpeg');
        expect(att.hasImageFile, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SizedBox()),
          ),
        );
        final context = tester.element(find.byType(Scaffold));

        await tester.runAsync(() async {
          await AttachmentHelper.openAttachment(
            context: context,
            attachment: att,
            api: client,
          );
        });

        expect(adapter.requested, hasLength(1));
        expect(openFileCalls, hasLength(1));
        expect(openFileCalls.first.type, 'image/jpeg');
        expect(openFileCalls.first.path.endsWith('.jpeg'), isTrue);
      },
    );

    // 6. Missing/invalid attachment URL → graceful error.
    testWidgets('6. Missing/invalid attachment URL results in graceful error', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({
            'error': {
              'code': 'not_ready',
              'message': 'This attachment is not available.',
              'details': {'status': 'UNAVAILABLE'},
            },
          }),
          409,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final att = MessageAttachment.fromJson({
        'id': 'unavailable_att',
        'type': 'FILE',
        'file_name': 'missing_file.jpg',
        'status': 'UNAVAILABLE',
        'content_url': '/api/attachments/unavailable_att/content/',
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final context = tester.element(find.byType(Scaffold));

      await tester.runAsync(() async {
        await AttachmentHelper.openAttachment(
          context: context,
          attachment: att,
          api: client,
          messageId: 86109,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(openFileCalls, isEmpty);
      expect(
        find.text("Couldn't download attachment. Please try again."),
        findsOneWidget,
      );
    });

    // 7. Authenticated attachment download still sends the required credentials.
    testWidgets('7. Authenticated download sends session cookies', (
      tester,
    ) async {
      final cookieJar = CookieJar();
      await cookieJar.saveFromResponse(
        Uri.parse('https://scenariomnchnl.tech'),
        [Cookie('scenario_session', 'session_auth_token_xyz')],
      );

      final adapter = _StubAdapter((options) {
        return ResponseBody.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/pdf'],
          },
        );
      });
      final client = ApiClient.create(cookieJar: cookieJar);
      client.raw.httpClientAdapter = adapter;

      final att = MessageAttachment.fromJson({
        'id': 'auth_test_att',
        'type': 'FILE',
        'file_name': 'secure.pdf',
        'content_url': '/api/attachments/auth_test_att/content/',
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final context = tester.element(find.byType(Scaffold));

      await tester.runAsync(() async {
        await AttachmentHelper.openAttachment(
          context: context,
          attachment: att,
          api: client,
        );
      });

      expect(adapter.requested, hasLength(1));
      final request = adapter.requested.first;
      expect(
        request.headers['cookie'] ?? request.headers['Cookie'],
        contains('scenario_session=session_auth_token_xyz'),
      );
    });

    // 8. Existing PDF/document behavior remains unchanged.
    testWidgets('8. Existing Word/Excel/PDF documents remain unchanged', (
      tester,
    ) async {
      final docxBytes = [0x50, 0x4B, 0x03, 0x04];
      final adapter = _StubAdapter((options) {
        return ResponseBody.fromBytes(
          Uint8List.fromList(docxBytes),
          200,
          headers: {
            Headers.contentTypeHeader: [
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            ],
          },
        );
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      final att = MessageAttachment.fromJson({
        'id': 'doc_docx_1',
        'type': 'FILE',
        'file_name': 'agreement.docx',
        'mime_type':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'content_url': '/api/attachments/doc_docx_1/content/',
      });

      expect(att.isDocument, isTrue);
      expect(att.hasImageFile, isFalse);
      expect(att.isImage, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final context = tester.element(find.byType(Scaffold));

      await tester.runAsync(() async {
        await AttachmentHelper.openAttachment(
          context: context,
          attachment: att,
          api: client,
        );
      });

      expect(adapter.requested, hasLength(1));
      expect(openFileCalls, hasLength(1));
      expect(
        openFileCalls.first.type,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(openFileCalls.first.path.endsWith('.docx'), isTrue);
    });
  });
}
