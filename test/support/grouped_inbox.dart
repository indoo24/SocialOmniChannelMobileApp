/// Test fixtures for `GET /conversations/grouped/`, the inbox's data source.
///
/// Most inbox tests describe a fixture as flat conversation rows (the shape of
/// `GET /conversations/`). [groupedRows] and [groupedEnvelope] turn those into
/// what the grouped endpoint answers, applying the documented rule: WhatsApp
/// threads of one customer share a group; every other thread is its own group.
/// The rows keep their order, and a group sits where its first thread was.
library;

import 'dart:convert';

import 'package:scenario_mobile/core/models/conversation.dart';
import 'package:scenario_mobile/core/models/conversation_group.dart';
import 'package:scenario_mobile/features/conversations/inbox_controller.dart';

/// The `group_key` the mobile grouping and the backend both use.
String groupKeyOf(Map<String, dynamic> conversation) {
  final provider = '${conversation['provider'] ?? ''}'.toUpperCase();
  final customer = conversation['customer'];
  final customerId = customer is Map ? (customer['id'] as num?)?.toInt() : null;
  if (provider == 'WHATSAPP' && customerId != null && customerId > 0) {
    return 'WHATSAPP_$customerId';
  }
  return '${provider}_convo_${conversation['id']}';
}

/// One `ConversationGroup` per group of [rows].
List<Map<String, dynamic>> groupedRows(List<dynamic> rows) {
  final order = <String>[];
  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final row in rows.whereType<Map>()) {
    final conversation = Map<String, dynamic>.from(row);
    final key = groupKeyOf(conversation);
    if (!byKey.containsKey(key)) order.add(key);
    (byKey[key] ??= []).add(conversation);
  }
  return [
    for (final key in order)
      {
        'group_key': key,
        'customer': byKey[key]!.first['customer'],
        'conversation_count': byKey[key]!.length,
        'providers': {
          for (final c in byKey[key]!) '${c['provider']}',
        }.toList(),
        'conversations': byKey[key],
      },
  ];
}

/// [flat] (`{count, next, previous, results: [conversation…]}`) as the grouped
/// endpoint's page: `results` become groups. `count` is the number of groups
/// when the fixture's `count` merely counted its own rows.
Map<String, dynamic> groupedEnvelope(Map<String, dynamic> flat) {
  final rows = (flat['results'] as List?) ?? const [];
  final groups = groupedRows(rows);
  final count = flat['count'];
  return {
    ...flat,
    'count': count is int && count != rows.length ? count : groups.length,
    'results': groups,
  };
}

/// [groupedEnvelope] for a JSON string fixture.
String groupedBody(String flatJson) =>
    jsonEncode(groupedEnvelope(jsonDecode(flatJson) as Map<String, dynamic>));

/// Whether [path] is the grouped endpoint the inbox now reads.
bool isGroupedPath(String path) => path.contains('/conversations/grouped/');

/// An [InboxState] holding [conversations] as the groups a grouped page would
/// carry (WhatsApp threads of one customer together, the rest standalone).
InboxState inboxStateOf({
  required List<Conversation> conversations,
  int total = 0,
}) => InboxState(
  groups: CustomerConversationGroup.groupConversations(conversations),
  total: total,
);
