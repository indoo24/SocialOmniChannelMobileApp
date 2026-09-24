/// Regression tests for the composer's Document option accepting any file:
///
///  1. The document picker asks for arbitrary file types.
///  2–6. PDF, DOCX, XLSX, TXT and ZIP upload with their real MIME type.
///  7. An image picked through Document keeps its real image MIME type.
///  8. The original filename (and size) is preserved.
///  9. The gallery picker is unaffected.
/// 10. The upload → send flow is unaffected.
/// Plus: an unknown extension is sent as-is, not renamed, and a backend
/// rejection's reason reaches the agent.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/composer_attachment.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

base class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile({required this.name, required String filePath})
    : uri = Uri.file(filePath),
      _file = File(filePath);

  @override
  final String name;

  @override
  final Uri uri;

  final File _file;

  @override
  XFile get xFile => XFile(path!, name: name);

  @override
  int? lengthSync() => _file.lengthSync();

  @override
  Future<int?> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => const Stream.empty();
}

class _FakeFilePicker extends FilePickerPlatform {
  _FakeFilePicker(this.files);

  final List<PlatformFile> files;
  int calls = 0;
  FileType? lastType;
  List<String>? lastAllowedExtensions;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    return files;
  }
}

class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.paths);

  final List<String> paths;
  int multiCalls = 0;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multiCalls++;
    return paths.map(XFile.new).toList();
  }
}

/// One multipart file part, as the server received it.
typedef _Upload = ({String? fileName, String? mimeType, int length});

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.rejectUploadsWith});

  /// When set, every upload is refused with this `ApiError` body.
  final String? rejectUploadsWith;

  final List<RequestOptions> received = [];
  final List<_Upload> uploads = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    final path = options.path;
    if (options.method == 'POST' && path == '/conversations/42/attachments/') {
      final form = options.data as FormData;
      final part = form.files.single;
      expect(part.key, 'file');
      final mime = part.value.contentType?.mimeType;
      uploads.add((
        fileName: part.value.filename,
        mimeType: mime,
        length: part.value.length,
      ));
      if (rejectUploadsWith != null) return _json(rejectUploadsWith!, 400);
      final isImage = mime?.startsWith('image/') ?? false;
      return _json(
        jsonEncode({
          'id': 'draft-${uploads.length}',
          'type': isImage ? 'IMAGE' : 'FILE',
          'mime_type': mime,
          'file_name': part.value.filename,
          'size_bytes': part.value.length,
          'is_voice': false,
          'duration_ms': null,
          'expires_at': '2026-09-25T12:00:00Z',
        }),
        201,
      );
    }
    if (options.method == 'POST' && path == '/conversations/42/reply/') {
      return _json('''
{
  "id": 801, "direction": "OUTBOUND", "sender_type": "AGENT",
  "sender_name": "Sam Agent", "message_type": "FILE", "text": "",
  "attachments": [{"type": "FILE", "file_name": "report.xlsx",
    "mime_type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "size_bytes": 300}],
  "delivery_status": "SENT", "sent_at": "2026-09-25T12:00:00Z"
}''', 201);
    }
    if (path.contains('/messages/')) return _json('{"results": []}', 200);
    if (path.contains('/notes/')) return _json('[]', 200);
    if (path.contains('/conversations/42/')) {
      return _json(
        jsonEncode({
          'id': 42,
          'customer': {'id': 7, 'display_name': 'Sarah', 'initials': 'S'},
          'provider': 'WHATSAPP',
          'channel_name': 'Scenario Sales',
          'status': 'OPEN',
          'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
        }),
        200,
      );
    }
    return _json('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ApiClient _client(_StubAdapter adapter) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = adapter;
  return client;
}

Employee _employee() => const Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: {Perm.conversationReply},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

/// The attachment button alone, reporting what it staged or the error.
Future<void> _pumpButton(
  WidgetTester tester,
  _StubAdapter adapter, {
  required List<StagedAttachment> staged,
  List<String>? errors,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_client(adapter))],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: ComposerAttachmentButton(
              conversationId: 42,
              enabled: true,
              onStaged: staged.addAll,
              onError: (e) => errors?.add(e),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens the attachment sheet and picks [option], letting the upload's real
/// file I/O complete (it never resolves under plain `pump()`).
Future<void> _choose(WidgetTester tester, String option) async {
  await tester.tap(find.byIcon(Icons.attach_file_rounded));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.text(option));
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('document_picker_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// A real file on disk named [name] holding [size] bytes.
  _TestPlatformFile file(String name, {int size = 300}) {
    final f = File('${tempDir.path}/$name')
      ..writeAsBytesSync(List.filled(size, 7));
    return _TestPlatformFile(name: name, filePath: f.path);
  }

  testWidgets('1. Document asks the picker for any file type, unfiltered', (
    tester,
  ) async {
    final picker = _FakeFilePicker([file('anything.bin')]);
    FilePickerPlatform.instance = picker;
    final staged = <StagedAttachment>[];

    await _pumpButton(tester, _StubAdapter(), staged: staged);
    await _choose(tester, 'Document');

    expect(picker.calls, 1);
    expect(picker.lastType, FileType.any);
    expect(picker.lastAllowedExtensions, isNull);
  });

  const cases = {
    '2. PDF': ('quote.pdf', 'application/pdf'),
    '3. DOCX': (
      'contract.docx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ),
    '4. XLSX': (
      'report.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
    '5. TXT': ('notes.txt', 'text/plain'),
    '6. ZIP': ('bundle.zip', 'application/zip'),
    '7. Image through Document': ('photo.jpg', 'image/jpeg'),
  };

  for (final MapEntry(key: label, value: (name, mime)) in cases.entries) {
    testWidgets('$label uploads with its real MIME type and name', (
      tester,
    ) async {
      FilePickerPlatform.instance = _FakeFilePicker([file(name, size: 300)]);
      final adapter = _StubAdapter();
      final staged = <StagedAttachment>[];

      await _pumpButton(tester, adapter, staged: staged);
      await _choose(tester, 'Document');

      expect(adapter.uploads, [(fileName: name, mimeType: mime, length: 300)]);
      expect(staged.single.attachment.fileName, name);
      expect(staged.single.attachment.mimeType, mime);
      expect(staged.single.fileSize, 300);
    });
  }

  testWidgets('8. The original filename and size are preserved exactly', (
    tester,
  ) async {
    const name = 'عرض سعر 2026 (final v2).pdf';
    FilePickerPlatform.instance = _FakeFilePicker([file(name, size: 1234)]);
    final adapter = _StubAdapter();
    final staged = <StagedAttachment>[];

    await _pumpButton(tester, adapter, staged: staged);
    await _choose(tester, 'Document');

    expect(adapter.uploads.single.fileName, name);
    expect(adapter.uploads.single.length, 1234);
    expect(staged.single.attachment.fileName, name);
    expect(staged.single.fileSize, 1234);
  });

  testWidgets('an unknown extension is sent unrenamed as octet-stream', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([file('backup.qzx9')]);
    final adapter = _StubAdapter();
    final staged = <StagedAttachment>[];

    await _pumpButton(tester, adapter, staged: staged);
    await _choose(tester, 'Document');

    expect(adapter.uploads.single.fileName, 'backup.qzx9');
    expect(adapter.uploads.single.mimeType, 'application/octet-stream');
    expect(staged, hasLength(1));
  });

  testWidgets("the backend's rejection reason reaches the agent", (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([file('setup.apk')]);
    final adapter = _StubAdapter(
      rejectUploadsWith:
          '{"error": {"code": "unsupported_media_type", '
          '"message": "WhatsApp does not accept this file type."}}',
    );
    final staged = <StagedAttachment>[];
    final errors = <String>[];

    await _pumpButton(tester, adapter, staged: staged, errors: errors);
    await _choose(tester, 'Document');

    expect(
      adapter.uploads.single.mimeType,
      'application/vnd.android.package-archive',
    );
    expect(staged, isEmpty);
    expect(errors, ['WhatsApp does not accept this file type.']);
  });

  testWidgets('9. Gallery still uses the image picker, not the file picker', (
    tester,
  ) async {
    final filePicker = _FakeFilePicker([]);
    FilePickerPlatform.instance = filePicker;
    final imagePath = file('gallery.png').path!;
    final imagePicker = _FakeImagePicker([imagePath]);
    ImagePickerPlatform.instance = imagePicker;
    final adapter = _StubAdapter();
    final staged = <StagedAttachment>[];

    await _pumpButton(tester, adapter, staged: staged);
    await _choose(tester, 'Photo from gallery');

    expect(imagePicker.multiCalls, 1);
    expect(filePicker.calls, 0);
    expect(adapter.uploads.single.fileName, 'gallery.png');
    expect(adapter.uploads.single.mimeType, 'image/png');
    expect(staged.single.attachment.type, 'IMAGE');
  });

  testWidgets('10. A picked file is staged and sent through the same reply '
      'flow', (tester) async {
    FilePickerPlatform.instance = _FakeFilePicker([file('report.xlsx')]);
    final adapter = _StubAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_client(adapter)),
          currentEmployeeProvider.overrideWithValue(_employee()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ConversationScreen(conversationId: 42),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _choose(tester, 'Document');
    expect(find.text('report.xlsx'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final reply = adapter.received.singleWhere(
      (r) => r.method == 'POST' && r.path == '/conversations/42/reply/',
    );
    expect((reply.data as Map<String, dynamic>)['attachment_ids'], ['draft-1']);
  });
}
