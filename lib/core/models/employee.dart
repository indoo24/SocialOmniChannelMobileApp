/// The authenticated employee, and the brief form embedded in other payloads.
///
/// [permissions] is a **mirror** of the backend's rules, sent by `/auth/me/`
/// purely so the UI can hide controls that would be rejected anyway. It is
/// never the authority: every action is re-checked server-side, and a client
/// that got this wrong would produce a clean 403, not an unauthorised write.
library;

class EmployeeBrief {
  const EmployeeBrief({
    required this.id,
    required this.fullName,
    required this.initials,
    this.avatarUrl = '',
    this.availability = 'OFFLINE',
  });

  final int id;
  final String fullName;
  final String initials;
  final String avatarUrl;
  final String availability;

  factory EmployeeBrief.fromJson(Map<String, dynamic> json) => EmployeeBrief(
        id: json['id'] as int,
        fullName: (json['full_name'] as String?) ?? '',
        initials: (json['initials'] as String?) ?? '',
        avatarUrl: (json['avatar_url'] as String?) ?? '',
        availability: (json['availability'] as String?) ?? 'OFFLINE',
      );

  bool get isOnline => availability == 'ONLINE';
}

class Organization {
  const Organization({required this.id, required this.name, this.timezone = 'UTC'});

  final int id;
  final String name;
  final String timezone;

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as int,
        name: (json['name'] as String?) ?? '',
        timezone: (json['timezone'] as String?) ?? 'UTC',
      );
}

class Employee {
  const Employee({
    required this.id,
    required this.email,
    required this.fullName,
    required this.initials,
    required this.role,
    required this.roleDisplay,
    required this.availability,
    required this.permissions,
    required this.visibilityScope,
    this.avatarUrl = '',
    this.title = '',
    this.organization,
  });

  final int id;
  final String email;
  final String fullName;
  final String initials;
  final String role;
  final String roleDisplay;
  final String availability;
  final String avatarUrl;
  final String title;

  /// Permission slugs from the backend. Presentation gating only.
  final Set<String> permissions;

  /// ALL | TEAM | ASSIGNED. Informational — the backend already filters what
  /// this employee can see, so the app never applies it to a list itself.
  final String visibilityScope;

  final Organization? organization;

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: json['id'] as int,
        email: (json['email'] as String?) ?? '',
        fullName: (json['full_name'] as String?) ?? '',
        initials: (json['initials'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'AGENT',
        roleDisplay: (json['role_display'] as String?) ?? '',
        availability: (json['availability'] as String?) ?? 'OFFLINE',
        avatarUrl: (json['avatar_url'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        permissions: ((json['permissions'] as List?) ?? const [])
            .map((p) => p.toString())
            .toSet(),
        visibilityScope: (json['visibility_scope'] as String?) ?? 'ASSIGNED',
        organization: json['organization'] is Map
            ? Organization.fromJson(
                Map<String, dynamic>.from(json['organization'] as Map))
            : null,
      );

  bool can(String permission) => permissions.contains(permission);

  Employee copyWith({String? availability}) => Employee(
        id: id,
        email: email,
        fullName: fullName,
        initials: initials,
        role: role,
        roleDisplay: roleDisplay,
        availability: availability ?? this.availability,
        avatarUrl: avatarUrl,
        title: title,
        permissions: permissions,
        visibilityScope: visibilityScope,
        organization: organization,
      );
}

/// Permission slugs, mirroring `apps/core/permissions.py`.
///
/// String constants rather than an enum so an unknown permission added by a
/// newer backend degrades to "not held" instead of failing to parse.
class Perm {
  const Perm._();
  static const conversationView = 'conversation.view';
  static const conversationReply = 'conversation.reply';
  static const conversationNote = 'conversation.note';
  static const conversationAssignSelf = 'conversation.assign_self';
  static const conversationAssignAny = 'conversation.assign_any';
  static const conversationChangeStatus = 'conversation.change_status';
  static const conversationChangePriority = 'conversation.change_priority';
  static const conversationChangeCategory = 'conversation.change_category';
  static const conversationDeleteMessage = 'conversation.delete_message';
  static const conversationConfirmPurchase = 'conversation.confirm_purchase';
  static const customerView = 'customer.view';
  static const employeeView = 'employee.view';
  static const teamView = 'team.view';
  static const analyticsView = 'analytics.view';
  static const channelView = 'channel.view';
  static const channelManage = 'channel.manage';
}
