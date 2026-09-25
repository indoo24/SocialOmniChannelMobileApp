/// Widget and integration tests for the composer's attachment cards and
/// their uploads:
///
///  1. picking a (large) file immediately shows its card
///  2. the attach button stays a normal, usable button during uploads
///  3. real bytes-sent progress lands on the right card
///  4. 58% reads "58%"
///  5. simultaneous uploads progress and finish independently
///  6. cancelling one upload leaves the others running
///  7. a finished upload turns into the uploaded state
///  8. a failed upload shows its own failed state (retry only when safe)
///  9. the composer stays usable while files upload
/// 10. send behaves as before: drafts in pick order, once, idempotent retry
///
/// Plus the pipeline guarantees these cards sit on: pick order, at most
/// `maxConcurrentAttachmentUploads` at once, clean cancel on leaving, and
/// unreadable picks reported.
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
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    show XFile;
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/employee.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/theme/app_theme.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/composer_attachment.dart';
import 'package:scenario_mobile/features/messages/conversation_screen.dart';
import 'package:scenario_mobile/l10n/generated/app_localizations.dart';

import 'support/composer_upload_harness.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

base class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.uri);

  @override
  final String name;

  @override
  final Uri uri;

  @override
  XFile get xFile => XFile(path!, name: name);

  @override
  int? lengthSync() => path == null ? null : File(path!).lengthSync();

  @override
  Future<int?> length() async => lengthSync();

  @override
  Future<Uint8List> readAsBytes() => File(path!).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => const Stream.empty();
}

class _FakeFilePicker extends FilePickerPlatform {
  _FakeFilePicker(this.files);

  final List<PlatformFile> files;

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
  }) async => files;
}

/// How the fake server answers one upload, keyed by file name.
typedef _UploadPlan = Future<ResponseBody> Function(Stream<Uint8List> body);

class _Server implements HttpClientAdapter {
  _Server({this.plans = const {}, this.replyStatuses = const []});

  final Map<String, _UploadPlan> plans;

  /// Status for each successive reply; 201 once the list runs out.
  final List<int> replyStatuses;

  final List<RequestOptions> received = [];
  final List<String> uploadOrder = [];
  int inFlight = 0;
  int maxInFlight = 0;

  List<RequestOptions> get replies => received
      .where((r) => r.method == 'POST' && r.path == '/conversations/42/reply/')
      .toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? _,
  ) async {
    received.add(options);
    final path = options.path;
    if (options.method == 'POST' && path == '/conversations/42/attachments/') {
      final name = (options.data as FormData).files.single.value.filename!;
      uploadOrder.add(name);
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      try {
        final plan = plans[name];
        if (plan != null) return await plan(requestStream!);
        await requestStream!.drain<void>();
        return _draft(name);
      } finally {
        inFlight--;
      }
    }
    if (options.method == 'DELETE') return _json({}, 204);
    if (options.method == 'POST' && path == '/conversations/42/reply/') {
      final n = replies.length - 1;
      final status = n < replyStatuses.length ? replyStatuses[n] : 201;
      if (status != 201) {
        return _json({
          'error': {'code': 'unavailable', 'message': 'Try again shortly.'},
        }, status);
      }
      return _json({
        'id': 700 + n,
        'direction': 'OUTBOUND',
        'sender_type': 'AGENT',
        'sender_name': 'Sam Agent',
        'text': '',
        'delivery_status': 'SENT',
        'sent_at': '2026-09-25T12:00:00Z',
      }, 201);
    }
    if (path.contains('/messages/')) return _json({'results': []}, 200);
    if (path.contains('/notes/')) return _json([], 200);
    if (path.contains('/saved-replies/')) return _json({'results': []}, 200);
    if (path.contains('/conversations/42/')) {
      return _json({
        'id': 42,
        'customer': {'id': 7, 'display_name': 'Sarah', 'initials': 'S'},
        'provider': 'WHATSAPP',
        'channel_name': 'Scenario Sales',
        'status': 'OPEN',
        'last_customer_message_at': DateTime.now().toUtc().toIso8601String(),
      }, 200);
    }
    return _json({}, 200);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _draft(String name) => _json({
  'id': 'draft-$name',
  'type': 'FILE',
  'mime_type': 'application/pdf',
  'file_name': name,
  'size_bytes': 2048,
  'is_voice': false,
  'duration_ms': null,
  'expires_at': '2026-09-25T12:00:00Z',
}, 201);

/// Upload plan: drain, wait [ms], succeed.
_UploadPlan _delayed(String name, int ms) => (body) async {
  await body.drain<void>();
  await Future<void>.delayed(Duration(milliseconds: ms));
  return _draft(name);
};

/// Upload plan: never answers until [gate] completes (then succeeds), and
/// reads nothing meanwhile — a transfer that has not started moving bytes.
_UploadPlan _held(String name, Completer<void> gate) => (body) async {
  await gate.future;
  await body.drain<void>();
  return _draft(name);
};

/// Upload plan: a slow uplink — every chunk takes [chunkMs].
_UploadPlan _slow(String name, {int chunkMs = 30}) => (body) async {
  await for (final _ in body) {
    await Future<void>.delayed(Duration(milliseconds: chunkMs));
  }
  return _draft(name);
};

ApiClient _client(_Server server) {
  final client = ApiClient.create(cookieJar: CookieJar());
  client.raw.httpClientAdapter = server;
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

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _app(ApiClient client, Widget home) => ProviderScope(
  overrides: [
    apiClientProvider.overrideWithValue(client),
    currentEmployeeProvider.overrideWithValue(_employee()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// Pumps real time until [done] holds (or a bounded number of frames).
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxFrames = 150,
}) async {
  for (var i = 0; i < maxFrames && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
  }
}

/// Opens the sheet and picks Document inside runAsync (the upload does real
/// file I/O), leaving the uploads running.
Future<void> _pickDocuments(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.attach_file_rounded));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.text('Document'));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
  });
}

/// The card for [upload], and a finder inside it.
Finder _card(ComposerUpload upload) => find.byKey(ObjectKey(upload));
Finder _inCard(ComposerUpload upload, Finder finder) =>
    find.descendant(of: _card(upload), matching: finder);
String _percentOf(WidgetTester tester, ComposerUpload upload) => tester
    .widget<Text>(
      _inCard(upload, find.byKey(const Key('attachmentUploadPercent'))),
    )
    .data!;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_flow_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a file a card was reading; the OS reclaims
      // its temp directory regardless.
    }
  });

  _PickedFile doc(String name, {int size = 2048}) {
    final f = File('${tempDir.path}/$name')
      ..writeAsBytesSync(List.filled(size, 1));
    return _PickedFile(name, Uri.file(f.path));
  }

  /// The button + queue + cards, as the composer wires them.
  Future<ComposerUploadQueue> pumpHarness(
    WidgetTester tester,
    _Server server, {
    List<StagedAttachment>? staged,
    List<String>? errors,
  }) async {
    late ComposerUploadQueue queue;
    await tester.pumpWidget(
      _app(
        _client(server),
        Scaffold(
          body: Center(
            child: ComposerUploadHarness(
              staged: staged,
              errors: errors,
              onQueue: (q) => queue = q,
            ),
          ),
        ),
      ),
    );
    return queue;
  }

  testWidgets('1. picking a large file shows its card at once, uploading', (
    tester,
  ) async {
    final gate = Completer<void>();
    FilePickerPlatform.instance = _FakeFilePicker([
      doc('app-release.aab', size: 3 * 1024 * 1024),
    ]);
    final server = _Server(plans: {'app-release.aab': _held('x', gate)});
    final queue = await pumpHarness(tester, server);

    await _pickDocuments(tester);

    final upload = queue.items.single;
    expect(upload.status, ComposerUploadStatus.uploading);
    expect(_inCard(upload, find.text('app-release.aab')), findsOneWidget);
    expect(_percentOf(tester, upload), '0%');
    expect(
      _inCard(upload, find.byType(LinearProgressIndicator)),
      findsOneWidget,
    );
    expect(_inCard(upload, find.byTooltip('Cancel upload')), findsOneWidget);

    await tester.runAsync(() async {
      gate.complete();
      await _pumpUntil(tester, () => !queue.hasActiveUploads);
    });
  });

  testWidgets('2. the attach button stays a normal, enabled button', (
    tester,
  ) async {
    final gate = Completer<void>();
    FilePickerPlatform.instance = _FakeFilePicker([doc('big.pdf')]);
    final server = _Server(plans: {'big.pdf': _held('big.pdf', gate)});
    final queue = await pumpHarness(tester, server);

    await _pickDocuments(tester);
    expect(queue.hasActiveUploads, isTrue);

    final button = find.widgetWithIcon(IconButton, Icons.attach_file_rounded);
    expect(button, findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byType(ComposerAttachmentButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Attach'), findsOneWidget);

    await tester.runAsync(() async {
      gate.complete();
      await _pumpUntil(tester, () => !queue.hasActiveUploads);
    });
  });

  testWidgets('3 + 5. real progress lands on the right card, independently', (
    tester,
  ) async {
    final gate = Completer<void>();
    FilePickerPlatform.instance = _FakeFilePicker([
      doc('moving.pdf', size: 900 * 1024),
      doc('waiting.pdf'),
    ]);
    final server = _Server(
      plans: {
        'moving.pdf': _slow('moving.pdf'),
        'waiting.pdf': _held('waiting.pdf', gate),
      },
    );
    final queue = await pumpHarness(tester, server);

    await _pickDocuments(tester);
    final moving = queue.items[0];
    final waiting = queue.items[1];

    final seen = <String>{};
    await tester.runAsync(() async {
      await _pumpUntil(tester, () {
        if (moving.status == ComposerUploadStatus.uploading) {
          seen.add(_percentOf(tester, moving));
        }
        return moving.status != ComposerUploadStatus.uploading;
      }, maxFrames: 300);
    });

    // The moving file went through real intermediate percentages …
    expect(
      seen.where((p) => p != '0%' && p != '100%'),
      isNotEmpty,
      reason: 'seen: $seen',
    );
    // … and finished on its own, while the other never moved.
    expect(moving.status, ComposerUploadStatus.uploaded);
    expect(waiting.status, ComposerUploadStatus.uploading);
    expect(_percentOf(tester, waiting), '0%');
    expect(
      _inCard(moving, find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget,
    );
    expect(
      _inCard(waiting, find.byIcon(Icons.check_circle_rounded)),
      findsNothing,
    );

    await tester.runAsync(() async {
      gate.complete();
      await _pumpUntil(tester, () => !queue.hasActiveUploads);
    });
    expect(waiting.status, ComposerUploadStatus.uploaded);
  });

  testWidgets('4. a 58% upload reads 58%', (tester) async {
    final gate = Completer<void>();
    FilePickerPlatform.instance = _FakeFilePicker([doc('half.pdf')]);
    final server = _Server(plans: {'half.pdf': _held('half.pdf', gate)});
    final queue = await pumpHarness(tester, server);
    await _pickDocuments(tester);

    final upload = queue.items.single;
    upload.progress.value = 0.58;
    await tester.pump();

    expect(_percentOf(tester, upload), '58%');
    final bar = tester.widget<LinearProgressIndicator>(
      _inCard(upload, find.byType(LinearProgressIndicator)),
    );
    expect(bar.value, closeTo(0.58, 0.001));

    await tester.runAsync(() async {
      gate.complete();
      await _pumpUntil(tester, () => !queue.hasActiveUploads);
    });
  });

  testWidgets('6. cancelling one upload leaves the other running', (
    tester,
  ) async {
    final gateA = Completer<void>();
    final gateB = Completer<void>();
    FilePickerPlatform.instance = _FakeFilePicker([doc('a.pdf'), doc('b.pdf')]);
    final server = _Server(
      plans: {'a.pdf': _held('a.pdf', gateA), 'b.pdf': _held('b.pdf', gateB)},
    );
    final errors = <String>[];
    final queue = await pumpHarness(tester, server, errors: errors);
    await _pickDocuments(tester);
    final a = queue.items[0];
    final b = queue.items[1];

    await tester.runAsync(() async {
      await tester.tap(_inCard(a, find.byTooltip('Cancel upload')));
      await tester.pump();
      gateB.complete();
      await _pumpUntil(tester, () => !queue.hasActiveUploads);
    });

    expect(queue.items, [b]);
    expect(b.status, ComposerUploadStatus.uploaded);
    expect(find.text('a.pdf'), findsNothing);
    expect(errors, isEmpty); // a cancel is not an error
  });

  testWidgets('7. a finished upload shows the uploaded state', (tester) async {
    FilePickerPlatform.instance = _FakeFilePicker([doc('done.pdf')]);
    final server = _Server();
    final staged = <StagedAttachment>[];
    final queue = await pumpHarness(tester, server, staged: staged);

    await _pickDocuments(tester);
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );

    final upload = queue.items.single;
    expect(upload.status, ComposerUploadStatus.uploaded);
    expect(
      _inCard(upload, find.byIcon(Icons.check_circle_rounded)),
      findsOneWidget,
    );
    expect(_inCard(upload, find.text('2.0 KB')), findsOneWidget);
    expect(_inCard(upload, find.byType(LinearProgressIndicator)), findsNothing);
    expect(
      _inCard(upload, find.byTooltip('Remove attachment')),
      findsOneWidget,
    );
    expect(staged.single.draftId, 'draft-done.pdf');
  });

  testWidgets('8. a failed upload shows its own failed state and retries on '
      'tap only', (tester) async {
    var attempts = 0;
    FilePickerPlatform.instance = _FakeFilePicker([doc('flaky.pdf')]);
    final server = _Server(
      plans: {
        'flaky.pdf': (body) async {
          await body.drain<void>();
          attempts++;
          if (attempts == 1) {
            return _json({
              'error': {'code': 'unavailable', 'message': 'Busy.'},
            }, 503);
          }
          return _draft('flaky.pdf');
        },
      },
    );
    final errors = <String>[];
    final queue = await pumpHarness(tester, server, errors: errors);

    await _pickDocuments(tester);
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );
    final upload = queue.items.single;
    expect(upload.status, ComposerUploadStatus.failed);
    expect(_inCard(upload, find.text('Upload failed')), findsOneWidget);
    expect(errors, ['Busy.']);
    // Never retried on its own.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(attempts, 1);

    await tester.runAsync(() async {
      await tester.tap(_inCard(upload, find.byTooltip('Retry upload')));
      await _pumpUntil(tester, () => !queue.hasActiveUploads);
    });
    expect(attempts, 2);
    expect(upload.status, ComposerUploadStatus.uploaded);
  });

  testWidgets('8b. a rejected size is failed with no retry offered', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([doc('huge.zip')]);
    final server = _Server(
      plans: {
        'huge.zip': (body) async {
          await body.drain<void>();
          return ResponseBody.fromString(
            '<html><body>413 Request Entity Too Large</body></html>',
            413,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          );
        },
      },
    );
    final queue = await pumpHarness(tester, server);

    await _pickDocuments(tester);
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );

    final upload = queue.items.single;
    expect(upload.status, ComposerUploadStatus.failed);
    expect(upload.error!.statusCode, 413);
    expect(_inCard(upload, find.text('Upload failed')), findsOneWidget);
    expect(_inCard(upload, find.byTooltip('Retry upload')), findsNothing);
  });

  testWidgets('cards keep pick order whatever order uploads finish in', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([
      doc('a.pdf'),
      doc('b.pdf'),
      doc('c.pdf'),
    ]);
    final server = _Server(
      plans: {
        'a.pdf': _delayed('a.pdf', 300),
        'b.pdf': _delayed('b.pdf', 0),
        'c.pdf': _delayed('c.pdf', 120),
      },
    );
    final staged = <StagedAttachment>[];
    final queue = await pumpHarness(tester, server, staged: staged);

    await _pickDocuments(tester);
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );

    expect(staged.map((s) => s.draftId), [
      'draft-a.pdf',
      'draft-b.pdf',
      'draft-c.pdf',
    ]);
  });

  testWidgets('at most three files upload at once, the rest wait their turn', (
    tester,
  ) async {
    final names = [for (var i = 1; i <= 7; i++) 'f$i.pdf'];
    FilePickerPlatform.instance = _FakeFilePicker([
      for (final n in names) doc(n),
    ]);
    final server = _Server(plans: {for (final n in names) n: _delayed(n, 60)});
    final queue = await pumpHarness(tester, server);

    await _pickDocuments(tester);
    // Every card is there at once, even those still queued.
    expect(queue.items, hasLength(7));
    for (final n in names) {
      expect(find.text(n), findsOneWidget);
    }
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );

    expect(server.maxInFlight, maxConcurrentAttachmentUploads);
    expect(server.uploadOrder, hasLength(7)); // each file sent exactly once
    expect(
      queue.items.every((u) => u.status == ComposerUploadStatus.uploaded),
      isTrue,
    );
  });

  testWidgets('leaving mid-upload cancels without touching the dead widget', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([doc('slow.pdf')]);
    final server = _Server(
      plans: {'slow.pdf': (body) => Completer<ResponseBody>().future},
    );
    final errors = <String>[];
    await pumpHarness(tester, server, errors: errors);
    await _pickDocuments(tester);

    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(tester.takeException(), isNull);
    expect(errors, isEmpty);
  });

  testWidgets('a pick with no readable copy is reported, not dropped', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([
      _PickedFile('cloud.pdf', Uri.parse('content://provider/doc/1')),
      doc('local.pdf'),
    ]);
    final errors = <String>[];
    final queue = await pumpHarness(tester, _Server(), errors: errors);

    await _pickDocuments(tester);
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );

    expect(queue.items.map((u) => u.file.name), ['local.pdf']);
    expect(errors, ["Some files couldn't be uploaded. Please try again."]);
  });

  testWidgets('removing an uploaded card is immediate; DELETE runs behind it', (
    tester,
  ) async {
    FilePickerPlatform.instance = _FakeFilePicker([doc('x.pdf')]);
    final server = _Server();
    final queue = await pumpHarness(tester, server);
    await _pickDocuments(tester);
    await tester.runAsync(
      () => _pumpUntil(tester, () => !queue.hasActiveUploads),
    );

    bool deleted() => server.received.any(
      (r) =>
          r.method == 'DELETE' &&
          r.path == '/conversations/42/attachments/draft-x.pdf/',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Remove attachment'));
      // Out of the composer before the DELETE has even started.
      expect(queue.items, isEmpty);
      await _pumpUntil(tester, deleted);
    });
    expect(deleted(), isTrue);
  });

  group('on the conversation screen', () {
    Future<_Server> openAndPick(
      WidgetTester tester,
      List<_PickedFile> files, {
      Map<String, _UploadPlan> plans = const {},
      List<int> replyStatuses = const [],
    }) async {
      FilePickerPlatform.instance = _FakeFilePicker(files);
      final server = _Server(plans: plans, replyStatuses: replyStatuses);
      await tester.pumpWidget(
        _app(_client(server), const ConversationScreen(conversationId: 42)),
      );
      await tester.pumpAndSettle();
      await _pickDocuments(tester);
      return server;
    }

    bool uploading() =>
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty;

    Future<void> send(WidgetTester tester, {int taps = 1}) async {
      for (var i = 0; i < taps; i++) {
        await tester.tap(find.byIcon(Icons.send_rounded), warnIfMissed: false);
      }
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('9. the composer stays usable while a file uploads', (
      tester,
    ) async {
      final gate = Completer<void>();
      await openAndPick(
        tester,
        [doc('big.pdf', size: 2 * 1024 * 1024)],
        plans: {'big.pdf': _held('big.pdf', gate)},
      );
      expect(uploading(), isTrue);

      // Typing works.
      await tester.enterText(
        find.byKey(const ValueKey('composer_reply_input')),
        'Here is the file',
      );
      expect(find.text('Here is the file'), findsOneWidget);
      // Attach and saved replies stay enabled; nothing became a spinner.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.attach_file_rounded),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('savedRepliesButton')))
            .onPressed,
        isNotNull,
      );
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      // Send waits for the file, so the message cannot leave without it.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.send_rounded),
            )
            .onPressed,
        isNull,
      );

      await tester.runAsync(() async {
        gate.complete();
        await _pumpUntil(tester, () => !uploading());
      });
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.send_rounded),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('10. drafts are sent once, in pick order, on a double tap', (
      tester,
    ) async {
      final server = await openAndPick(
        tester,
        [doc('a.pdf'), doc('b.pdf'), doc('c.pdf')],
        plans: {
          'a.pdf': _delayed('a.pdf', 200),
          'b.pdf': _delayed('b.pdf', 0),
          'c.pdf': _delayed('c.pdf', 80),
        },
      );
      await tester.runAsync(() => _pumpUntil(tester, () => !uploading()));

      await send(tester, taps: 2);

      expect(server.replies, hasLength(1));
      expect(
        (server.replies.single.data as Map<String, dynamic>)['attachment_ids'],
        ['draft-a.pdf', 'draft-b.pdf', 'draft-c.pdf'],
      );
      expect(find.text('a.pdf'), findsNothing); // cards cleared on send
    });

    testWidgets('10b. a failed card is not sent and stays to retry or remove', (
      tester,
    ) async {
      final server = await openAndPick(
        tester,
        [doc('good.pdf'), doc('bad.pdf')],
        plans: {
          'bad.pdf': (body) async {
            await body.drain<void>();
            return _json({
              'error': {'code': 'invalid', 'message': 'Unsupported file.'},
            }, 400);
          },
        },
      );
      await tester.runAsync(() => _pumpUntil(tester, () => !uploading()));

      await send(tester);

      expect(
        (server.replies.single.data as Map<String, dynamic>)['attachment_ids'],
        ['draft-good.pdf'],
      );
      expect(find.text('bad.pdf'), findsOneWidget);
      expect(find.text('Upload failed'), findsOneWidget);
    });

    testWidgets('10c. a failed send retries with the same client_message_id '
        'and no re-upload', (tester) async {
      final server = await openAndPick(
        tester,
        [doc('invoice.pdf')],
        replyStatuses: [503],
      );
      await tester.runAsync(() => _pumpUntil(tester, () => !uploading()));

      await send(tester);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final bodies = server.replies
          .map((r) => r.data as Map<String, dynamic>)
          .toList();
      expect(bodies, hasLength(2));
      expect(bodies[1]['client_message_id'], bodies[0]['client_message_id']);
      expect(bodies[1]['attachment_ids'], ['draft-invoice.pdf']);
      expect(server.uploadOrder, ['invoice.pdf']);
    });
  });
}
