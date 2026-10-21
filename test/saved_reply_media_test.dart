/// Saved replies with a file: the model, the asset endpoints, the form's
/// pickers and voice recorder (with permission denial, discard and preview),
/// saving and its partial failures, editing / replacing / removing, and the
/// composer attaching a saved reply's file and sending it through the
/// ordinary reply path — with the platform pickers, the recorder and the
/// network faked.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/features/messages/message_bubble.dart';
import 'package:scenario_mobile/features/saved_replies/saved_replies_providers.dart';
import 'package:scenario_mobile/features/saved_replies/saved_replies_settings_screen.dart';
import 'package:scenario_mobile/features/saved_replies/saved_reply.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Platform fakes
// ---------------------------------------------------------------------------

class _FakeImagePicker extends ImagePickerPlatform {
  String? imagePath;
  String? videoPath;
  Object? throwOnPick;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (throwOnPick != null) throw throwOnPick!;
    return imagePath == null ? null : XFile(imagePath!);
  }

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    if (throwOnPick != null) throw throwOnPick!;
    return videoPath == null ? null : XFile(videoPath!);
  }
}

base class _PickedFile extends PlatformFile {
  _PickedFile(this.name, String filePath, this.sizeBytes)
    : uri = Uri.file(filePath);

  @override
  final String name;

  @override
  final Uri uri;

  final int sizeBytes;

  @override
  XFile get xFile => XFile(path!, name: name);

  @override
  int? lengthSync() => sizeBytes;

  @override
  Future<int?> length() async => sizeBytes;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() => const Stream.empty();
}

class _FakeFilePicker extends FilePickerPlatform {
  List<PlatformFile> files = [];
  FileType? lastType;

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
    lastType = type;
    return files;
  }
}

/// Records to a real file (the form checks it exists), as the plugin does.
class _FakeRecord extends RecordPlatform {
  bool permission = true;
  int starts = 0;
  bool cancelled = false;
  String? path;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    starts++;
    this.path = path;
    File(path).writeAsBytesSync(List.filled(64, 1));
  }

  @override
  Future<Stream<Uint8List>> startStream(String id, RecordConfig c) async =>
      const Stream.empty();

  @override
  Future<String?> stop(String recorderId) async => path;

  @override
  Future<void> cancel(String recorderId) async => cancelled = true;

  @override
  Future<bool> hasPermission(String id, {bool request = true}) async =>
      permission;

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -30, max: -10);

  @override
  Future<bool> isEncoderSupported(String id, AudioEncoder e) async => true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];

  @override
  RecordIos? getIos(String recorderId) => null;

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;
}

// ---------------------------------------------------------------------------
// HTTP stub
// ---------------------------------------------------------------------------

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  /// Reads the whole request body first, as a server does — an upload's
  /// file is only closed once its stream has been read.
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? _,
  ) async {
    await requestStream?.drain<void>();
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _page(List<Object?> results) => {
  'count': results.length,
  'next': null,
  'results': results,
};

Map<String, Object?> _asset({
  int id = 50,
  String type = 'FILE',
  String name = 'price-list.pdf',
  String mime = 'application/pdf',
  bool voice = false,
  int size = 2048,
}) => {
  'id': id,
  'public_id': 'a$id',
  'attachment_type': type,
  'mime_type': mime,
  'original_filename': name,
  'size_bytes': size,
  'is_voice': voice,
  'metadata': voice ? {'duration_ms': 3000} : <String, Object?>{},
  'content_url': '/api/saved-reply-assets/a$id/content/',
};

Map<String, Object?> _reply(
  int id,
  String title, {
  String body = 'Body',
  List<Map<String, Object?>> assets = const [],
}) => {
  'id': id,
  'title': title,
  'shortcut': '',
  'body': body,
  'category': '',
  'category_id': null,
  'position': 0,
  'scope': 'personal',
  'team': null,
  'is_active': true,
  'can_edit': true,
  'assets': assets,
};

/// The saved-replies backend: replies, their one file each.
class _Server {
  _Server({List<Map<String, Object?>>? replies}) : replies = replies ?? [];

  List<Map<String, Object?>> replies;
  final writes = <RequestOptions>[];

  /// Answers the next asset upload with this status.
  int? failUpload;

  /// Holds asset uploads until completed.
  Completer<void>? holdUpload;

  Map<String, Object?> _find(int id) =>
      replies.firstWhere((r) => r['id'] == id);

  void _put(Map<String, Object?> reply) {
    replies = [
      for (final r in replies)
        if (r['id'] != reply['id']) r,
      reply,
    ];
  }

  ApiClient client() {
    final client = ApiClient.create(cookieJar: CookieJar());
    client.raw.httpClientAdapter = _StubAdapter(_handle);
    return client;
  }

  Future<ResponseBody> _handle(RequestOptions o) async {
    final path = o.path;
    if (o.method != 'GET') writes.add(o);
    if (path == '/saved-reply-categories/') return _json(_page([]));
    if (path == '/saved-replies/') {
      if (o.method == 'GET') return _json(_page(replies));
      final body = Map<String, dynamic>.from(o.data as Map);
      final created = _reply(
        100 + replies.length,
        body['title'] as String,
        body: body['body'] as String? ?? '',
      );
      _put(created);
      return _json(created, 201);
    }
    final replyMatch = RegExp(r'^/saved-replies/(\d+)/$').firstMatch(path);
    if (replyMatch != null && o.method == 'PATCH') {
      final id = int.parse(replyMatch.group(1)!);
      final body = Map<String, dynamic>.from(o.data as Map);
      final updated = {..._find(id), ...body};
      _put(updated);
      return _json(updated);
    }
    if (path == '/saved-reply-assets/') {
      final hold = holdUpload;
      if (hold != null) await hold.future;
      if (failUpload case final status?) {
        failUpload = null;
        return _json({
          'error': {'code': 'error', 'message': 'Storage is down.'},
        }, status);
      }
      final form = o.data as FormData;
      final fields = {for (final f in form.fields) f.key: f.value};
      final id = int.parse(fields['saved_reply_id']!);
      final file = form.files.single.value;
      final voice = fields['is_voice'] == 'true';
      final updated = {
        ..._find(id),
        'assets': [
          _asset(
            id: 60,
            type: voice ? 'AUDIO' : 'FILE',
            name: file.filename ?? '',
            mime: file.contentType?.mimeType ?? '',
            voice: voice,
          ),
        ],
      };
      _put(updated);
      return _json(updated, 201);
    }
    final assetMatch = RegExp(r'^/saved-reply-assets/(\d+)/$').firstMatch(path);
    if (assetMatch != null && o.method == 'DELETE') {
      final assetId = int.parse(assetMatch.group(1)!);
      final owner = replies.firstWhere(
        (r) => (r['assets'] as List).any((a) => (a as Map)['id'] == assetId),
      );
      final updated = {...owner, 'assets': <Object?>[]};
      _put(updated);
      return _json(updated);
    }
    return _json({});
  }
}

Map<String, String> _fields(RequestOptions o) => {
  for (final f in (o.data as FormData).fields) f.key: f.value,
};

final _me = Employee(
  id: 1,
  email: 'agent@acme.test',
  fullName: 'Sam Agent',
  initials: 'SA',
  role: 'AGENT',
  roleDisplay: 'Agent',
  availability: 'ONLINE',
  permissions: const {Perm.conversationReply, Perm.conversationNote},
  visibilityScope: 'ALL',
  organization: const Organization(id: 1, name: 'Acme'),
);

/// Taps [finder] and lets the work it starts finish: real event-loop turns
/// (the upload streams a real file), tap included — a future started
/// outside `runAsync` would wait on fake time forever. Bounded, so a stuck
/// future still fails.
Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await _turns(tester);
  });
}

Future<void> _turns(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

final _save = find.byKey(const Key('saved-reply-form-save'));
final _preview = find.byKey(const Key('saved-reply-attachment-preview'));
final _details = find.byKey(const Key('saved-reply-attachment-details'));

void main() {
  late Directory temp;
  late String jpeg;
  late String video;
  late String pdf;
  late String mp3;
  late _FakeImagePicker images;
  late _FakeFilePicker files;
  late _FakeRecord record;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('saved_reply_media_');
    jpeg = '${temp.path}${Platform.pathSeparator}photo.jpg';
    File(
      jpeg,
    ).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(60, 0)]);
    video = '${temp.path}${Platform.pathSeparator}clip.mp4';
    File(video).writeAsBytesSync(List.filled(2048, 0));
    pdf = '${temp.path}${Platform.pathSeparator}menu.pdf';
    File(
      pdf,
    ).writeAsBytesSync([0x25, 0x50, 0x44, 0x46, ...List.filled(1200, 0)]);
    mp3 = '${temp.path}${Platform.pathSeparator}jingle.mp3';
    File(mp3).writeAsBytesSync(List.filled(4096, 0));
    images = _FakeImagePicker();
    files = _FakeFilePicker();
    record = _FakeRecord();
    ImagePickerPlatform.instance = images;
    FilePickerPlatform.instance = files;
    RecordPlatform.instance = record;
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDown(() async {
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a just-uploaded file open; the OS clears it.
    }
  });

  // -------------------------------------------------------------------------
  group('model and API', () {
    test('a reply with and without a file', () {
      final withFile = SavedReply.fromJson(
        _reply(1, 'Menu', assets: [_asset(voice: true, type: 'AUDIO')]),
      );
      final asset = withFile.asset!;
      expect(asset.id, 50);
      expect(asset.isVoice, isTrue);
      expect(asset.durationMs, 3000);
      expect(asset.originalFilename, 'price-list.pdf');
      expect(asset.toAttachment().isAudio, isTrue);
      expect(
        asset.toAttachment().resolvedUrl,
        endsWith('/api/saved-reply-assets/a50/content/'),
      );

      final textOnly = SavedReply.fromJson(_reply(2, 'Hi'));
      expect(textOnly.asset, isNull);
      final old = SavedReply.fromJson({'id': 3, 'title': 'Old', 'body': 'b'});
      expect(old.assets, isEmpty);
    });

    test('upload, remove, and the composer\'s server-side copy', () async {
      final requests = <RequestOptions>[];
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = _StubAdapter((o) {
        requests.add(o);
        if (o.path.contains('from-saved-reply')) {
          return _json({
            'id': 'draft-1',
            'type': 'FILE',
            'mime_type': 'application/pdf',
            'file_name': 'menu.pdf',
            'size_bytes': 10,
            'is_voice': false,
          }, 201);
        }
        return _json(_reply(7, 'Menu', assets: [_asset()]));
      });
      final repo = SavedRepliesRepository(client);

      await repo.uploadAsset(
        7,
        filePath: pdf,
        fileName: 'menu.pdf',
        mimeType: 'application/pdf',
      );
      expect(requests.last.path, '/saved-reply-assets/');
      expect(_fields(requests.last), {'saved_reply_id': '7'});
      final part = (requests.last.data as FormData).files.single;
      expect(part.key, 'file');
      expect(part.value.filename, 'menu.pdf');
      expect(part.value.contentType?.mimeType, 'application/pdf');

      await repo.uploadAsset(
        7,
        filePath: mp3,
        fileName: 'voice-message.ogg',
        isVoice: true,
        durationMs: 4200,
      );
      expect(_fields(requests.last), {
        'saved_reply_id': '7',
        'is_voice': 'true',
        'duration_ms': '4200',
      });

      await repo.removeAsset(50);
      expect(requests.last.method, 'DELETE');
      expect(requests.last.path, '/saved-reply-assets/50/');

      final draft = await ConversationRepository(
        client,
      ).attachmentFromSavedReply(42, 7);
      expect(
        requests.last.path,
        '/conversations/42/attachments/from-saved-reply/',
      );
      expect(requests.last.data, {'saved_reply_id': 7});
      expect(draft.id, 'draft-1');
    });
  });

  // -------------------------------------------------------------------------
  group('the form', () {
    Future<void> open(
      WidgetTester tester,
      _Server server, {
      int? edit,
      Locale locale = const Locale('en'),
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(server.client()),
            currentEmployeeProvider.overrideWithValue(_me),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SavedRepliesSettingsTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key(edit == null ? 'add-saved-reply' : 'saved-reply-$edit-edit'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, {String body = ''}) async {
      await tester.enterText(
        find.byKey(const Key('saved-reply-form-title')),
        'Price list',
      );
      if (body.isNotEmpty) {
        await tester.enterText(
          find.byKey(const Key('saved-reply-form-body')),
          body,
        );
      }
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('an image: previewed, then saved as the reply\'s file — '
        'with no text needed', (tester) async {
      images.imagePath = jpeg;
      final server = _Server();
      await open(tester, server);
      await fill(tester);

      await tapKey(tester, 'saved-reply-attach-image');
      expect(_preview, findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(tester.widget<Text>(_details).data, startsWith('Image'));

      await _tapAndSettle(tester, _save);

      expect(server.writes.map((w) => '${w.method} ${w.path}').toList(), [
        'POST /saved-replies/',
        'POST /saved-reply-assets/',
      ]);
      expect(_fields(server.writes.last)['saved_reply_id'], '100');
      final part = (server.writes.last.data as FormData).files.single.value;
      expect(part.filename, 'photo.jpg');
      // From the bytes (a JPEG header), not the name alone.
      expect(part.contentType?.mimeType, 'image/jpeg');
      expect(find.text('Saved reply added'), findsOneWidget);
      expect(
        find.byKey(const Key('saved-reply-file-badge-60')),
        findsOneWidget,
      );
    });

    testWidgets('a video, an audio file and a document each show what they '
        'are; one file per reply', (tester) async {
      images.videoPath = video;
      files.files = [_PickedFile('jingle.mp3', mp3, 4096)];
      await open(tester, _Server());

      await tapKey(tester, 'saved-reply-attach-video');
      expect(find.text('clip.mp4'), findsOneWidget);
      expect(tester.widget<Text>(_details).data, 'Video · 2.0 KB');

      await tapKey(tester, 'saved-reply-attach-audio');
      expect(files.lastType, FileType.audio);
      expect(find.text('clip.mp4'), findsNothing);
      expect(find.text('jingle.mp3'), findsOneWidget);
      // Audio can be listened to before saving.
      expect(find.byType(VoiceNotePlayer), findsOneWidget);

      files.files = [_PickedFile('menu.pdf', pdf, 1204)];
      await tapKey(tester, 'saved-reply-attach-file');
      expect(files.lastType, FileType.any);
      expect(_preview, findsOneWidget);
      expect(tester.widget<Text>(_details).data, 'PDF · 1.2 KB');
      expect(
        find.text('Choosing another file replaces this one.'),
        findsOneWidget,
      );

      await tapKey(tester, 'saved-reply-attachment-remove');
      expect(_preview, findsNothing);
    });

    testWidgets('without a file, text is still required', (tester) async {
      final server = _Server();
      await open(tester, server);
      await fill(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.text('Enter the reply text.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('a denied photo permission, or an unreadable file, is said', (
      tester,
    ) async {
      images.throwOnPick = PlatformException(code: 'photo_access_denied');
      files.files = [
        _PickedFile(
          'gone.pdf',
          '${temp.path}${Platform.pathSeparator}gone.pdf',
          10,
        ),
      ];
      await open(tester, _Server());

      await tapKey(tester, 'saved-reply-attach-image');
      expect(find.byKey(const Key('saved-reply-form-error')), findsOneWidget);
      expect(_preview, findsNothing);

      await tapKey(tester, 'saved-reply-attach-file');
      expect(
        find.text("Couldn't open that file. Try another one."),
        findsOneWidget,
      );
      expect(_preview, findsNothing);
    });

    testWidgets('record, listen back, discard, record again, save as a voice '
        'message — and the temporary file is cleaned up', (tester) async {
      final server = _Server();
      await open(tester, server);
      await fill(tester);
      // Nothing records until asked.
      expect(record.starts, 0);

      await tapKey(tester, 'saved-reply-attach-record');
      expect(
        find.byKey(const Key('saved-reply-recording-bar')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('saved-reply-recording-time')))
            .data,
        contains('0:03 / 5:00'),
      );

      // Thrown away mid-recording: nothing kept.
      final first = record.path!;
      await _tapAndSettle(
        tester,
        find.byKey(const Key('saved-reply-recording-discard')),
      );
      expect(record.cancelled, isTrue);
      expect(File(first).existsSync(), isFalse);
      expect(_preview, findsNothing);

      await tapKey(tester, 'saved-reply-attach-record');
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('saved-reply-recording-stop')));
      await tester.pumpAndSettle();
      final recorded = record.path!;
      expect(_preview, findsOneWidget);
      expect(tester.widget<Text>(_details).data, startsWith('Voice message'));
      expect(find.byType(VoiceNotePlayer), findsOneWidget);

      await _tapAndSettle(tester, _save);
      final upload = server.writes.last;
      expect(upload.path, '/saved-reply-assets/');
      expect(_fields(upload)['is_voice'], 'true');
      expect(_fields(upload)['duration_ms'], '2000');
      expect(
        (upload.data as FormData).files.single.value.contentType?.mimeType,
        'audio/ogg',
      );
      // Uploaded: the recording's temporary file is gone.
      expect(File(recorded).existsSync(), isFalse);
    });

    testWidgets('a denied microphone records nothing and says why', (
      tester,
    ) async {
      record.permission = false;
      await open(tester, _Server());
      await tapKey(tester, 'saved-reply-attach-record');
      expect(record.starts, 0);
      expect(find.byKey(const Key('saved-reply-recording-bar')), findsNothing);
      expect(find.byKey(const Key('saved-reply-form-error')), findsOneWidget);
    });

    testWidgets('the text saves but the file does not: said so, and Save '
        'retries the file on the same reply', (tester) async {
      files.files = [_PickedFile('menu.pdf', pdf, 1204)];
      final server = _Server()..failUpload = 500;
      await open(tester, server);
      await fill(tester, body: 'Our prices');
      await tapKey(tester, 'saved-reply-attach-file');

      await _tapAndSettle(tester, _save);

      expect(
        find.textContaining("The reply's text was saved, but its file wasn't."),
        findsOneWidget,
      );
      expect(find.text('Saved reply added'), findsNothing);
      // Still open, now editing that reply, the file still chosen.
      expect(find.text('Edit saved reply'), findsOneWidget);
      expect(_preview, findsOneWidget);

      await _tapAndSettle(tester, _save);
      expect(server.writes.map((w) => '${w.method} ${w.path}').toList(), [
        'POST /saved-replies/',
        'POST /saved-reply-assets/',
        'PATCH /saved-replies/100/',
        'POST /saved-reply-assets/',
      ]);
      expect(server.replies, hasLength(1));
      expect(find.text('Saved reply added'), findsOneWidget);
    });

    testWidgets('Cancel during the upload stops it; the text stays saved', (
      tester,
    ) async {
      files.files = [_PickedFile('menu.pdf', pdf, 1204)];
      final server = _Server()..holdUpload = Completer<void>();
      await open(tester, server);
      await fill(tester, body: 'Our prices');
      await tapKey(tester, 'saved-reply-attach-file');

      await tester.runAsync(() async {
        await tester.tap(_save);
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (server.writes.any((w) => w.path == '/saved-reply-assets/')) {
            break;
          }
        }
      });
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('saved-reply-form-cancel')));
        server.holdUpload!.complete();
        await _turns(tester);
      });

      expect(
        find.text(
          "Upload cancelled. The reply's text was saved; tap Save to upload "
          'the file again.',
        ),
        findsOneWidget,
      );
      // The text was saved: the sheet stays on that reply, and the list is
      // re-read so it shows whatever the server kept.
      expect(find.text('Edit saved reply'), findsOneWidget);
      expect(server.replies, hasLength(1));
      expect(find.text('Saved reply added'), findsNothing);
    });

    testWidgets('editing: the current file is shown; removing it is saved', (
      tester,
    ) async {
      final server = _Server(
        replies: [
          _reply(5, 'Menu', assets: [_asset()]),
        ],
      );
      await open(tester, server, edit: 5);
      expect(
        find.descendant(of: _preview, matching: find.text('price-list.pdf')),
        findsOneWidget,
      );

      await tapKey(tester, 'saved-reply-attachment-remove');
      expect(_preview, findsNothing);
      await _tapAndSettle(tester, _save);

      expect(server.writes.map((w) => '${w.method} ${w.path}').toList(), [
        'PATCH /saved-replies/5/',
        'DELETE /saved-reply-assets/50/',
      ]);
      expect(server.replies.single['assets'], isEmpty);
    });

    testWidgets('editing: replacing the file uploads the new one only', (
      tester,
    ) async {
      files.files = [_PickedFile('menu.pdf', pdf, 1204)];
      final server = _Server(
        replies: [
          _reply(5, 'Menu', assets: [_asset()]),
        ],
      );
      await open(tester, server, edit: 5);
      await tapKey(tester, 'saved-reply-attach-file');
      expect(
        find.descendant(of: _preview, matching: find.text('menu.pdf')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _preview, matching: find.text('price-list.pdf')),
        findsNothing,
      );

      await _tapAndSettle(tester, _save);
      expect(server.writes.map((w) => '${w.method} ${w.path}').toList(), [
        'PATCH /saved-replies/5/',
        'POST /saved-reply-assets/',
      ]);
    });

    testWidgets('editing a text-only reply touches no file', (tester) async {
      final server = _Server(replies: [_reply(5, 'Hi')]);
      await open(tester, server, edit: 5);
      await _tapAndSettle(tester, _save);
      expect(server.writes.map((w) => '${w.method} ${w.path}').toList(), [
        'PATCH /saved-replies/5/',
      ]);
    });

    for (final (label, locale, dark) in [
      ('Arabic dark', const Locale('ar'), true),
      ('English light', const Locale('en'), false),
    ]) {
      testWidgets('the attachment section — $label', (tester) async {
        images.imagePath = jpeg;
        await open(
          tester,
          _Server(),
          locale: locale,
          theme: dark ? AppTheme.dark : AppTheme.light,
        );
        expect(
          find.text(
            locale.languageCode == 'ar'
                ? 'مرفق (اختياري)'
                : 'Attachment (optional)',
          ),
          findsOneWidget,
        );
        await tapKey(tester, 'saved-reply-attach-image');
        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(tester.element(_preview)),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  group('in a conversation', () {
    String detail({bool outboundMedia = true}) => jsonEncode({
      'id': 42,
      'customer': {'id': 7, 'display_name': 'Sarah Connor'},
      'provider': 'INSTAGRAM',
      'channel_name': 'Shop',
      'status': 'OPEN',
      'media_capabilities': {'outbound_media': outboundMedia},
    });

    late List<RequestOptions> requests;

    ApiClient client({bool outboundMedia = true, int? draftStatus}) {
      requests = [];
      final c = ApiClient.create(cookieJar: CookieJar());
      c.raw.httpClientAdapter = _StubAdapter((o) {
        requests.add(o);
        final path = o.path;
        if (path == '/saved-replies/') {
          return _json(
            _page([
              _reply(9, 'Menu', body: 'Here is our menu', assets: [_asset()]),
            ]),
          );
        }
        if (path == '/conversations/42/attachments/from-saved-reply/') {
          if (draftStatus != null) {
            return _json({
              'error': {
                'code': 'unsupported_media',
                'message': 'Instagram does not accept PDF files.',
              },
            }, draftStatus);
          }
          return _json({
            'id': 'draft-from-saved',
            'type': 'FILE',
            'mime_type': 'application/pdf',
            'file_name': 'price-list.pdf',
            'size_bytes': 2048,
            'is_voice': false,
          }, 201);
        }
        if (path == '/conversations/42/reply/') {
          return _json({
            'id': 501,
            'direction': 'OUTBOUND',
            'sender_type': 'AGENT',
            'message_type': 'FILE',
            'text': 'Here is our menu',
            'attachments': [],
            'delivery_status': 'SENT',
            'sent_at': '2026-10-20T12:00:00Z',
          }, 201);
        }
        if (path.contains('/messages/')) return _json({'results': []});
        if (path.contains('/notes/')) return _json([]);
        if (path == '/conversations/42/') {
          return ResponseBody.fromString(
            detail(outboundMedia: outboundMedia),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return _json({});
      });
      return c;
    }

    Future<void> pickSavedReply(WidgetTester tester, ApiClient c) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(c),
            currentEmployeeProvider.overrideWithValue(_me),
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
      await tester.tap(find.byKey(const Key('savedRepliesButton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('saved-reply-file-badge-50')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('savedReply-9')));
      await tester.pumpAndSettle();
    }

    String composerText(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('composer_reply_input')))
        .controller!
        .text;

    testWidgets('its text and its file go into the composer, and Send sends '
        'both through the ordinary reply', (tester) async {
      final c = client();
      await pickSavedReply(tester, c);

      expect(composerText(tester), 'Here is our menu');
      final copy = requests.where(
        (r) => r.path == '/conversations/42/attachments/from-saved-reply/',
      );
      expect(copy.single.data, {'saved_reply_id': 9});
      // Nothing uploaded from the phone.
      expect(
        requests.where((r) => r.path == '/conversations/42/attachments/'),
        isEmpty,
      );
      expect(find.text('price-list.pdf'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final reply = requests.firstWhere(
        (r) => r.path == '/conversations/42/reply/',
      );
      final body = reply.data as Map<String, dynamic>;
      expect(body['attachment_ids'], ['draft-from-saved']);
      expect(body['text'], 'Here is our menu');
    });

    testWidgets('the file can be removed before sending', (tester) async {
      await pickSavedReply(tester, client());
      await tester.tap(find.byTooltip('Remove attachment'));
      await tester.pumpAndSettle();
      expect(find.text('price-list.pdf'), findsNothing);
      expect(
        requests.where(
          (r) =>
              r.method == 'DELETE' &&
              r.path == '/conversations/42/attachments/draft-from-saved/',
        ),
        hasLength(1),
      );
      expect(composerText(tester), 'Here is our menu');
    });

    testWidgets('a channel that takes no files: the text only, and said so', (
      tester,
    ) async {
      await pickSavedReply(tester, client(outboundMedia: false));
      expect(composerText(tester), 'Here is our menu');
      expect(
        requests.where((r) => r.path.contains('from-saved-reply')),
        isEmpty,
      );
      expect(
        find.text(
          "The text was added, but this channel doesn't accept files, so the "
          "saved reply's file wasn't attached.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('the server refusing the file: its reason, the card failed, '
        'the text kept', (tester) async {
      await pickSavedReply(tester, client(draftStatus: 400));
      expect(find.text('Instagram does not accept PDF files.'), findsOneWidget);
      expect(composerText(tester), 'Here is our menu');
      expect(find.text('Upload failed'), findsOneWidget);
    });
  });
}
