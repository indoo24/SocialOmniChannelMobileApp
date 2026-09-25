/// Unit-level regression tests for the document attachment pipeline:
///
///  - MIME detection (content signature first, extension as fallback)
///  - filename safety (separators, `..`, control chars, UTF-8 length)
///  - header-byte reading
///  - error mapping (413, cancel vs. stall)
///  - `ApiClient.upload`: a long but progressing upload survives; a stalled
///    one fails as a timeout; a cancelled one is a silent cancel
///  - `ApiClient.downloadToFile` / `AttachmentHelper.downloadAttachmentFile`:
///    streamed, atomic, de-duplicated, and never leaving a partial file
///  - `ConversationController.retry` resending under the same
///    `client_message_id`, so the backend's idempotency can hold
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';
import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/core/utils/attachment_helper.dart';
import 'package:scenario_mobile/features/authentication/auth_controller.dart';
import 'package:scenario_mobile/features/messages/conversation_controller.dart';

typedef _Handler =
    Future<ResponseBody> Function(
      RequestOptions options,
      Stream<Uint8List>? body,
    );

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final _Handler handler;
  final List<RequestOptions> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? _,
  ) {
    received.add(options);
    return handler(options, requestStream);
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

({ApiClient client, _StubAdapter adapter}) _client(
  _Handler handler, {
  void Function()? onSessionExpired,
}) {
  final client = ApiClient.create(
    cookieJar: CookieJar(),
    onSessionExpired: onSessionExpired,
  );
  final adapter = _StubAdapter(handler);
  client.raw.httpClientAdapter = adapter;
  return (client: client, adapter: adapter);
}

const _pdfMagic = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37];
const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _zipMagic = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00];

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getDownloadsPath() async => path;

  @override
  Future<String?> getExternalStoragePath() async => path;
}

/// Seeded with fixed state so `send`/`retry` run without the REST `build()`.
class _SeededController extends ConversationController {
  _SeededController(super.conversationId, this._initial);

  final ConversationState _initial;

  @override
  Future<ConversationState> build() async => _initial;

  @override
  Future<void> refreshFromServer({String? triggerTraceId}) async {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('attachment_pipeline_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File writeFile(String name, List<int> bytes) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(bytes);

  group('MIME detection', () {
    test('the content signature wins over a misleading extension', () {
      expect(
        AttachmentHelper.detectMimeType(
          fileName: 'holiday.jpg',
          headerBytes: _pngMagic,
        ),
        'image/png',
      );
    });

    test('a file with no extension is identified by its bytes', () {
      expect(
        AttachmentHelper.detectMimeType(
          fileName: 'Scanned document',
          headerBytes: _pdfMagic,
        ),
        'application/pdf',
      );
    });

    test('ZIP-based Office files keep their own type, not application/zip', () {
      for (final (name, mime) in [
        (
          'contract.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        (
          'report.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ]) {
        expect(
          AttachmentHelper.detectMimeType(
            fileName: name,
            headerBytes: _zipMagic,
          ),
          mime,
        );
      }
    });

    test('signature-less formats fall back to the extension', () {
      expect(
        AttachmentHelper.detectMimeType(
          fileName: 'notes.txt',
          headerBytes: utf8.encode('hello'),
        ),
        'text/plain',
      );
      expect(AttachmentHelper.detectMimeType(fileName: 'data.csv'), 'text/csv');
    });

    test('the display name is preferred over the on-disk cache path', () {
      expect(
        AttachmentHelper.detectMimeType(
          fileName: 'budget.xlsx',
          filePath: '/cache/file_picker/1712/tmp123',
        ),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(
        AttachmentHelper.detectMimeType(
          fileName: 'no-extension',
          filePath: '/cache/file_picker/budget.pdf',
        ),
        'application/pdf',
      );
    });

    test('nothing recognisable yields null — never a forged type', () {
      expect(
        AttachmentHelper.detectMimeType(
          fileName: 'backup.qzx9',
          headerBytes: [1, 2, 3, 4],
        ),
        isNull,
      );
    });
  });

  group('readHeaderBytes', () {
    test('reads only the signature prefix of a large file', () async {
      final big = writeFile('big.bin', List.filled(5 * 1024 * 1024, 7));
      final header = await AttachmentHelper.readHeaderBytes(big.path);
      expect(header, isNotNull);
      expect(header!.length, lessThanOrEqualTo(64));
      expect(header.length, greaterThan(0));
    });

    test('a missing file yields null instead of throwing', () async {
      expect(
        await AttachmentHelper.readHeaderBytes('${tempDir.path}/gone.pdf'),
        isNull,
      );
    });
  });

  group('safeFileName', () {
    test('strips separators, reserved and control characters', () {
      expect(
        AttachmentHelper.safeFileName('../../etc/pass\u0000wd:*?.pdf'),
        '.._.._etc_pass_wd___.pdf',
      );
      expect(
        AttachmentHelper.safeFileName(r'C:\Users\x.pdf'),
        'C__Users_x.pdf',
      );
    });

    test('never returns an empty, "." or ".." segment', () {
      expect(AttachmentHelper.safeFileName(''), 'file');
      expect(AttachmentHelper.safeFileName('   '), 'file');
      expect(AttachmentHelper.safeFileName('.'), 'file');
      expect(AttachmentHelper.safeFileName('..'), 'file');
    });

    test('keeps ordinary Unicode, Arabic and spaces untouched', () {
      const name = 'عرض سعر 2026 (final v2).pdf';
      expect(AttachmentHelper.safeFileName(name), name);
    });

    test('trims a long Arabic name by bytes, whole characters, keeping the '
        'extension', () {
      final name = '${'تقرير' * 60}.docx'; // 300 chars, ~600 UTF-8 bytes
      final safe = AttachmentHelper.safeFileName(name);
      expect(
        utf8.encode(safe).length,
        lessThanOrEqualTo(AttachmentHelper.maxFileNameBytes),
      );
      expect(safe, endsWith('.docx'));
      expect(safe, startsWith('تقرير'));
      // Round-trips: no UTF-8 sequence was cut in half.
      expect(utf8.decode(utf8.encode(safe)), safe);
    });
  });

  group('media marker stripping', () {
    String textOf(String raw) => Message.fromJson({
      'id': 1,
      'direction': 'INBOUND',
      'text': raw,
      'sent_at': '2026-09-25T10:00:00Z',
    }).text;

    test('a marker between words leaves exactly one space', () {
      expect(
        textOf('receipt: [[media:IMAGE]] and agreement: [[media:FILE]]'),
        'receipt: and agreement:',
      );
    });

    test('adjacent markers collapse to one separator', () {
      expect(textOf('hi [[media:IMAGE]] [media:FILE] there'), 'hi there');
    });

    test('a marker on its own line leaves no stray spaces', () {
      expect(textOf('first\n[[media:IMAGE]]\nsecond'), 'first\n\nsecond');
      expect(textOf('[media: image name=photo.jpg]'), isEmpty);
    });

    test("the customer's own spacing elsewhere is untouched", () {
      expect(
        textOf('Total:    120 EGP [[media:FILE]]  ok'),
        'Total:    120 EGP ok',
      );
    });
  });

  group('error mapping', () {
    test('a 413 without the JSON envelope reads as a size error', () {
      final error = ApiException.fromResponse(413, '<html>Too Large</html>');
      expect(error.statusCode, 413);
      expect(error.message, 'That file is too large to send.');
    });
  });

  group('ApiClient.upload', () {
    FormData form(File file) => FormData.fromMap({
      'file': MultipartFile.fromFileSync(file.path, filename: 'big.pdf'),
    });

    test('a long upload that keeps progressing is not cut off', () async {
      final file = writeFile('big.pdf', List.filled(512 * 1024, 1));
      var progressEvents = 0;
      final (:client, :adapter) = _client((options, body) async {
        // Slow uplink: every chunk takes a while, the whole body far longer
        // than the idle timeout.
        await for (final _ in body!) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        return _json({'id': 'draft-1'}, 201);
      });

      final watch = Stopwatch()..start();
      final result = await client.upload<Map<String, dynamic>>(
        '/conversations/1/attachments/',
        body: form(file),
        idleTimeout: const Duration(milliseconds: 150),
        onSendProgress: (_, _) => progressEvents++,
      );

      expect(result['id'], 'draft-1');
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 150)));
      expect(progressEvents, greaterThan(1));
      expect(adapter.received.single.sendTimeout, Duration.zero);
    });

    test('a stalled upload fails as a retryable timeout', () async {
      final file = writeFile('stall.pdf', List.filled(256 * 1024, 1));
      final (:client, adapter: _) = _client((options, body) async {
        await body!.first; // one chunk, then silence
        return Completer<ResponseBody>().future;
      });

      await expectLater(
        client.upload<dynamic>(
          '/conversations/1/attachments/',
          body: form(file),
          idleTimeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('took too long'),
          ),
        ),
      );
    });

    test('a caller cancel is a silent RequestCancelledException', () async {
      final file = writeFile('cancel.pdf', List.filled(1024, 1));
      final (:client, adapter: _) = _client(
        (options, body) => Completer<ResponseBody>().future,
      );
      final token = CancelToken();
      Timer(const Duration(milliseconds: 30), token.cancel);

      await expectLater(
        client.upload<dynamic>(
          '/conversations/1/attachments/',
          body: form(file),
          cancelToken: token,
        ),
        throwsA(isA<RequestCancelledException>()),
      );
    });
  });

  group('ApiClient.downloadToFile', () {
    ResponseBody bytesBody(List<int> bytes, int status, {int? length}) =>
        ResponseBody.fromBytes(
          bytes,
          status,
          headers: {
            Headers.contentLengthHeader: ['${length ?? bytes.length}'],
          },
        );

    test('streams a successful body to the given path', () async {
      final (:client, adapter: _) = _client(
        (options, _) async => bytesBody(List.filled(2048, 9), 200),
      );
      final path = '${tempDir.path}/out.pdf';
      await client.downloadToFile('https://files.test/a', path);
      expect(File(path).lengthSync(), 2048);
    });

    test('an error status leaves no file behind', () async {
      final (:client, adapter: _) = _client(
        (options, _) async => _json({
          'error': {'code': 'not_found', 'message': 'Not found.'},
        }, 404),
      );
      final path = '${tempDir.path}/missing.pdf';
      await expectLater(
        client.downloadToFile('https://files.test/a', path),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      expect(File(path).existsSync(), isFalse);
    });

    test('a truncated body is rejected and deleted', () async {
      final (:client, adapter: _) = _client(
        (options, _) async => bytesBody(List.filled(10, 9), 200, length: 5000),
      );
      final path = '${tempDir.path}/short.pdf';
      await expectLater(
        client.downloadToFile('https://files.test/a', path),
        throwsA(isA<NetworkException>()),
      );
      expect(File(path).existsSync(), isFalse);
    });

    test('a 401 ends the session like any other request', () async {
      var expired = 0;
      final (:client, adapter: _) = _client(
        (options, _) async => _json({}, 401),
        onSessionExpired: () => expired++,
      );
      await expectLater(
        client.downloadToFile('https://files.test/a', '${tempDir.path}/x'),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(expired, 1);
    });
  });

  group('AttachmentHelper.downloadAttachmentFile', () {
    const attachment = MessageAttachment(
      type: 'FILE',
      attachmentId: '8f14e45f-ceea-467a-9cfa-0000000000aa',
      url: 'https://files.test/content/8f14',
      fileName: 'Q3 report.pdf',
      mimeType: 'application/pdf',
    );

    test('two taps share one transfer and one finished file', () async {
      final gate = Completer<void>();
      final (:client, :adapter) = _client((options, _) async {
        await gate.future;
        return ResponseBody.fromBytes(List.filled(4096, 3), 200);
      });

      final first = AttachmentHelper.downloadAttachmentFile(
        attachment: attachment,
        api: client,
      );
      final second = AttachmentHelper.downloadAttachmentFile(
        attachment: attachment,
        api: client,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      final files = await Future.wait([first, second]);

      expect(adapter.received, hasLength(1));
      expect(files[0]!.path, files[1]!.path);
      expect(files[0]!.lengthSync(), 4096);
      expect(files[0]!.path, endsWith('Q3 report.pdf'));
      expect(File('${files[0]!.path}.part').existsSync(), isFalse);
    });

    test('a failed download caches nothing, so the next tap retries', () async {
      var calls = 0;
      final (:client, adapter: _) = _client((options, _) async {
        calls++;
        return calls == 1
            ? _json({}, 503)
            : ResponseBody.fromBytes(List.filled(100, 1), 200);
      });

      expect(
        await AttachmentHelper.downloadAttachmentFile(
          attachment: attachment,
          api: client,
        ),
        isNull,
      );
      expect(await AttachmentHelper.findLocalAttachment(attachment), isNull);

      final retried = await AttachmentHelper.downloadAttachmentFile(
        attachment: attachment,
        api: client,
      );
      expect(retried!.lengthSync(), 100);
      expect(calls, 2);
    });

    test('a non-https URL is never fetched with the session', () async {
      final (:client, :adapter) = _client(
        (options, _) async => ResponseBody.fromBytes([1], 200),
      );
      final result = await AttachmentHelper.downloadAttachmentFile(
        attachment: const MessageAttachment(
          type: 'FILE',
          url: 'http://evil.test/x.pdf',
          fileName: 'x.pdf',
        ),
        api: client,
      );
      expect(result, isNull);
      expect(adapter.received, isEmpty);
    });
  });

  group('ConversationController.retry', () {
    test('resends under the same client_message_id and draft ids', () async {
      final bodies = <Map<String, dynamic>>[];
      var replies = 0;
      final (:client, adapter: _) = _client((options, _) async {
        if (options.path == '/conversations/1/reply/') {
          bodies.add(Map<String, dynamic>.from(options.data as Map));
          replies++;
          // First attempt: the gateway times out after the server may
          // already have created the message.
          if (replies == 1) return _json({}, 504);
          return _json({
            'id': 900,
            'direction': 'OUTBOUND',
            'sender_type': 'AGENT',
            'text': 'Invoice attached',
            'delivery_status': 'SENT',
            'sent_at': '2026-09-25T12:00:00Z',
          }, 201);
        }
        return _json({}, 200);
      });
      final controller = _SeededController(
        1,
        ConversationState(
          conversation: Conversation.fromJson({
            'id': 1,
            'customer': {'id': 7, 'display_name': 'Sarah'},
            'provider': 'WHATSAPP',
            'status': 'OPEN',
          }),
          messages: const [],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          conversationControllerProvider(1).overrideWith(() => controller),
          apiClientProvider.overrideWithValue(client),
          currentEmployeeProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(conversationControllerProvider(1).future);

      await expectLater(
        controller.send('Invoice attached', attachmentIds: ['draft-a']),
        throwsA(isA<ApiException>()),
      );
      final failed = container
          .read(conversationControllerProvider(1))
          .value!
          .messages
          .single;
      expect(failed.hasFailed, isTrue);

      await controller.retry(failed.localId!);

      expect(bodies, hasLength(2));
      expect(bodies[0]['client_message_id'], isNotEmpty);
      expect(bodies[1]['client_message_id'], bodies[0]['client_message_id']);
      expect(bodies[1]['attachment_ids'], ['draft-a']);
      final messages = container
          .read(conversationControllerProvider(1))
          .value!
          .messages;
      expect(messages.map((m) => m.id), [900]);
    });
  });
}
