/// How pages and refreshed heads are combined into the Inbox's loaded list.
///
/// Pure functions over the groups the server returned — nothing here fetches
/// or regroups, and only the display helper at the end ([pinnedFirst])
/// reorders what is shown. Each one keeps the
/// instance of every group it does not change, so a row that did not change
/// is not rebuilt.
///
/// Why duplicates can happen at all: the list is ordered by activity, so a new
/// message moves a conversation to the top and pushes everything below it one
/// place down. The last row of a page the agent already has then reappears as
/// the first row of the next one. Combining by group identity (and by the
/// conversations a group holds) makes that harmless.
library;

import '../../core/models/conversation_group.dart';

typedef Groups = List<CustomerConversationGroup>;

/// [loaded] followed by the rows of [incoming] it does not already hold.
///
/// A row is a duplicate when its [CustomerConversationGroup.identity] is
/// already present, or when every conversation it holds already is (the same
/// threads regrouped under another key). Duplicates inside [incoming] itself
/// are dropped too. [loaded] is not modified.
({Groups groups, int added, int duplicates}) appendDeduped(
  Groups loaded,
  Groups incoming,
) {
  if (incoming.isEmpty) {
    return (groups: loaded, added: 0, duplicates: 0);
  }
  final keys = <String>{for (final g in loaded) g.identity};
  final conversationIds = <int>{
    for (final g in loaded)
      for (final c in g.conversations) c.id,
  };

  final fresh = <CustomerConversationGroup>[];
  var duplicates = 0;
  for (final group in incoming) {
    final isNew =
        !keys.contains(group.identity) &&
        !group.conversations.every((c) => conversationIds.contains(c.id));
    if (!isNew) {
      duplicates++;
      continue;
    }
    keys.add(group.identity);
    conversationIds.addAll(group.conversations.map((c) => c.id));
    fresh.add(group);
  }
  if (fresh.isEmpty) return (groups: loaded, added: 0, duplicates: duplicates);
  return (
    groups: [...loaded, ...fresh],
    added: fresh.length,
    duplicates: duplicates,
  );
}

/// The refreshed top of the list, [head], placed first; the rest of [loaded]
/// follows in its existing order without anything [head] already carries.
///
/// A row that moved up from deeper in the list is therefore moved, not
/// duplicated, and a row pushed down by new activity stays where it falls.
/// Rows only [loaded] has are kept: the server's answer for the head says
/// nothing about whether they still exist, only a full reload does.
Groups mergeHead(Groups loaded, Groups head) {
  if (head.isEmpty) return loaded;
  final headKeys = <String>{for (final g in head) g.identity};
  final headConversationIds = <int>{
    for (final g in head)
      for (final c in g.conversations) c.id,
  };
  return [
    ...head,
    for (final g in loaded)
      if (!headKeys.contains(g.identity) &&
          !g.conversations.every((c) => headConversationIds.contains(c.id)))
        g,
  ];
}

/// [loaded] with each row [head] also carries replaced by its fresh version,
/// in the same position. Nothing is inserted, removed or moved, so what is on
/// screen does not shift under the agent.
Groups patchInPlace(Groups loaded, Groups head) {
  if (head.isEmpty || loaded.isEmpty) return loaded;
  final byKey = {for (final g in head) g.identity: g};
  var changed = false;
  final out = <CustomerConversationGroup>[
    for (final g in loaded)
      () {
        final fresh = byKey[g.identity];
        if (fresh == null) return g;
        changed = true;
        return fresh;
      }(),
  ];
  return changed ? out : loaded;
}

/// Whether [a] and [b] are the same rows in the same order.
bool sameGroups(Groups a, Groups b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].identity != b[i].identity) return false;
  }
  return true;
}

/// Whether the top of [loaded] differs from the server's [head] in a way
/// [patchInPlace] cannot show: a row [loaded] lacks, or the same rows in a
/// different order. That is what the "New activity" pill is for.
bool headDiffers(Groups loaded, Groups head) {
  if (head.isEmpty) return false;
  final n = head.length < loaded.length ? head.length : loaded.length;
  for (var i = 0; i < n; i++) {
    if (loaded[i].identity != head[i].identity) return true;
  }
  // Fewer loaded rows than the head: the rest are new to this list.
  return head.length > loaded.length;
}

/// [groups] as the inbox shows them: every row holding a pinned conversation
/// first, then the rest. Both parts keep the order they had, so this only
/// lifts pinned rows above the others — and changes nothing when the server
/// already sorts them first. It reorders rows the server returned for the
/// current filter and search; it never adds or removes one. The same list
/// when no row moves.
Groups pinnedFirst(Groups groups) {
  final pinned = <CustomerConversationGroup>[];
  final rest = <CustomerConversationGroup>[];
  var seenUnpinned = false;
  var moves = false;
  for (final group in groups) {
    if (group.hasPinned) {
      pinned.add(group);
      if (seenUnpinned) moves = true;
    } else {
      rest.add(group);
      seenUnpinned = true;
    }
  }
  return moves ? [...pinned, ...rest] : groups;
}
