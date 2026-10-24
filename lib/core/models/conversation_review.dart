import '../utils/json_safe.dart';

/// Someone who may be asked to review a conversation: a row of
/// `GET /conversations/reviewers/` (an `EmployeeBrief`).
///
/// The server's list *is* the eligibility rule — active colleagues holding
/// `conversation.review`, the caller left out — so nothing here, a role name
/// or otherwise, decides who qualifies. The brief carries no role, which is
/// why none is shown.
class ReviewerCandidate {
  const ReviewerCandidate({
    required this.id,
    required this.fullName,
    this.initials = '',
    this.avatarUrl = '',
    this.availability = '',
  });

  final int id;
  final String fullName;
  final String initials;
  final String avatarUrl;
  final String availability;

  factory ReviewerCandidate.fromJson(Map<String, dynamic> json) =>
      ReviewerCandidate(
        id: JsonSafe.asInt(json['id'], fallback: -1),
        fullName: JsonSafe.asString(json['full_name']),
        initials: JsonSafe.asString(json['initials']),
        avatarUrl: JsonSafe.asString(json['avatar_url']),
        availability: JsonSafe.asString(json['availability']),
      );
}

/// A colleague's review of a conversation — the `review` object on a
/// conversation response.
///
/// A review is not an assignment: the conversation keeps its assignee, claim
/// and team, and anyone holding it can go on replying while it is open.
///
/// [status] is kept exactly as the server sent it. Its values are not
/// documented to the app yet, so nothing here decides behaviour from it.
class ConversationReview {
  const ConversationReview({
    required this.id,
    this.status = '',
    this.note = '',
    this.reviewerId,
    this.reviewerName = '',
    this.requestedById,
    this.requestedByName = '',
    this.requestedAt,
  });

  final int id;
  final String status;
  final String note;
  final int? reviewerId;
  final String reviewerName;
  final int? requestedById;
  final String requestedByName;
  final DateTime? requestedAt;

  /// Null for a missing or `null` review, and for anything that is not an
  /// object, so a conversation without a review parses as it always has.
  static ConversationReview? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = JsonSafe.asMap(json);
    final requestedAt = JsonSafe.asStringOrNull(map['requested_at']);
    return ConversationReview(
      id: JsonSafe.asInt(map['id'], fallback: -1),
      status: JsonSafe.asString(map['status']),
      note: JsonSafe.asString(map['note']),
      reviewerId: JsonSafe.asIntOrNull(map['reviewer_id']),
      reviewerName: JsonSafe.asString(map['reviewer_name']),
      requestedById: JsonSafe.asIntOrNull(map['requested_by_id']),
      requestedByName: JsonSafe.asString(map['requested_by_name']),
      requestedAt: requestedAt == null
          ? null
          : DateTime.tryParse(requestedAt)?.toLocal(),
    );
  }

  /// Whether [employeeId] is the colleague named as reviewer — the one
  /// person, besides an ADMIN, the server lets complete it.
  bool isReviewer(int employeeId) => reviewerId == employeeId;
}
