/// Reading saved replies.
///
/// Read-only on mobile: agents *use* saved replies here, and create or edit
/// them on the web (Settings → Saved replies). A `FutureProvider.family` keyed
/// by the search term — the same shape the read-only intelligence and
/// conversion sections use — so each search is its own cached read and a
/// cleared search returns to the unfiltered list instantly.
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
}

final savedRepliesRepositoryProvider = Provider<SavedRepliesRepository>(
  (ref) => SavedRepliesRepository(ref.watch(apiClientProvider)),
);

final savedRepliesProvider = FutureProvider.autoDispose
    .family<List<SavedReply>, String>((ref, search) {
      return ref.watch(savedRepliesRepositoryProvider).usable(search: search);
    });
