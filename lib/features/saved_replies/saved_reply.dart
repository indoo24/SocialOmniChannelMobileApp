/// Saved replies — reusable text an agent inserts into the composer.
///
/// **Not WhatsApp templates.** A template is approved by Meta and sent by name;
/// a saved reply is text stored in OmniChannel that the composer pastes into
/// the reply box. The agent edits it and presses Send, which goes through
/// `ConversationRepository.reply()` exactly like anything typed by hand, under
/// every rule an ordinary reply is under. Nothing in this feature sends.
///
/// The scope and editing rules live on the server (`apps.saved_replies`); the
/// app only reads the replies it is allowed to use.
library;

import '../../core/models/message.dart';
import '../../core/utils/json_safe.dart';

class SavedReply {
  const SavedReply({
    required this.id,
    required this.title,
    required this.body,
    this.shortcut = '',
    this.category = '',
    this.categoryId,
    this.position = 0,
    this.categoryPosition,
    this.scope = 'organization',
    this.teamId,
    this.teamName,
    this.isActive = true,
    this.canEdit = false,
    this.assets = const [],
  });

  final int id;
  final String title;

  /// Stored without the leading slash, lower-cased. Empty when none is set.
  final String shortcut;
  final String body;

  /// The category's name, as the server reports it. Kept for replies whose
  /// category is only a name (no [categoryId]).
  final String category;

  /// The `SavedReplyCategory` this reply belongs to; null when it has none.
  final int? categoryId;

  /// The reply's place among its category's replies, as the server keeps it.
  /// Read-only: no endpoint changes it.
  final int position;

  /// Its category's place in the category order; null without a category.
  final int? categoryPosition;

  /// `personal`, `team` or `organization`.
  final String scope;
  final int? teamId;
  final String? teamName;

  /// Deactivated replies are never deleted server-side — `DELETE` just turns
  /// this off and releases the shortcut. Only ever `false` on a response from
  /// `manageable: true` list/create/update calls; the composer's own
  /// `usable()` read never returns an inactive one to begin with.
  final bool isActive;

  /// Server-computed: true when this employee may edit or deactivate this
  /// specific reply (owns it, leads its team, or holds `saved_reply.manage`).
  /// Authoritative — never re-derive this client-side.
  final bool canEdit;

  /// The reply's file, as `assets[]` (`POST /saved-reply-assets/` replaces
  /// it, so there is at most one). Empty for a text-only reply.
  final List<SavedReplyAsset> assets;

  /// Its file, if it has one.
  SavedReplyAsset? get asset => assets.isEmpty ? null : assets.first;

  factory SavedReply.fromJson(Map<String, dynamic> json) => SavedReply(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    title: JsonSafe.asString(json['title']),
    body: JsonSafe.asString(json['body']),
    shortcut: JsonSafe.asString(json['shortcut']),
    category: JsonSafe.asString(json['category']),
    categoryId: JsonSafe.asIntOrNull(json['category_id']),
    position: JsonSafe.asInt(json['position']),
    categoryPosition: JsonSafe.asIntOrNull(json['category_position']),
    scope: JsonSafe.asString(json['scope'], fallback: 'organization'),
    teamId: json['team'] is Map
        ? JsonSafe.asIntOrNull(JsonSafe.asMap(json['team'])['id'])
        : null,
    teamName: json['team'] is Map
        ? JsonSafe.asString(JsonSafe.asMap(json['team'])['name'])
        : null,
    isActive: JsonSafe.asBool(json['is_active'], fallback: true),
    canEdit: JsonSafe.asBool(json['can_edit']),
    assets: JsonSafe.parseList(json['assets'], SavedReplyAsset.fromJson),
  );
}

/// A saved reply's file: `SavedReplyAsset`. Its bytes are at [contentUrl]
/// (`/saved-reply-assets/{public_id}/content/`, session-authenticated); in a
/// conversation it is copied into a draft by
/// `POST /conversations/{id}/attachments/from-saved-reply/`, never re-sent
/// from the phone.
class SavedReplyAsset {
  const SavedReplyAsset({
    required this.id,
    this.publicId = '',
    this.attachmentType = 'FILE',
    this.mimeType = '',
    this.originalFilename = '',
    this.sizeBytes,
    this.isVoice = false,
    this.durationMs,
    this.contentUrl = '',
  });

  final int id;
  final String publicId;

  /// `IMAGE`, `VIDEO`, `AUDIO` or `FILE` — the server's reading of the
  /// bytes, not of the name.
  final String attachmentType;
  final String mimeType;
  final String originalFilename;
  final int? sizeBytes;

  /// A recorded voice message, sent as a voice note.
  final bool isVoice;

  /// From `metadata.duration_ms`, when the server records one.
  final int? durationMs;
  final String contentUrl;

  factory SavedReplyAsset.fromJson(Map<String, dynamic> json) {
    final metadata = JsonSafe.asMap(json['metadata']);
    return SavedReplyAsset(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      publicId: JsonSafe.asString(json['public_id']),
      attachmentType: JsonSafe.asString(
        json['attachment_type'],
        fallback: 'FILE',
      ).toUpperCase(),
      mimeType: JsonSafe.asString(json['mime_type']),
      originalFilename: JsonSafe.asString(json['original_filename']),
      sizeBytes: JsonSafe.asIntOrNull(json['size_bytes']),
      isVoice: JsonSafe.asBool(json['is_voice']),
      durationMs: JsonSafe.asIntOrNull(metadata['duration_ms']),
      contentUrl: JsonSafe.asString(json['content_url']),
    );
  }

  /// As the app's attachment widgets show one.
  MessageAttachment toAttachment() => MessageAttachment(
    type: isVoice ? 'AUDIO' : attachmentType,
    url: contentUrl,
    fileName: originalFilename,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    durationMs: durationMs,
  );
}

/// A saved-reply category: `GET /saved-reply-categories/`. Its [position] is
/// the order the categories, and the replies grouped under them, are shown
/// in; it is set with `POST /saved-reply-categories/reorder/`.
class SavedReplyCategory {
  const SavedReplyCategory({
    required this.id,
    required this.name,
    this.position = 0,
    this.replyCount = 0,
  });

  final int id;
  final String name;
  final int position;

  /// How many replies the server counts in it — all of them, not only the
  /// ones this employee can see or edit.
  final int replyCount;

  factory SavedReplyCategory.fromJson(Map<String, dynamic> json) =>
      SavedReplyCategory(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        name: JsonSafe.asString(json['name']),
        position: JsonSafe.asInt(json['position']),
        replyCount: JsonSafe.asInt(json['reply_count']),
      );

  SavedReplyCategory copyWith({String? name}) => SavedReplyCategory(
    id: id,
    name: name ?? this.name,
    position: position,
    replyCount: replyCount,
  );
}

/// One category's replies on the Settings screen; [category] is null for the
/// uncategorized ones.
class SavedReplySection {
  const SavedReplySection(this.category, this.replies);

  final SavedReplyCategory? category;
  final List<SavedReply> replies;
}

/// [replies] under [categories], in the categories' order, every category
/// listed even when it has none here; then, if any, the uncategorized ones.
///
/// A reply goes under its `category_id`. One with only a category name is
/// matched to a category of that name (ignoring case and spaces). One whose
/// category is not among [categories] — deleted, or newer than the list —
/// is listed with the uncategorized ones rather than dropped. Within a
/// section the server's [SavedReply.position] orders them; its list order
/// breaks ties.
List<SavedReplySection> sectionSavedReplies(
  List<SavedReplyCategory> categories,
  List<SavedReply> replies,
) {
  final ids = {for (final c in categories) c.id};
  final byName = <String, int>{};
  for (final c in categories) {
    byName.putIfAbsent(c.name.trim().toLowerCase(), () => c.id);
  }
  final buckets = <int?, List<SavedReply>>{};
  for (final reply in replies) {
    final id = reply.categoryId;
    final key = id != null
        ? (ids.contains(id) ? id : null)
        : byName[reply.category.trim().toLowerCase()];
    (buckets[key] ??= []).add(reply);
  }
  final uncategorized = buckets[null] ?? const <SavedReply>[];
  return [
    for (final c in categories)
      SavedReplySection(c, savedRepliesInOrder(buckets[c.id] ?? const [])),
    if (uncategorized.isNotEmpty)
      SavedReplySection(null, savedRepliesInOrder(uncategorized)),
  ];
}

/// [replies] by [SavedReply.position], keeping their order where it ties.
List<SavedReply> savedRepliesInOrder(List<SavedReply> replies) {
  final indexed = replies.indexed.toList()
    ..sort((a, b) {
      final byPosition = a.$2.position.compareTo(b.$2.position);
      return byPosition != 0 ? byPosition : a.$1.compareTo(b.$1);
    });
  return [for (final (_, reply) in indexed) reply];
}

/// The backend's sentinel for a customer whose name the platform withheld.
/// Mirrors `UNKNOWN_CUSTOMER` in `apps/conversations/services.py`.
const unknownCustomerSentinel = 'Unknown customer';

final _variable = RegExp(r'\{\{\s*(customer_name|agent_name)\s*\}\}');

/// Fill `{{customer_name}}` and `{{agent_name}}` from what the screen already
/// has.
///
/// A value that is not known is **removed and the sentence tidied** — never
/// left as a literal `{{customer_name}}` for the customer to read, and never
/// replaced with a placeholder such as "Unknown customer". Any other `{{…}}`
/// is left as written. Same rules as the web composer's `renderSavedReply`.
String renderSavedReply(
  String body, {
  String? customerName,
  String? agentName,
}) {
  final values = <String, String>{
    'customer_name': (customerName ?? '').trim() == unknownCustomerSentinel
        ? ''
        : (customerName ?? '').trim(),
    'agent_name': (agentName ?? '').trim(),
  };

  var removed = false;
  final filled = body.replaceAllMapped(_variable, (match) {
    final value = values[match.group(1)] ?? '';
    if (value.isEmpty) removed = true;
    return value;
  });
  if (!removed) return filled;

  return filled
      .split('\n')
      .map(
        (line) => line
            .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
            .replaceAllMapped(
              RegExp(r'[ \t]+([,.!?;:،؛؟])'),
              (m) => m.group(1)!,
            )
            .trim(),
      )
      .join('\n');
}

/// Insert [text] into [value] at its selection (replacing any selected text),
/// returning the new text and the caret offset just after the insertion.
({String text, int caret}) insertAtSelection(
  String value,
  int selectionStart,
  int selectionEnd,
  String text,
) {
  final length = value.length;
  // A controller that has never been focused reports -1 for both ends.
  final start = selectionStart < 0 ? length : selectionStart.clamp(0, length);
  final end = selectionEnd < 0 ? length : selectionEnd.clamp(start, length);
  final next = value.substring(0, start) + text + value.substring(end);
  return (text: next, caret: start + text.length);
}
