/// Internal notes: `InternalNote` model parsing,
/// `ConversationRepository.notes()`/`.addNote()`, and `NotesController`.
///
/// Mirrors `conversion_reporting_test.dart`'s `_StubAdapter` — networking is
/// tested directly against canned responses rather than through widgets.
library;

import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_client.dart';
import 'package:scenario_mobile/core/models/message.dart';
import 'package:scenario_mobile/core/providers.dart';
import 'package:scenario_mobile/features/conversations/conversation_repository.dart';
import 'package:scenario_mobile/features/messages/notes_controller.dart';

// ignore: library_private_types_in_public_api
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
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

(ConversationRepository, _StubAdapter) _repositoryReturning(
  ResponseBody Function(RequestOptions options) handler,
) {
  final client = ApiClient.create(cookieJar: CookieJar());
  final adapter = _StubAdapter(handler);
  client.raw.httpClientAdapter = adapter;
  return (ConversationRepository(client), adapter);
}

void main() {
  group('InternalNote.fromJson', () {
    test('parses the full backend shape', () {
      final note = InternalNote.fromJson({
        'id': 5,
        'body': 'Called back, no answer.',
        'author_name': 'Mohamed Gad',
        'author_initials': 'MG',
        'created_at': '2026-08-21T04:52:00Z',
      });

      expect(note.id, 5);
      expect(note.body, 'Called back, no answer.');
      expect(note.authorName, 'Mohamed Gad');
      expect(note.authorInitials, 'MG');
      expect(note.createdAt.isUtc, isFalse); // .toLocal() applied
    });

    test('malformed/missing fields fall back rather than throwing', () {
      final note = InternalNote.fromJson(const {});

      expect(note.id, -1);
      expect(note.body, isEmpty);
      expect(note.authorName, isEmpty);
      expect(note.authorInitials, isEmpty);
    });
  });

  group('ConversationRepository.notes', () {
    test('GETs the plain, non-paginated array from the correct path', () async {
      RequestOptions? captured;
      final (repository, _) = _repositoryReturning((options) {
        captured = options;
        return _json(
          '[{"id": 1, "body": "First note", "author_name": "Sam Agent", '
          '"author_initials": "SA", "created_at": "2026-08-21T04:00:00Z"}, '
          '{"id": 2, "body": "Second note", "author_name": "Mohamed Gad", '
          '"author_initials": "MG", "created_at": "2026-08-21T04:52:00Z"}]',
          200,
        );
      });

      final result = await repository.notes(42);

      expect(captured!.method, 'GET');
      expect(captured!.path, '/conversations/42/notes/');
      expect(result, hasLength(2));
      expect(result[0].body, 'First note');
      expect(result[1].body, 'Second note');
    });

    test(
      'notes for one conversation never leak into a call for another',
      () async {
        final (repository, adapter) = _repositoryReturning((options) {
          final id = options.path.split('/')[2];
          return _json('[{"id": 1, "body": "Only for $id"}]', 200);
        });

        final forOne = await repository.notes(1);
        final forTwo = await repository.notes(2);

        expect(adapter.received[0].path, '/conversations/1/notes/');
        expect(adapter.received[1].path, '/conversations/2/notes/');
        expect(forOne.single.body, 'Only for 1');
        expect(forTwo.single.body, 'Only for 2');
      },
    );
  });

  group('ConversationRepository.addNote', () {
    test(
      'POSTs {"body": ...} to the correct path and returns the note',
      () async {
        RequestOptions? captured;
        final (repository, _) = _repositoryReturning((options) {
          captured = options;
          return _json(
            '{"id": 9, "body": "New note", "author_name": "Sam Agent", '
            '"author_initials": "SA", "created_at": "2026-08-21T05:00:00Z"}',
            201,
          );
        });

        final note = await repository.addNote(7, 'New note');

        expect(captured!.method, 'POST');
        expect(captured!.path, '/conversations/7/notes/');
        expect(captured!.data, {'body': 'New note'});
        expect(note.id, 9);
        expect(note.body, 'New note');
      },
    );

    test('a server error throws, not a swallowed failure', () async {
      final (repository, _) = _repositoryReturning(
        (_) => _json(
          '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
          403,
        ),
      );

      expect(() => repository.addNote(7, 'x'), throwsA(isA<Exception>()));
    });
  });

  group('NotesController', () {
    ProviderContainer containerFor(
      ResponseBody Function(RequestOptions options) handler,
    ) {
      final (repository, _) = _repositoryReturning(handler);
      final container = ProviderContainer(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('build() loads notes scoped to the given conversation id', () async {
      final container = containerFor(
        (_) => _json(
          '[{"id": 1, "body": "Hello", "author_name": "Sam Agent", '
          '"author_initials": "SA", "created_at": "2026-08-21T04:00:00Z"}]',
          200,
        ),
      );

      final notes = await container.read(notesControllerProvider(10).future);

      expect(notes, hasLength(1));
      expect(notes.single.body, 'Hello');
    });

    test('addNote() appends the created note without a second GET — no '
        'unnecessary reload of the list it already has', () async {
      var getCount = 0;
      var postCount = 0;
      final (repository, _) = _repositoryReturning((options) {
        if (options.method == 'GET') {
          getCount += 1;
          return _json(
            '[{"id": 1, "body": "Existing note", "author_name": "Sam Agent", '
            '"author_initials": "SA", "created_at": "2026-08-21T04:00:00Z"}]',
            200,
          );
        }
        postCount += 1;
        return _json(
          '{"id": 2, "body": "New note", "author_name": "Sam Agent", '
          '"author_initials": "SA", "created_at": "2026-08-21T05:00:00Z"}',
          201,
        );
      });

      final container = ProviderContainer(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(notesControllerProvider(10).future);
      expect(getCount, 1);

      await container
          .read(notesControllerProvider(10).notifier)
          .addNote('New note');

      final notes = container.read(notesControllerProvider(10)).value!;
      expect(notes, hasLength(2));
      expect(notes.map((n) => n.body), ['Existing note', 'New note']);
      // The whole point of the append-in-place design: exactly one GET
      // (the initial load) and one POST — no refetch after the mutation.
      expect(getCount, 1);
      expect(postCount, 1);
    });

    test('addNote() failure throws (so the caller can preserve the draft) and '
        'leaves the existing list untouched', () async {
      final (repository, _) = _repositoryReturning((options) {
        if (options.method == 'GET') {
          return _json(
            '[{"id": 1, "body": "Existing note", "author_name": "Sam Agent", '
            '"author_initials": "SA", "created_at": "2026-08-21T04:00:00Z"}]',
            200,
          );
        }
        return _json(
          '{"error": {"code": "forbidden", "message": "Not allowed.", "details": {}}}',
          403,
        );
      });

      final container = ProviderContainer(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(notesControllerProvider(10).future);

      await expectLater(
        container.read(notesControllerProvider(10).notifier).addNote('x'),
        throwsA(isA<Exception>()),
      );

      final notes = container.read(notesControllerProvider(10)).value!;
      expect(notes, hasLength(1));
      expect(notes.single.body, 'Existing note');
    });

    test(
      'notes for different conversation ids are independent providers',
      () async {
        final (repository, _) = _repositoryReturning((options) {
          final id = options.path.split('/')[2];
          return _json('[{"id": 1, "body": "Only for $id"}]', 200);
        });

        final container = ProviderContainer(
          overrides: [
            conversationRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final forOne = await container.read(notesControllerProvider(1).future);
        final forTwo = await container.read(notesControllerProvider(2).future);

        expect(forOne.single.body, 'Only for 1');
        expect(forTwo.single.body, 'Only for 2');
      },
    );
  });
}
