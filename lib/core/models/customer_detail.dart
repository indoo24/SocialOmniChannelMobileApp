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

/// One channel account this customer has been reached on, from
/// `CustomerDetail.identities` (`GET /customers/{id}/`).
class CustomerIdentity {
  const CustomerIdentity({
    required this.id,
    required this.provider,
    required this.externalId,
    this.username = '',
    this.displayName = '',
    this.lastInteractionAt,
  });

  final int id;

  /// WHATSAPP · FACEBOOK · INSTAGRAM · TIKTOK · MOCK.
  final String provider;

  /// The account/phone/page identifier on that platform — a WhatsApp number,
  /// a Facebook PSID, an Instagram-scoped id. Always present; [username] and
  /// [displayName] are not, depending on what the platform hands back.
  final String externalId;
  final String username;
  final String displayName;
  final DateTime? lastInteractionAt;

  /// What to show as the account identifier: the human-readable handle when
  /// the platform gave one, else the raw id.
  String get accountLabel => username.isNotEmpty ? username : externalId;

  factory CustomerIdentity.fromJson(Map<String, dynamic> json) =>
      CustomerIdentity(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        provider: JsonSafe.asString(json['provider']),
        externalId: JsonSafe.asString(json['external_id']),
        username: JsonSafe.asString(json['username']),
        displayName: JsonSafe.asString(json['display_name']),
        lastInteractionAt: DateTime.tryParse(
          JsonSafe.asString(json['last_interaction_at']),
        )?.toLocal(),
      );
}

/// The WhatsApp number among [identities] as `+<digits>`, or empty.
///
/// The single place a phone number is read off a customer's identities, shared
/// by the profile (`CustomerDetail`) and the Customers list (`Customer`) so
/// both show the same number. The most recently active WhatsApp identity wins;
/// an id that is not a phone number is ignored.
String whatsappPhoneOf(Iterable<CustomerIdentity> identities) {
  final whatsapp = identities.where((i) => i.provider == 'WHATSAPP').toList()
    ..sort((a, b) {
      final at = a.lastInteractionAt;
      final bt = b.lastInteractionAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  for (final identity in whatsapp) {
    final digits = identity.externalId.replaceFirst(RegExp(r'^\+'), '');
    if (RegExp(r'^\d{7,15}$').hasMatch(digits)) return '+$digits';
  }
  return '';
}

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
    this.identities = const [],
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

  /// Distinct providers this customer has been seen on — derived from
  /// [identities]. Kept for callers that only need the channel type, not the
  /// per-account identifier.
  final List<String> providers;

  /// Every channel account this customer has been reached on, each with its
  /// own platform and account identifier — what the Customer Details
  /// screen's Channels section shows.
  final List<CustomerIdentity> identities;
  final DateTime? lastSeenAt;
  final DateTime? firstSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The phone number to show for this customer.
  ///
  /// A number already stored on the customer ([phone]) always wins — it is
  /// never overwritten. When the backend has none, the customer's WhatsApp
  /// identity already carries the number the customer wrote from
  /// (`identities[].external_id`, digits without a leading `+`), so it is
  /// reused here rather than asking an employee to type it again. Nothing is
  /// written back; this is a read-only fallback over data the backend sent.
  /// Empty when neither exists.
  String get displayPhone {
    if (phone.trim().isNotEmpty) return phone;
    return whatsappPhone;
  }

  /// The number of this customer's WhatsApp identity as `+<digits>`, or empty
  /// when they have none (or its id is not a phone number). With several
  /// WhatsApp identities the most recently active one is used.
  String get whatsappPhone => whatsappPhoneOf(identities);

  String get subtitle {
    if (email.isNotEmpty) return email;
    if (displayPhone.isNotEmpty) return displayPhone;
    if (city.isNotEmpty) return city;
    return '—';
  }

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    final identities = JsonSafe.asObjectList(json['identities'])
        .whereType<Map>()
        .map((i) => CustomerIdentity.fromJson(Map<String, dynamic>.from(i)))
        .toList();

    return CustomerDetail(
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
      providers: identities.map((i) => i.provider).toSet().toList(),
      identities: identities,
      lastSeenAt: _parseDate(json['last_seen_at']),
      firstSeenAt: _parseDate(json['first_seen_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
