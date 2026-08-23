/// The customer detail representation, from `GET /customers/{id}/`.
///
/// Backed by `apps.customers.serializers.CustomerDetailSerializer`, which
/// extends the list serializer with `notes`, `facts`, `confirmed_purchase_count`,
/// `created_at` and `updated_at` — fields the list representation (`Customer`,
/// `directory.dart`) omits. Modeled as its own type rather than forced onto
/// `Customer`, the same "two payloads, two types" precedent Batch 1 (Batch 1
/// Intelligence) established for `IntelligenceBrief` vs `ConversationIntelligence`.
library;

import '../utils/json_safe.dart';
import 'performance.dart' show CustomerFact;

class CustomerDetail {
  const CustomerDetail({
    required this.id,
    required this.displayName,
    required this.lifecycleStage,
    required this.conversationCount,
    required this.confirmedPurchaseCount,
    required this.facts,
    this.avatarUrl = '',
    this.email = '',
    this.phone = '',
    this.city = '',
    this.country = '',
    this.preferredLanguage = '',
    this.notes = '',
    this.tags = '',
    this.providers = const [],
    this.lastSeenAt,
    this.firstSeenAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String displayName;
  final String lifecycleStage;
  final int conversationCount;

  /// Purchases an employee has actually confirmed for this customer — never
  /// includes unverified claims. Scenario has no payment data, so this is
  /// the only number here that means "a real sale."
  final int confirmedPurchaseCount;

  /// Everything the analyzer or an employee has recorded about this
  /// customer, confirmed and still-pending alike (see [CustomerFact.needsReview]).
  final List<CustomerFact> facts;

  final String avatarUrl;
  final String email;
  final String phone;
  final String city;
  final String country;
  final String preferredLanguage;
  final String notes;

  /// Free-text tags, as the backend stores them — a single string, not a list.
  final String tags;

  /// Channels this customer has been seen on.
  final List<String> providers;
  final DateTime? lastSeenAt;
  final DateTime? firstSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get subtitle {
    if (email.isNotEmpty) return email;
    if (phone.isNotEmpty) return phone;
    if (city.isNotEmpty) return city;
    return '—';
  }

  factory CustomerDetail.fromJson(Map<String, dynamic> json) => CustomerDetail(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    displayName: JsonSafe.asString(json['display_name']),
    lifecycleStage: JsonSafe.asString(
      json['lifecycle_stage'],
      fallback: 'UNKNOWN',
    ),
    conversationCount: JsonSafe.asInt(json['conversation_count']),
    confirmedPurchaseCount: JsonSafe.asInt(json['confirmed_purchase_count']),
    facts: JsonSafe.parseList(json['facts'], CustomerFact.fromJson),
    avatarUrl: JsonSafe.asString(json['avatar_url']),
    email: JsonSafe.asString(json['email']),
    phone: JsonSafe.asString(json['phone']),
    city: JsonSafe.asString(json['city']),
    country: JsonSafe.asString(json['country']),
    preferredLanguage: JsonSafe.asString(json['preferred_language']),
    notes: JsonSafe.asString(json['notes']),
    tags: JsonSafe.asString(json['tags']),
    providers: JsonSafe.asObjectList(json['identities'])
        .map((i) => i is Map ? JsonSafe.asString(i['provider']) : '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList(),
    lastSeenAt: _parseDate(json['last_seen_at']),
    firstSeenAt: _parseDate(json['first_seen_at']),
    createdAt: _parseDate(json['created_at']),
    updatedAt: _parseDate(json['updated_at']),
  );
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
