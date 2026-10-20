/// Reading and managing saved replies.
///
/// `usable()` is what the composer picker calls: active replies only, most
/// specific scope first, exactly what an agent may insert. `manageable()` is
/// the Settings admin screen's read instead — it needs the replies this
/// employee may *edit*, deactivated ones included, which is a different
/// question the server answers with `?manageable=true` rather than something
/// derived client-side from the same list.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/conversation.dart';
import '../../core/providers.dart';
import 'saved_reply.dart';

class SavedRepliesRepository {
  const SavedRepliesRepository(this._api);

  final ApiClient _api;

  /// The replies the signed-in employee may insert: their personal ones, their
  /// teams', and the organization's — most specific first. Filtered and
  /// ordered by the server.
  Future<List<SavedReply>> usable({String search = ''}) async {
    final term = search.trim();
    final data = await _api.get<Map<String, dynamic>>(
      '/saved-replies/',
      query: {'page_size': 100, if (term.isNotEmpty) 'search': term},
    );
    return Paginated<SavedReply>.fromJson(data, SavedReply.fromJson).results;
  }

  /// The Settings admin list: replies this employee may edit, including
  /// deactivated ones. `GET /saved-replies/?manageable=true`.
  Future<List<SavedReply>> manageable() async {
    final data = await _api.get<Map<String, dynamic>>(
      '/saved-replies/',
      query: {'page_size': 100, 'manageable': true},
    );
    return Paginated<SavedReply>.fromJson(data, SavedReply.fromJson).results;
  }

  /// `POST /saved-replies/`. [scope] is `personal` or `organization` — `team`
  /// scope exists server-side but the mobile form does not offer it, matching
  /// the web Settings screen's own Add dialog. `scope` and `teamId` are
  /// write-once: the server does not accept them on update.
  ///
  /// [categoryId] places it in that `SavedReplyCategory`; none when null.
  Future<SavedReply> create({
    required String title,
    required String body,
    required String scope,
    String shortcut = '',
    int? categoryId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/saved-replies/',
      body: {
        'title': title,
        'body': body,
        'scope': scope,
        if (shortcut.isNotEmpty) 'shortcut': shortcut,
        'category_id': ?categoryId,
      },
    );
    return SavedReply.fromJson(data);
  }

  /// `PATCH /saved-replies/{id}/`. Scope is immutable after creation, so it is
  /// never sent here.
  ///
  /// The category is sent only with [changeCategory]: then [categoryId]
  /// moves the reply there, or out of every category when null. Otherwise
  /// it is left as the server has it — a reply whose category is only a
  /// name keeps it.
  Future<SavedReply> update(
    int id, {
    required String title,
    required String body,
    String shortcut = '',
    bool changeCategory = false,
    int? categoryId,
  }) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/saved-replies/$id/',
      body: {
        'title': title,
        'body': body,
        'shortcut': shortcut,
        if (changeCategory) 'category_id': categoryId,
      },
    );
    return SavedReply.fromJson(data);
  }

  // -- categories -------------------------------------------------------------

  /// `GET /saved-reply-categories/`, in their saved order ([position]).
  Future<List<SavedReplyCategory>> categories() async {
    final data = await _api.get<Map<String, dynamic>>(
      '/saved-reply-categories/',
      query: {'page_size': 100},
    );
    return _inOrder(
      Paginated<SavedReplyCategory>.fromJson(
        data,
        SavedReplyCategory.fromJson,
      ).results,
    );
  }

  /// `POST /saved-reply-categories/` `{name}`. Needs `saved_reply.manage`.
  Future<SavedReplyCategory> createCategory(String name) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/saved-reply-categories/',
      body: {'name': name},
    );
    return SavedReplyCategory.fromJson(data);
  }

  /// `PATCH /saved-reply-categories/{id}/` `{name}`.
  Future<SavedReplyCategory> renameCategory(int id, String name) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/saved-reply-categories/$id/',
      body: {'name': name},
    );
    return SavedReplyCategory.fromJson(data);
  }

  /// `DELETE /saved-reply-categories/{id}/` → 204. Its replies are kept and
  /// become uncategorized.
  Future<void> deleteCategory(int id) =>
      _api.delete<dynamic>('/saved-reply-categories/$id/');

  /// `POST /saved-reply-categories/reorder/` `{ids}` — every category, in
  /// the new order. Answers with the categories as saved.
  Future<List<SavedReplyCategory>> reorderCategories(List<int> ids) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/saved-reply-categories/reorder/',
      body: {'ids': ids},
    );
    return _inOrder(
      Paginated<SavedReplyCategory>.fromJson(
        data,
        SavedReplyCategory.fromJson,
      ).results,
    );
  }

  /// By [SavedReplyCategory.position]; the server's order breaks ties.
  static List<SavedReplyCategory> _inOrder(List<SavedReplyCategory> list) {
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byPosition = a.$2.position.compareTo(b.$2.position);
        return byPosition != 0 ? byPosition : a.$1.compareTo(b.$1);
      });
    return [for (final (_, c) in indexed) c];
  }

  /// `DELETE /saved-replies/{id}/` — deactivates rather than deletes and
  /// releases the shortcut; the server answers 200 with the now-inactive
  /// reply, not 204.
  Future<SavedReply> deactivate(int id) async {
    final data = await _api.delete<Map<String, dynamic>>('/saved-replies/$id/');
    return SavedReply.fromJson(data);
  }
}

final savedRepliesRepositoryProvider = Provider<SavedRepliesRepository>(
  (ref) => SavedRepliesRepository(ref.watch(apiClientProvider)),
);

final savedRepliesProvider = FutureProvider.autoDispose
    .family<List<SavedReply>, String>((ref, search) {
      return ref.watch(savedRepliesRepositoryProvider).usable(search: search);
    });

/// The Settings admin tab's list — see [SavedRepliesRepository.manageable].
final manageableSavedRepliesProvider = FutureProvider<List<SavedReply>>((ref) {
  return ref.watch(savedRepliesRepositoryProvider).manageable();
});

/// The saved-reply categories in their saved order, and the changes to them.
///
/// Every change waits for the server and shows its answer, except a reorder,
/// which shows the new order at once and, if the server refuses it, shows
/// the order the server actually has (re-read; the previous one if even
/// that fails). One reorder at a time: a second while one is saving is
/// refused rather than raced.
class SavedReplyCategoriesController
    extends AsyncNotifier<List<SavedReplyCategory>> {
  @override
  Future<List<SavedReplyCategory>> build() =>
      ref.watch(savedRepliesRepositoryProvider).categories();

  SavedRepliesRepository get _repository =>
      ref.read(savedRepliesRepositoryProvider);

  List<SavedReplyCategory> get _current => state.value ?? const [];

  bool _reordering = false;

  /// A reorder is being saved.
  bool get isReordering => _reordering;

  Future<SavedReplyCategory> create(String name) async {
    final created = await _repository.createCategory(name);
    state = AsyncData([
      for (final c in _current)
        if (c.id != created.id) c,
      created,
    ]);
    return created;
  }

  Future<void> rename(int id, String name) async {
    final renamed = await _repository.renameCategory(id, name);
    state = AsyncData([for (final c in _current) c.id == id ? renamed : c]);
    // Replies carry their category's name.
    _refreshReplies();
  }

  /// Deletes the category; its replies become uncategorized, never deleted.
  Future<void> delete(int id) async {
    await _repository.deleteCategory(id);
    state = AsyncData([
      for (final c in _current)
        if (c.id != id) c,
    ]);
    _refreshReplies();
  }

  /// Saves [ids] — every category, in the new order. Resolves to false
  /// without sending anything when a reorder is already being saved.
  Future<bool> reorder(List<int> ids) async {
    if (_reordering) return false;
    final previous = _current;
    final byId = {for (final c in previous) c.id: c};
    _reordering = true;
    state = AsyncData([for (final id in ids) ?byId[id]]);
    try {
      state = AsyncData(await _repository.reorderCategories(ids));
      // Replies carry their category's position, which orders the composer.
      _refreshReplies();
      return true;
    } catch (_) {
      try {
        state = AsyncData(await _repository.categories());
      } catch (_) {
        state = AsyncData(previous);
      }
      rethrow;
    } finally {
      _reordering = false;
    }
  }

  void _refreshReplies() {
    ref.invalidate(manageableSavedRepliesProvider);
    ref.invalidate(savedRepliesProvider);
  }
}

final savedReplyCategoriesProvider =
    AsyncNotifierProvider<
      SavedReplyCategoriesController,
      List<SavedReplyCategory>
    >(SavedReplyCategoriesController.new);
