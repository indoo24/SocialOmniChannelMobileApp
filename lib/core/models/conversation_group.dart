import '../utils/json_safe.dart';
import 'conversation.dart';
import 'message.dart';

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
    // The order of the threads *inside* a group is not part of the contract,
    // and the row's preview, tick and "primary" thread all come from the
    // first one — so make that the latest activity. Only this presentation
    // order is fixed up; which groups a page holds, their order and the
    // paging numbers stay exactly as the server sent them.
    final rawConvos = _newestFirst(
      JsonSafe.parseList(json['conversations'], Conversation.fromJson),
    );
    // A group with no threads has nothing to open and no primary
    // conversation. Refusing it here lets `Paginated.fromJson`'s per-row guard
    // drop that one row rather than crash the page that holds it.
    if (rawConvos.isEmpty) {
      throw const FormatException('conversation group has no conversations');
    }
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

  /// What makes two rows "the same group" when pages are combined: the
  /// server's [groupKey], or — for a row that arrived without one — its
  /// primary conversation, so a keyless row still cannot appear twice.
  String get identity => groupKey.isNotEmpty
      ? groupKey
      : '${provider}_convo_${primaryConversation.id}';

  /// This group holding exactly [conversations], keeping the server's key and
  /// customer. For removing a thread (access revoked) without refetching.
  CustomerConversationGroup withConversations(
    List<Conversation> conversations,
  ) => CustomerConversationGroup(
    groupKey: groupKey,
    customer: customer,
    provider: provider,
    conversations: List.unmodifiable(conversations),
  );

  /// This group with [update] applied to each of its conversations, keeping
  /// the server's key, customer and thread order. How a nested conversation is
  /// patched in place (read state, delivery tick) without refetching the page.
  CustomerConversationGroup mapConversations(
    Conversation Function(Conversation conversation) update,
  ) => CustomerConversationGroup(
    groupKey: groupKey,
    customer: customer,
    provider: provider,
    conversations: List.unmodifiable(conversations.map(update)),
  );

  /// Latest message activity timestamp across all conversations in this group.
  DateTime? get lastMessageAt => primaryConversation.lastMessageAt;

  /// The conversation [lastMessagePreview] actually reads from — same
  /// selection rule, kept as its own getter so [lastMessageDirection] and
  /// [lastMessageDeliveryStatus] describe that exact same message rather
  /// than defaulting back to [primaryConversation] independently.
  Conversation get _previewSource {
    for (final c in conversations) {
      if (c.lastMessagePreview.isNotEmpty ||
          c.lastMessageAttachments.isNotEmpty) {
        return c;
      }
    }
    return primaryConversation;
  }

  /// Latest message preview across all conversations in this group.
  String get lastMessagePreview => _previewSource.lastMessagePreview;

  /// Latest message attachments across all conversations in this group.
  List<MessageAttachment> get lastMessageAttachments =>
      _previewSource.lastMessageAttachments;

  /// Direction of the message [lastMessagePreview] is showing, for the
  /// group row's delivery tick.
  String get lastMessageDirection => _previewSource.lastMessageDirection;

  /// Delivery status of the message [lastMessagePreview] is showing.
  String get lastMessageDeliveryStatus =>
      _previewSource.lastMessageDeliveryStatus;

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
      convos.sort(_byRecency);

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

  /// Latest activity first; ties (and threads with no activity) by id, newest
  /// first, so the order is deterministic.
  static int _byRecency(Conversation a, Conversation b) {
    final aTime = a.lastMessageAt ?? a.startedAt;
    final bTime = b.lastMessageAt ?? b.startedAt;
    if (aTime == null && bTime == null) return b.id.compareTo(a.id);
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    final byTime = bTime.compareTo(aTime);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  static List<Conversation> _newestFirst(List<Conversation> conversations) =>
      [...conversations]..sort(_byRecency);

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
