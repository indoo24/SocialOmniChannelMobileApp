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

import '../../core/utils/json_safe.dart';

class SavedReply {
  const SavedReply({
    required this.id,
    required this.title,
    required this.body,
    this.shortcut = '',
    this.category = '',
    this.scope = 'organization',
    this.teamName,
  });

  final int id;
  final String title;

  /// Stored without the leading slash, lower-cased. Empty when none is set.
  final String shortcut;
  final String body;
  final String category;

  /// `personal`, `team` or `organization`.
  final String scope;
  final String? teamName;

  factory SavedReply.fromJson(Map<String, dynamic> json) => SavedReply(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    title: JsonSafe.asString(json['title']),
    body: JsonSafe.asString(json['body']),
    shortcut: JsonSafe.asString(json['shortcut']),
    category: JsonSafe.asString(json['category']),
    scope: JsonSafe.asString(json['scope'], fallback: 'organization'),
    teamName: json['team'] is Map
        ? JsonSafe.asString(JsonSafe.asMap(json['team'])['name'])
        : null,
  );
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
