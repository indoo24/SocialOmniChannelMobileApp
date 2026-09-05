import '../utils/json_safe.dart';
import 'conversation.dart';

/// Represents a customer-level grouping of conversations in the Inbox.
///
/// If a customer reaches out through multiple WhatsApp numbers/channels,
/// their threads are grouped under this single customer-level presentation,
/// while each underlying [Conversation] remains a distinct, independent
/// backend entity with its own ID, channel, and message history.
class CustomerConversationGroup {
  const CustomerConversationGroup({
    required this.groupKey,
    required this.customer,
    required this.provider,
    required this.conversations,
  });

  /// Unique stable grouping key.
  final String groupKey;

  /// The customer this group belongs to.
  final CustomerBrief customer;

  /// Channel provider (e.g. `'WHATSAPP'`, `'INSTAGRAM'`).
  final String provider;

  /// All individual backend conversations belonging to this customer group.
  final List<Conversation> conversations;

  /// Total number of conversations in this customer group.
  int get conversationCount => conversations.length;

  /// Whether this group contains more than one conversation.
  bool get isMultiConversation => conversations.length > 1;

  /// Total unread message count aggregated across all conversations in this group.
  int get unreadCount =>
      conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

  /// Number of conversations with unread messages.
  int get unreadConversations =>
      conversations.where((c) => c.unreadCount > 0).length;

  /// Whether this group has any unread messages.
  bool get isUnread => unreadCount > 0;

  /// Primary conversation (the one with the latest message activity).
  Conversation get primaryConversation {
    if (conversations.isEmpty) {
      throw StateError(
        'CustomerConversationGroup cannot have empty conversations',
      );
    }
    return conversations.first;
  }

  factory CustomerConversationGroup.fromJson(Map<String, dynamic> json) {
    final customer = CustomerBrief.fromJson(JsonSafe.asMap(json['customer']));
    final rawConvos = JsonSafe.parseList(
      json['conversations'],
      Conversation.fromJson,
    );
    final providers = JsonSafe.asStringList(json['providers']);
    final provider = providers.isNotEmpty
        ? providers.first
        : (rawConvos.isNotEmpty ? rawConvos.first.provider : 'WHATSAPP');

    return CustomerConversationGroup(
      groupKey: JsonSafe.asString(json['group_key']),
      customer: customer,
      provider: provider,
      conversations: rawConvos,
    );
  }

  /// Latest message activity timestamp across all conversations in this group.
  DateTime? get lastMessageAt => primaryConversation.lastMessageAt;

  /// Latest message preview across all conversations in this group.
  String get lastMessagePreview {
    for (final c in conversations) {
      if (c.lastMessagePreview.isNotEmpty) {
        return c.lastMessagePreview;
      }
    }
    return primaryConversation.lastMessagePreview;
  }

  /// Groups a flat list of conversations into [CustomerConversationGroup] items.
  ///
  /// Grouping rules:
  /// - Only WhatsApp conversations with a valid backend [customer.id > 0]
  ///   are grouped together by their stable customer identity.
  /// - Non-WhatsApp conversations (Instagram, Facebook, TikTok) or conversations
  ///   without a valid customer ID remain standalone to preserve channel isolation
  ///   and data safety.
  /// - Groups are ordered by latest message activity descending.
  static List<CustomerConversationGroup> groupConversations(
    List<Conversation> list,
  ) {
    if (list.isEmpty) return const [];

    final map = <String, List<Conversation>>{};

    for (final convo in list) {
      final key = _makeGroupKey(convo);
      (map[key] ??= []).add(convo);
    }

    final groups = <CustomerConversationGroup>[];

    for (final entry in map.entries) {
      final convos = entry.value;
      // Sort conversations within the group by latest activity first.
      convos.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.startedAt;
        final bTime = b.lastMessageAt ?? b.startedAt;
        if (aTime == null && bTime == null) return b.id.compareTo(a.id);
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      final primary = convos.first;

      groups.add(
        CustomerConversationGroup(
          groupKey: entry.key,
          customer: primary.customer,
          provider: primary.provider,
          conversations: List.unmodifiable(convos),
        ),
      );
    }

    // Sort groups so the one with the newest activity appears first.
    groups.sort((a, b) {
      final aTime = a.lastMessageAt ?? a.primaryConversation.startedAt;
      final bTime = b.lastMessageAt ?? b.primaryConversation.startedAt;
      if (aTime == null && bTime == null) {
        return b.primaryConversation.id.compareTo(a.primaryConversation.id);
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return groups;
  }

  static String _makeGroupKey(Conversation convo) {
    final provider = convo.provider.toUpperCase();
    final customerId = convo.customer.id;

    // Only WhatsApp conversations with a valid, stable customer ID are grouped.
    if (provider == 'WHATSAPP' && customerId > 0) {
      return 'WHATSAPP_$customerId';
    }

    // Otherwise, isolate by individual conversation ID.
    return '${provider}_convo_${convo.id}';
  }
}
