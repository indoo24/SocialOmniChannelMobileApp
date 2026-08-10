/// Employee performance, orders, and captured customer details.
///
/// Three fields here carry a caveat the UI must respect, because getting them
/// wrong turns a missing measurement into a claim about a person:
///
/// * [HoursBreakdown.hasSessionData] — false means "not recorded", not "worked
///   nothing". Render the difference.
/// * [EmployeePerformance.averageResponseSeconds] and friends are nullable.
///   Null is "no replies yet", which is not the same as "answered instantly".
/// * [Order.isClaim] — recorded but unattested. Never revenue.
library;

class PlatformVolume {
  const PlatformVolume({
    required this.provider,
    required this.messages,
    required this.customers,
    required this.conversations,
  });

  final String provider;
  final int messages;
  final int customers;
  final int conversations;

  factory PlatformVolume.fromJson(Map<String, dynamic> json) => PlatformVolume(
        provider: (json['provider'] as String?) ?? '',
        messages: (json['messages'] as num?)?.toInt() ?? 0,
        customers: (json['customers'] as num?)?.toInt() ?? 0,
        conversations: (json['conversations'] as num?)?.toInt() ?? 0,
      );
}

class HoursBreakdown {
  const HoursBreakdown({
    required this.scheduledSeconds,
    required this.onlineSeconds,
    required this.awaySeconds,
    required this.breakSeconds,
    required this.hasSessionData,
    this.adherence,
  });

  final int scheduledSeconds;
  final int onlineSeconds;
  final int awaySeconds;
  final int breakSeconds;

  /// False when the availability log has nothing for this window. **Not** the
  /// same as zero hours worked.
  final bool hasSessionData;

  /// Online over scheduled. Null when there is nothing to compare against — an
  /// employee with no roster is unmeasured, not 0% adherent.
  final double? adherence;

  factory HoursBreakdown.fromJson(Map<String, dynamic> json) => HoursBreakdown(
        scheduledSeconds: (json['scheduled_seconds'] as num?)?.toInt() ?? 0,
        onlineSeconds: (json['online_seconds'] as num?)?.toInt() ?? 0,
        awaySeconds: (json['away_seconds'] as num?)?.toInt() ?? 0,
        breakSeconds: (json['break_seconds'] as num?)?.toInt() ?? 0,
        hasSessionData: (json['has_session_data'] as bool?) ?? false,
        adherence: (json['adherence'] as num?)?.toDouble(),
      );
}

class EmployeePerformance {
  const EmployeePerformance({
    required this.employeeId,
    required this.fullName,
    required this.initials,
    required this.role,
    required this.availability,
    required this.conversationsHandled,
    required this.conversationsResolved,
    required this.responsesCounted,
    required this.messagesSent,
    required this.customersServed,
    required this.scoredConversations,
    required this.platforms,
    required this.hours,
    required this.ordersRecorded,
    required this.ordersConfirmed,
    required this.confirmedOrderValue,
    required this.currency,
    this.avatarUrl = '',
    this.averageResponseSeconds,
    this.medianResponseSeconds,
    this.firstResponseAverageSeconds,
    this.leadScoreAtAssignment,
    this.leadScoreNow,
    this.leadScoreLift,
    this.leadScoreLiftPercent,
  });

  final int employeeId;
  final String fullName;
  final String initials;
  final String role;
  final String availability;
  final String avatarUrl;

  final int conversationsHandled;
  final int conversationsResolved;

  /// Null until this employee has sent a reply that ended a customer wait.
  final double? averageResponseSeconds;
  final int? medianResponseSeconds;
  final double? firstResponseAverageSeconds;
  final int responsesCounted;

  final double? leadScoreAtAssignment;
  final double? leadScoreNow;

  /// Change in lead score while they held the conversation. Movement, not proof
  /// of causation — a lead can warm up on its own.
  final double? leadScoreLift;

  /// Null when the baseline was zero: a lead that went 0 to 40 did not improve
  /// by "infinity percent".
  final double? leadScoreLiftPercent;
  final int scoredConversations;

  final int messagesSent;

  /// Distinct customers, so one person reachable on two channels counts once.
  final int customersServed;
  final List<PlatformVolume> platforms;

  final HoursBreakdown hours;

  final int ordersRecorded;
  final int ordersConfirmed;

  /// Decimal string. Only CONFIRMED orders contribute.
  final String confirmedOrderValue;
  final String currency;

  factory EmployeePerformance.fromJson(Map<String, dynamic> json) {
    int at(String key) => (json[key] as num?)?.toInt() ?? 0;
    double? maybe(String key) => (json[key] as num?)?.toDouble();

    return EmployeePerformance(
      employeeId: json['employee_id'] as int,
      fullName: (json['full_name'] as String?) ?? '',
      initials: (json['initials'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'AGENT',
      availability: (json['availability'] as String?) ?? 'OFFLINE',
      avatarUrl: (json['avatar_url'] as String?) ?? '',
      conversationsHandled: at('conversations_handled'),
      conversationsResolved: at('conversations_resolved'),
      averageResponseSeconds: maybe('average_response_seconds'),
      medianResponseSeconds: (json['median_response_seconds'] as num?)?.toInt(),
      firstResponseAverageSeconds: maybe('first_response_average_seconds'),
      responsesCounted: at('responses_counted'),
      leadScoreAtAssignment: maybe('lead_score_at_assignment'),
      leadScoreNow: maybe('lead_score_now'),
      leadScoreLift: maybe('lead_score_lift'),
      leadScoreLiftPercent: maybe('lead_score_lift_percent'),
      scoredConversations: at('scored_conversations'),
      messagesSent: at('messages_sent'),
      customersServed: at('customers_served'),
      platforms: ((json['platforms'] as List?) ?? const [])
          .map((p) => PlatformVolume.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      hours: HoursBreakdown.fromJson(
        Map<String, dynamic>.from((json['hours'] as Map?) ?? const {}),
      ),
      ordersRecorded: at('orders_recorded'),
      ordersConfirmed: at('orders_confirmed'),
      confirmedOrderValue: (json['confirmed_order_value'] as String?) ?? '0.00',
      currency: (json['currency'] as String?) ?? '',
    );
  }

  /// Whether there is anything worth rendering. A brand-new account showing a
  /// card of dashes reads as a bad review rather than an empty one.
  bool get hasActivity =>
      responsesCounted > 0 ||
      messagesSent > 0 ||
      conversationsHandled > 0 ||
      hours.hasSessionData;
}

class PerformanceReport {
  const PerformanceReport({required this.days, required this.results});

  final int days;
  final List<EmployeePerformance> results;

  factory PerformanceReport.fromJson(Map<String, dynamic> json) => PerformanceReport(
        days: ((json['window'] as Map?)?['days'] as num?)?.toInt() ?? 14,
        results: ((json['results'] as List?) ?? const [])
            .map((r) => EmployeePerformance.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(),
      );
}

// --------------------------------------------------------------------------- //
// Orders
// --------------------------------------------------------------------------- //
class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final int id;
  final String productName;
  final int quantity;
  final String unitPrice;
  final String lineTotal;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as int,
        productName: (json['product_name'] as String?) ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unit_price'] as String?) ?? '0.00',
        lineTotal: (json['line_total'] as String?) ?? '0.00',
      );
}

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.status,
    required this.statusDisplay,
    required this.source,
    required this.isClaim,
    required this.totalAmount,
    required this.currency,
    required this.items,
    this.conversationId,
    this.recordedByName = '',
    this.confirmedByName = '',
    this.evidence = '',
    this.note = '',
  });

  final int id;
  final int customerId;
  final int? conversationId;

  /// SUGGESTED · RECORDED · CONFIRMED · CANCELLED · REFUNDED.
  final String status;
  final String statusDisplay;
  final String source;

  /// Recorded but unattested. Never presented as revenue.
  final bool isClaim;

  final String totalAmount;
  final String currency;
  final List<OrderItem> items;
  final String recordedByName;
  final String confirmedByName;

  /// The customer's own words behind an analyzer suggestion, so a reviewing
  /// agent judges the extraction rather than the extractor.
  final String evidence;
  final String note;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as int,
        customerId: (json['customer'] as num?)?.toInt() ?? 0,
        conversationId: (json['conversation'] as num?)?.toInt(),
        status: (json['status'] as String?) ?? 'RECORDED',
        statusDisplay: (json['status_display'] as String?) ?? '',
        source: (json['source'] as String?) ?? 'EMPLOYEE',
        isClaim: (json['is_claim'] as bool?) ?? true,
        totalAmount: (json['total_amount'] as String?) ?? '0.00',
        currency: (json['currency'] as String?) ?? '',
        items: ((json['items'] as List?) ?? const [])
            .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i as Map)))
            .toList(),
        recordedByName: (json['recorded_by_name'] as String?) ?? '',
        confirmedByName: (json['confirmed_by_name'] as String?) ?? '',
        evidence: (json['evidence'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
      );

  bool get isSuggestion => status == 'SUGGESTED';
  bool get isConfirmed => status == 'CONFIRMED';
}

// --------------------------------------------------------------------------- //
// Captured customer details
// --------------------------------------------------------------------------- //
class CustomerFact {
  const CustomerFact({
    required this.id,
    required this.key,
    required this.value,
    required this.confidence,
    required this.source,
    required this.status,
    required this.needsReview,
    this.reviewedByName = '',
  });

  final int id;
  final String key;
  final String value;
  final double confidence;
  final String source;

  /// SUGGESTED · CONFIRMED · REJECTED.
  final String status;

  /// True while the analyzer's guess is still waiting on a human. Render these
  /// in a review tray, never mixed into the profile.
  final bool needsReview;
  final String reviewedByName;

  factory CustomerFact.fromJson(Map<String, dynamic> json) => CustomerFact(
        id: json['id'] as int,
        key: (json['key'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        source: (json['source'] as String?) ?? 'ANALYZER',
        status: (json['status'] as String?) ?? 'CONFIRMED',
        needsReview: (json['needs_review'] as bool?) ?? false,
        reviewedByName: (json['reviewed_by_name'] as String?) ?? '',
      );
}
