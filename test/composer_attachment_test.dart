/// Regression tests for the two composer features layered onto the
/// Conversation screen:
///
///  - Image attachment (gallery/camera pick -> stage -> preview -> send)
///  - Voice recording (record -> stage -> send)
///
/// Both share one backend contract:
///
///     POST /conversations/{id}/attachments/   (multipart: file, is_voice?, duration_ms?)
///     DELETE /conversations/{id}/attachments/{draft_id}/
///     POST /conversations/{id}/reply/         (attachment_ids: [id], text?, client_message_id?)
///
/// `image_picker` and `record` have no platform channel in the widget-test
/// environment, so their platform interfaces are faked here the same way
/// `settings_channels_tab_test.dart` fakes `UrlLauncherPlatform` — real
/// plugin code runs, only the native call at the bottom is replaced.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
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
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

/// A genuine, decodable 1x1 JPEG — the composer's preview renders the
/// picked file with `Image.file()`, which needs real image bytes or the
/// codec throws "Invalid image data"; arbitrary placeholder bytes fail it.
final Uint8List _tinyJpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkI'
  'CQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQ'
  'EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCAABAAEDASIA'
  'AhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEB'
  'AQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX'
  '/9k=',
);

// ---------------------------------------------------------------------------
// Fakes: image_picker
// ---------------------------------------------------------------------------

class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker({this.filePath, this.throwOnPick});

  /// The path returned for a successful pick; `null` means "cancelled" —
  /// `pickImage` returning `null`, matching what the real plugin does when
  /// the user backs out of the picker.
  String? filePath;

  /// If set, thrown from [getImageFromSource] instead of returning a result
  /// — used to simulate a `PlatformException` (permission denied) or any
  /// other pick failure.
  Object? throwOnPick;

  ImageSource? lastSource;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastSource = source;
    if (throwOnPick != null) throw throwOnPick!;
    if (filePath == null) return null;
    return XFile(filePath!);
  }
}

// ---------------------------------------------------------------------------
// Fakes: record
// ---------------------------------------------------------------------------

class _FakeRecordPlatform extends RecordPlatform {
  /// Path [stop] resolves to — a real file the test creates ahead of time,
  /// since the code under test feeds it straight into
  /// `MultipartFile.fromFile()`, real `dart:io` file I/O that needs an
  /// actual file on disk. Left unset, [start] fills it in with the path it
  /// was asked to record to (mirroring the real plugin, which returns
  /// whatever it was told to write) — but does not overwrite a path the
  /// test already provided.
  String? stopReturnsPath;
  bool permissionGranted = true;
  bool startThrows = false;
  bool cancelled = false;
  bool stopped = false;
  bool disposed = false;
  int startCallCount = 0;

  final _stateController = StreamController<RecordState>.broadcast();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    startCallCount++;
    if (startThrows) throw Exception('platform start failure');
    stopReturnsPath ??= path;
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async => const Stream<Uint8List>.empty();

  @override
  Future<String?> stop(String recorderId) async {
    stopped = true;
    return stopReturnsPath;
  }

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permissionGranted;

  @override
  Future<void> dispose(String recorderId) async {
    disposed = true;
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -30, max: -10);

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];

  @override
  Future<void> cancel(String recorderId) async {
    cancelled = true;
  }

  @override
  RecordIos? getIos(String recorderId) => null;

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      _stateController.stream;

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}

// ---------------------------------------------------------------------------
// Fakes: path_provider (record's temp-file path)
// ---------------------------------------------------------------------------

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.tempPath);

  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getLibraryPath() async => tempPath;

  @override
  Future<String?> getExternalStoragePath() async => tempPath;

  @override
  Future<List<String>?> getExternalCachePaths() async => [tempPath];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => [tempPath];

  @override
  Future<String?> getDownloadsPath() async => tempPath;
}

// ---------------------------------------------------------------------------
// HTTP stub
// ---------------------------------------------------------------------------

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    received.add(options);
    return handler(options);
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

ApiClient _stubClient(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  final adapter = _StubAdapter(handler);
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
  permissions: {Perm.conversationReply, Perm.conversationNote},
  visibilityScope: 'ALL',
  organization: Organization(id: 1, name: 'Acme Retail'),
);

const _conversationDetail = '''
{
  "id": 42,
  "customer": {
    "id": 7,
    "display_name": "Sarah Connor",
    "avatar_url": "",
    "initials": "SC",
    "phone": "+201124868273"
  },
  "provider": "WHATSAPP",
  "channel_name": "Scenario Sales",
  "status": "OPEN"
}
''';

Future<void> _pumpConversation(
  WidgetTester tester,
  ApiClient client, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        currentEmployeeProvider.overrideWithValue(_employee()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: theme ?? AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConversationScreen(conversationId: 42),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Advances frames while a busy spinner is on screen, without
/// `pumpAndSettle()` — its indeterminate `CircularProgressIndicator`
/// animation never naturally goes idle, so `pumpAndSettle()` hangs for the
/// whole duration of any of this composer's in-flight async calls (upload,
/// discard, stop-and-send). Bounded, so a genuinely stuck future still fails
/// the test instead of hanging it. Must be called from inside `runAsync()`
/// (see `_tapAndPumpUntilIdle`) — plain `pump()` never gives a real
/// event-loop turn to the `dart:io` file I/O `MultipartFile.fromFile()`
/// does underneath.
///
/// [passes] repeats the wait: a voice-note stop-and-send shows the stop
/// button's own spinner while uploading, then — once that clears — the
/// Send button's own spinner while it sends, in two back-to-back phases a
/// single wait can miss the second half of.
Future<void> _pumpUntilIdle(
  WidgetTester tester, {
  int maxPumps = 30,
  int passes = 1,
}) async {
  for (var pass = 0; pass < passes; pass++) {
    for (var i = 0; i < maxPumps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    // A few more short frames so anything the busy state's completion just
    // triggered (a SnackBar's entrance animation, a rebuild) has landed too
    // — still bounded, so a genuinely stuck future fails the test either way.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  }
}

/// Taps [finder] and then waits out the busy spinner via [_pumpUntilIdle].
///
/// The tap and the pumping both run inside one `runAsync()`: staging an
/// attachment goes through `MultipartFile.fromFile()`, which does real
/// `dart:io` file I/O (`File.length()`) that never completes under plain
/// `pump()` calls — only a real event-loop turn lets it resolve, and that
/// future is already created (and stuck) the moment `tap()` fires the
/// `onTap` callback, so the tap itself has to be inside `runAsync()` too.
Future<void> _tapAndPumpUntilIdle(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 30,
  int passes = 1,
  Finder? secondTap,
}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    if (secondTap != null) {
      // One immediate frame first: the target disables itself the instant
      // _busy flips true, before the second tap is even attempted. Guarded
      // (rather than warnIfMissed: false) because runAsync() surfaces a
      // missed tap as a hard exception, not a suppressible warning.
      await tester.pump();
      if (secondTap.evaluate().isNotEmpty) await tester.tap(secondTap);
    }
    await _pumpUntilIdle(tester, maxPumps: maxPumps, passes: passes);
  });
}

/// Taps the mic and waits for the recording UI to actually appear.
///
/// Same reasoning as [_tapAndPumpUntilIdle]: `_start()` does real async
/// work (`hasPermission()`, `getTemporaryDirectory()`, the platform's own
/// `start()` call) before the recording UI renders, none of which resolves
/// under plain bounded `pump()` calls the way `runAsync()` + real delays do.
Future<void> _tapMicAndWaitForRecording(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.textContaining('Recording').evaluate().isNotEmpty) break;
    }
  });
}

void main() {
  late Directory tempDir;
  late String pickedImagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('composer_attachment_');
    // A real file on disk — MultipartFile.fromFile() needs one that
    // actually exists, and the composer's own preview renders it with
    // Image.file(), which needs genuine, decodable JPEG bytes (not just
    // any bytes) or the image codec throws.
    final imageFile = File('${tempDir.path}/photo.jpg');
    await imageFile.writeAsBytes(_tinyJpegBytes);
    pickedImagePath = imageFile.path;

    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Image attachment — composer UI', () {
    testWidgets('attachment button is visible in the reply composer', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
    });

    testWidgets('tapping attachment offers gallery and camera actions', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Photo from gallery'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget);
    });

    testWidgets(
      'picking from gallery uploads and shows a preview before sending',
      (tester) async {
        ImagePickerPlatform.instance = _FakeImagePicker(
          filePath: pickedImagePath,
        );

        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path == '/conversations/42/attachments/') {
            return _json('''
{
  "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "type": "IMAGE",
  "mime_type": "image/jpeg",
  "file_name": "photo.jpg",
  "size_bytes": 16,
  "is_voice": false,
  "duration_ms": null,
  "expires_at": "2026-09-04T12:00:00Z"
}
''', 201);
          }
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await _pumpConversation(tester, client);
        await tester.tap(find.byIcon(Icons.attach_file_rounded));
        await tester.pumpAndSettle();
        // Not pumpAndSettle(): while the upload is in flight, the button
        // shows an indeterminate CircularProgressIndicator, whose animation
        // never naturally goes idle. Tapping through runAsync() is required
        // too — staging goes through MultipartFile.fromFile(), which does
        // real dart:io file I/O (File.length()) that never completes under
        // plain tap()/pump() calls, only under a real event-loop turn.
        await _tapAndPumpUntilIdle(tester, find.text('Photo from gallery'));

        expect(
          adapter.received.any(
            (r) =>
                r.method == 'POST' &&
                r.path == '/conversations/42/attachments/',
          ),
          isTrue,
        );
        expect(find.byType(Image), findsWidgets);
        expect(find.byIcon(Icons.close), findsOneWidget);
      },
    );

    testWidgets('the staged preview can be removed before sending', (
      tester,
    ) async {
      ImagePickerPlatform.instance = _FakeImagePicker(
        filePath: pickedImagePath,
      );

      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/conversations/42/attachments/') {
          return _json('''
{"id": "draft-1", "type": "IMAGE", "mime_type": "image/jpeg",
 "file_name": "photo.jpg", "size_bytes": 16, "is_voice": false,
 "duration_ms": null, "expires_at": "2026-09-04T12:00:00Z"}
''', 201);
        }
        if (options.method == 'DELETE' &&
            options.path == '/conversations/42/attachments/draft-1/') {
          return _json('', 204);
        }
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpConversation(tester, client);
      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();
      // Not pumpAndSettle(): see the matching comment on the upload test
      // above — the in-flight spinner never naturally goes idle, and the
      // tap must run through runAsync() too (real file I/O underneath).
      await _tapAndPumpUntilIdle(tester, find.text('Photo from gallery'));

      expect(find.byIcon(Icons.close), findsOneWidget);

      // Same reasoning: the remove badge shows its own spinner in flight.
      await _tapAndPumpUntilIdle(tester, find.byIcon(Icons.close));

      expect(
        adapter.received.any(
          (r) =>
              r.method == 'DELETE' &&
              r.path == '/conversations/42/attachments/draft-1/',
        ),
        isTrue,
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets(
      'sending a staged image POSTs reply/ with attachment_ids referencing the draft',
      (tester) async {
        ImagePickerPlatform.instance = _FakeImagePicker(
          filePath: pickedImagePath,
        );

        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path == '/conversations/42/attachments/') {
            return _json('''
{"id": "draft-xyz", "type": "IMAGE", "mime_type": "image/jpeg",
 "file_name": "photo.jpg", "size_bytes": 16, "is_voice": false,
 "duration_ms": null, "expires_at": "2026-09-04T12:00:00Z"}
''', 201);
          }
          if (options.method == 'POST' &&
              options.path == '/conversations/42/reply/') {
            return _json('''
{
  "id": 501, "public_id": "p1", "direction": "OUTBOUND",
  "sender_type": "AGENT", "sender_name": "Sam Agent", "sender_initials": "SA",
  "message_type": "IMAGE", "text": "",
  "attachments": [{"type": "IMAGE", "url": "https://cdn.example/img.jpg", "file_name": "photo.jpg", "mime_type": "image/jpeg"}],
  "delivery_status": "SENT", "delivery_error": "", "client_message_id": "",
  "sent_at": "2026-09-04T12:00:00Z", "delivered_at": null, "read_at": null
}
''', 201);
          }
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await _pumpConversation(tester, client);
        await tester.tap(find.byIcon(Icons.attach_file_rounded));
        await tester.pumpAndSettle();
        // Not pumpAndSettle(): see the matching comment on the upload test
        // above — the in-flight spinner never naturally goes idle, and the
        // tap must run through runAsync() too (real file I/O underneath).
        await _tapAndPumpUntilIdle(tester, find.text('Photo from gallery'));

        await tester.tap(find.byIcon(Icons.send_rounded));
        // Not pumpAndSettle(): the sent image message now renders through
        // the real MessageBubble image path, which keeps a FutureBuilder
        // (session-cookie headers) and CachedNetworkImage's own fetch of
        // the fixture's unstubbed https://cdn.example/img.jpg in flight —
        // neither naturally goes idle in this offline test environment.
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final replyReq = adapter.received.firstWhere(
          (r) => r.method == 'POST' && r.path == '/conversations/42/reply/',
        );
        final body = replyReq.data as Map<String, dynamic>;
        expect(body['attachment_ids'], ['draft-xyz']);
      },
    );

    testWidgets('an upload failure (permission denied) is shown, not a crash', (
      tester,
    ) async {
      ImagePickerPlatform.instance = _FakeImagePicker(
        throwOnPick: PlatformException(code: 'camera_access_denied'),
      );

      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Permission was denied. Enable it in your device settings to attach photos.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an upload API failure (400) is shown, not a crash', (
      tester,
    ) async {
      ImagePickerPlatform.instance = _FakeImagePicker(
        filePath: pickedImagePath,
      );

      final client = _stubClient((options) {
        if (options.method == 'POST' &&
            options.path == '/conversations/42/attachments/') {
          return _json(
            '{"error": {"code": "invalid", "message": "Unsupported file type.", "details": {}}}',
            400,
          );
        }
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();
      // Not pumpAndSettle(): see the matching comment on the upload test
      // above — the in-flight spinner never naturally goes idle, and the
      // tap must run through runAsync() too (real file I/O underneath).
      await _tapAndPumpUntilIdle(tester, find.text('Photo from gallery'));

      expect(find.text('Unsupported file type.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the attachment button twice does not double-upload', (
      tester,
    ) async {
      var uploadCalls = 0;
      ImagePickerPlatform.instance = _FakeImagePicker(
        filePath: pickedImagePath,
      );

      final client = _stubClient((options) {
        if (options.method == 'POST' &&
            options.path == '/conversations/42/attachments/') {
          uploadCalls++;
          return _json('''
{"id": "draft-1", "type": "IMAGE", "mime_type": "image/jpeg",
 "file_name": "photo.jpg", "size_bytes": 16, "is_voice": false,
 "duration_ms": null, "expires_at": "2026-09-04T12:00:00Z"}
''', 201);
        }
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pumpAndSettle();
      // Not pumpAndSettle(): the upload button's own spinner never
      // naturally goes idle, and the tap must run through runAsync() too
      // (real file I/O underneath). secondTap re-taps the attachment
      // button while still busy, to confirm it's a no-op.
      await _tapAndPumpUntilIdle(
        tester,
        find.text('Photo from gallery'),
        secondTap: find.byIcon(Icons.attach_file_rounded),
      );

      expect(uploadCalls, 1);
    });
  });

  group('Voice recording — composer UI', () {
    testWidgets('microphone button is visible in the reply composer', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);

      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });

    testWidgets(
      'tapping the mic requests permission and starts recording, showing duration',
      (tester) async {
        final fakeRecord = _FakeRecordPlatform();
        RecordPlatform.instance = fakeRecord;

        final client = _stubClient((options) {
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });

        await _pumpConversation(tester, client);
        await tester.runAsync(() async {
          await tester.tap(find.byIcon(Icons.mic_none_rounded));
          // Not pumpAndSettle(): once recording starts, its Timer.periodic
          // never naturally goes idle, so pumpAndSettle() would wait
          // forever. The duration ticker this test asserts on runs on real
          // Timer.periodic ticks, so it — and the recording-start wait
          // before it — use real delays under runAsync() rather than
          // tester.pump(Duration), which only advances the fake clock.
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (find.textContaining('Recording').evaluate().isNotEmpty) break;
          }

          expect(fakeRecord.startCallCount, 1);
          expect(find.textContaining('Recording'), findsOneWidget);

          for (var i = 0; i < 110; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (find.textContaining('0:02').evaluate().isNotEmpty) break;
          }
          expect(find.textContaining('0:02'), findsOneWidget);

          // Clean up: cancel so the timer doesn't outlive the test.
          await tester.tap(find.byIcon(Icons.delete_outline));
          await tester.pump();
        });
      },
    );

    testWidgets('microphone permission denial is handled gracefully', (
      tester,
    ) async {
      final fakeRecord = _FakeRecordPlatform()..permissionGranted = false;
      RecordPlatform.instance = fakeRecord;

      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      // Not pumpAndSettle(): the idle mic button shows its own indeterminate
      // spinner while hasPermission() is in flight.
      await _tapAndPumpUntilIdle(tester, find.byIcon(Icons.mic_none_rounded));

      expect(
        find.text(
          'Microphone access was denied. Enable it in your device settings to record a voice message.',
        ),
        findsOneWidget,
      );
      expect(fakeRecord.startCallCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recording can be canceled and sends nothing', (tester) async {
      final fakeRecord = _FakeRecordPlatform();
      RecordPlatform.instance = fakeRecord;

      final adapter = _StubAdapter((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpConversation(tester, client);
      // Not pumpAndSettle() — see _tapMicAndWaitForRecording's doc comment.
      await _tapMicAndWaitForRecording(tester);

      expect(find.textContaining('Recording'), findsOneWidget);

      // Not a plain tap()+pumpAndSettle(): _cancel() awaits the platform's
      // own cancel()/dispose() calls, real async work that (like the
      // upload's MultipartFile.fromFile() elsewhere in this file) only
      // resolves under runAsync(), not the fake-clock test zone.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.delete_outline));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });

      expect(fakeRecord.cancelled, isTrue);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(
        adapter.received.any((r) => r.path.contains('/attachments/')),
        isFalse,
      );
      expect(
        adapter.received.any(
          (r) => r.method == 'POST' && r.path == '/conversations/42/reply/',
        ),
        isFalse,
      );
    });

    testWidgets(
      'completing a recording uploads it and sends it as a voice message',
      (tester) async {
        // File.writeAsBytes() is real dart:io I/O — testWidgets() runs its
        // body in a fake-clock zone where that never completes, so it must
        // go through runAsync() too (see the matching comment on
        // _tapAndPumpUntilIdle above).
        final voiceFile = File('${tempDir.path}/voice-recorded.m4a');
        await tester.runAsync(
          () => voiceFile.writeAsBytes(List<int>.filled(8, 0)),
        );

        final fakeRecord = _FakeRecordPlatform()
          ..stopReturnsPath = voiceFile.path;
        RecordPlatform.instance = fakeRecord;

        final adapter = _StubAdapter((options) {
          if (options.method == 'POST' &&
              options.path == '/conversations/42/attachments/') {
            return _json('''
{"id": "voice-draft-1", "type": "AUDIO", "mime_type": "audio/aac",
 "file_name": "voice-message.m4a", "size_bytes": 8, "is_voice": true,
 "duration_ms": 3000, "expires_at": "2026-09-04T12:00:00Z"}
''', 201);
          }
          if (options.method == 'POST' &&
              options.path == '/conversations/42/reply/') {
            return _json('''
{
  "id": 502, "public_id": "p2", "direction": "OUTBOUND",
  "sender_type": "AGENT", "sender_name": "Sam Agent", "sender_initials": "SA",
  "message_type": "AUDIO", "text": "",
  "attachments": [{"type": "AUDIO", "url": "https://cdn.example/voice.m4a", "file_name": "voice-message.m4a", "mime_type": "audio/aac"}],
  "delivery_status": "SENT", "delivery_error": "", "client_message_id": "",
  "sent_at": "2026-09-04T12:00:00Z", "delivered_at": null, "read_at": null
}
''', 201);
          }
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });
        final client = ApiClient.create(cookieJar: CookieJar());
        client.raw.httpClientAdapter = adapter;

        await _pumpConversation(tester, client);
        // Not pumpAndSettle() — see _tapMicAndWaitForRecording's doc comment.
        await _tapMicAndWaitForRecording(tester);

        // Not pumpAndSettle(): stopping shows an indeterminate spinner while
        // the upload is in flight (real dart:io file I/O, so the tap runs
        // through runAsync() too), and a voice note sends immediately on
        // staging, which shows the Send button's own busy spinner too —
        // neither naturally goes idle. Two passes cover both phases, since
        // the Send spinner only appears after the upload spinner clears.
        await _tapAndPumpUntilIdle(
          tester,
          find.byIcon(Icons.stop_rounded),
          passes: 2,
        );

        expect(fakeRecord.stopped, isTrue);
        expect(fakeRecord.disposed, isTrue);

        final uploadReq = adapter.received.firstWhere(
          (r) =>
              r.method == 'POST' && r.path == '/conversations/42/attachments/',
        );
        expect(uploadReq.data, isA<FormData>());
        final formData = uploadReq.data as FormData;
        expect(
          formData.fields.any((f) => f.key == 'is_voice' && f.value == 'true'),
          isTrue,
        );

        final replyReq = adapter.received.firstWhere(
          (r) => r.method == 'POST' && r.path == '/conversations/42/reply/',
        );
        final body = replyReq.data as Map<String, dynamic>;
        expect(body['attachment_ids'], ['voice-draft-1']);

        // Back to the idle mic icon — no lingering recording UI.
        expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      },
    );

    testWidgets('a recording-start failure is handled gracefully', (
      tester,
    ) async {
      final fakeRecord = _FakeRecordPlatform()..startThrows = true;
      RecordPlatform.instance = fakeRecord;

      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      // Not pumpAndSettle(): the idle mic button shows its own indeterminate
      // spinner while start() is in flight.
      await _tapAndPumpUntilIdle(tester, find.byIcon(Icons.mic_none_rounded));

      expect(
        find.text("Couldn't start recording. Please try again."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    });

    testWidgets('an upload failure after stopping is handled gracefully', (
      tester,
    ) async {
      // File.writeAsBytes() is real dart:io I/O — testWidgets() runs its
      // body in a fake-clock zone where that never completes, so it must go
      // through runAsync() too (see the matching comment on
      // _tapAndPumpUntilIdle above).
      final voiceFile = File('${tempDir.path}/voice-recorded.m4a');
      await tester.runAsync(
        () => voiceFile.writeAsBytes(List<int>.filled(8, 0)),
      );
      final fakeRecord = _FakeRecordPlatform()
        ..stopReturnsPath = voiceFile.path;
      RecordPlatform.instance = fakeRecord;

      final client = _stubClient((options) {
        if (options.method == 'POST' &&
            options.path == '/conversations/42/attachments/') {
          return _json(
            '{"error": {"code": "invalid", "message": "Too large.", "details": {}}}',
            400,
          );
        }
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);
      // Not pumpAndSettle() — see _tapMicAndWaitForRecording's doc comment.
      await _tapMicAndWaitForRecording(tester);
      // Not pumpAndSettle(): stopping shows an indeterminate spinner while
      // the upload is in flight (real dart:io file I/O, so the tap runs
      // through runAsync() too), which never naturally goes idle either.
      await _tapAndPumpUntilIdle(tester, find.byIcon(Icons.stop_rounded));

      expect(find.text('Too large.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'leaving the conversation screen mid-recording releases the recorder',
      (tester) async {
        final fakeRecord = _FakeRecordPlatform();
        RecordPlatform.instance = fakeRecord;

        final client = _stubClient((options) {
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });

        await _pumpConversation(tester, client);
        // Not pumpAndSettle() — see _tapMicAndWaitForRecording's doc comment.
        await _tapMicAndWaitForRecording(tester);
        expect(find.textContaining('Recording'), findsOneWidget);

        // Navigate away while still recording.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              currentEmployeeProvider.overrideWithValue(_employee()),
            ],
            child: const MaterialApp(
              home: Scaffold(body: Text('Other screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // cancel() runs fire-and-forget from State.dispose() (a sync
        // lifecycle method can't await it) and is itself real async
        // platform work — same as the delete-tap in the cancel test above,
        // it only progresses under runAsync(), not plain pump() calls.
        await tester.runAsync(() async {
          for (var i = 0; i < 30 && !fakeRecord.cancelled; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });

        // The safety property that matters here is that the microphone
        // gets released — cancel() is what actually does that; dispose()
        // afterward is best-effort resource cleanup on a screen the agent
        // has already left, not asserted on its own.
        expect(fakeRecord.cancelled, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Existing text-message behavior is unaffected', () {
    testWidgets('a plain text reply still sends with no attachment_ids', (
      tester,
    ) async {
      final adapter = _StubAdapter((options) {
        if (options.method == 'POST' &&
            options.path == '/conversations/42/reply/') {
          return _json('''
{
  "id": 900, "public_id": "p9", "direction": "OUTBOUND",
  "sender_type": "AGENT", "sender_name": "Sam Agent", "sender_initials": "SA",
  "message_type": "TEXT", "text": "Hello there",
  "attachments": [], "delivery_status": "SENT", "delivery_error": "",
  "client_message_id": "", "sent_at": "2026-09-04T12:00:00Z",
  "delivered_at": null, "read_at": null
}
''', 201);
        }
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });
      final client = ApiClient.create(cookieJar: CookieJar());
      client.raw.httpClientAdapter = adapter;

      await _pumpConversation(tester, client);
      await tester.enterText(
        find.byKey(const ValueKey('composer_reply_input')),
        'Hello there',
      );
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final replyReq = adapter.received.firstWhere(
        (r) => r.method == 'POST' && r.path == '/conversations/42/reply/',
      );
      final body = replyReq.data as Map<String, dynamic>;
      expect(body['text'], 'Hello there');
      expect(body.containsKey('attachment_ids'), isFalse);
      expect(find.text('Hello there'), findsWidgets);
    });
  });

  group('Theming, RTL, and narrow screens', () {
    testWidgets('composer with attachment/mic controls renders in dark theme', (
      tester,
    ) async {
      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client, theme: AppTheme.dark);

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'composer with attachment/mic controls renders in Arabic (RTL)',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });

        await _pumpConversation(tester, client, locale: const Locale('ar'));

        expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
        expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('composer does not overflow on a narrow Android width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final client = _stubClient((options) {
        if (options.path.contains('/messages/')) {
          return _json('{"results": []}', 200);
        }
        if (options.path.contains('/notes/')) {
          return _json('[]', 200);
        }
        if (options.path.contains('/conversations/42/')) {
          return _json(_conversationDetail, 200);
        }
        return _json('{}', 200);
      });

      await _pumpConversation(tester, client);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the recording bar does not overflow on a narrow Android width',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        RecordPlatform.instance = _FakeRecordPlatform();

        final client = _stubClient((options) {
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });

        await _pumpConversation(tester, client);
        // Not pumpAndSettle() — see _tapMicAndWaitForRecording's doc comment.
        await _tapMicAndWaitForRecording(tester);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'normal composer has [attachment] [text field] [mic] [send] ordered with send at far right',
      (tester) async {
        final client = _stubClient((options) {
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });

        await _pumpConversation(tester, client);

        final attachX = tester
            .getTopLeft(find.byIcon(Icons.attach_file_rounded))
            .dx;
        final inputX = tester
            .getTopLeft(find.byKey(const ValueKey('composer_reply_input')))
            .dx;
        final micX = tester.getTopLeft(find.byIcon(Icons.mic_none_rounded)).dx;
        final sendX = tester.getTopLeft(find.byIcon(Icons.send_rounded)).dx;

        expect(attachX, lessThan(inputX));
        expect(inputX, lessThan(micX));
        expect(micX, lessThan(sendX));
      },
    );

    testWidgets(
      'recording bar shows red dot, recording text, 5:00 timer, trash, and square stop button on right',
      (tester) async {
        RecordPlatform.instance = _FakeRecordPlatform();

        final client = _stubClient((options) {
          if (options.path.contains('/messages/')) {
            return _json('{"results": []}', 200);
          }
          if (options.path.contains('/notes/')) {
            return _json('[]', 200);
          }
          if (options.path.contains('/conversations/42/')) {
            return _json(_conversationDetail, 200);
          }
          return _json('{}', 200);
        });

        await _pumpConversation(tester, client);
        await _tapMicAndWaitForRecording(tester);

        expect(find.textContaining('Recording'), findsOneWidget);
        expect(find.textContaining('/ 5:00'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

        final trashX = tester.getTopLeft(find.byIcon(Icons.delete_outline)).dx;
        final stopX = tester.getTopLeft(find.byIcon(Icons.stop_rounded)).dx;
        expect(trashX, lessThan(stopX));

        // Clean up
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pump();
      },
    );
  });
}
