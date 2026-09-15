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
  Future<SavedReply> create({
    required String title,
    required String body,
    required String scope,
    String shortcut = '',
    String category = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/saved-replies/',
      body: {
        'title': title,
        'body': body,
        'scope': scope,
        if (shortcut.isNotEmpty) 'shortcut': shortcut,
        if (category.isNotEmpty) 'category': category,
      },
    );
    return SavedReply.fromJson(data);
  }

  /// `PATCH /saved-replies/{id}/`. Scope is immutable after creation, so it is
  /// never sent here.
  Future<SavedReply> update(
    int id, {
    required String title,
    required String body,
    String shortcut = '',
    String category = '',
  }) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/saved-replies/$id/',
      body: {
        'title': title,
        'body': body,
        'shortcut': shortcut,
        'category': category,
      },
    );
    return SavedReply.fromJson(data);
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
