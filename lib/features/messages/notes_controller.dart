/// Internal notes for one conversation.
///
/// `AsyncNotifier`, not a plain `FutureProvider` (the shape
/// `intelligence_providers.dart`/`conversion_providers.dart` use for
/// read-only sections): adding a note needs to update the held list
/// directly from the POST response rather than invalidating and refetching
/// — the backend already hands back the created note in full, so a second
/// round trip would only add latency for data this side already has.
///
/// Never sent to the customer, and never merged with `ConversationState`'s
/// messages — a note is scoped to this conversation only, the same way
/// `conversationConversionsProvider`/`conversationEventsProvider` are keyed
/// by conversation id and never bleed into another one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../core/providers.dart';

class NotesController extends AsyncNotifier<List<InternalNote>> {
  NotesController(this.conversationId);

  /// Riverpod 3 hands a family's argument to the constructor rather than to
  /// `build`, so the id is a field and `build` takes none — same shape as
  /// `ConversationController`.
  final int conversationId;

  @override
  Future<List<InternalNote>> build() {
    return ref.watch(conversationRepositoryProvider).notes(conversationId);
  }

  /// Posts a new note and appends the server's own record of it to the held
  /// list — no `ref.invalidate`/refetch, per the file doc comment.
  ///
  /// Throws on failure so the caller's composer can leave the typed text in
  /// place rather than losing it; this method does not catch `ApiException`
  /// itself, matching every other mutating action in this app (the UI layer
  /// is where `on ApiException catch` belongs).
  Future<void> addNote(String body) async {
    final note = await ref
        .read(conversationRepositoryProvider)
        .addNote(conversationId, body);
    final current = state.value ?? const <InternalNote>[];
    state = AsyncData([...current, note]);
  }
}

final notesControllerProvider =
    AsyncNotifierProvider.family<NotesController, List<InternalNote>, int>(
      NotesController.new,
    );
