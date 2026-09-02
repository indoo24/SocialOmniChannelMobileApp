/// The authenticated employee, and the brief form embedded in other payloads.
///
/// [permissions] is a **mirror** of the backend's rules, sent by `/auth/me/`
/// purely so the UI can hide controls that would be rejected anyway. It is
/// never the authority: every action is re-checked server-side, and a client
/// that got this wrong would produce a clean 403, not an unauthorised write.
library;

import '../utils/json_safe.dart';

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
    id: JsonSafe.asInt(json['id'], fallback: -1),
    fullName: JsonSafe.asString(json['full_name']),
    initials: JsonSafe.asString(json['initials']),
    avatarUrl: JsonSafe.asString(json['avatar_url']),
    availability: JsonSafe.asString(json['availability'], fallback: 'OFFLINE'),
  );

  bool get isOnline => availability == 'ONLINE';
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    this.timezone = 'UTC',
  });

  final int id;
  final String name;
  final String timezone;

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
    id: JsonSafe.asInt(json['id'], fallback: -1),
    name: JsonSafe.asString(json['name']),
    timezone: JsonSafe.asString(json['timezone'], fallback: 'UTC'),
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
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
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
  final String firstName;
  final String lastName;
  final String phone;

  /// Permission slugs from the backend. Presentation gating only.
  final Set<String> permissions;

  /// ALL | TEAM | ASSIGNED. Informational — the backend already filters what
  /// this employee can see, so the app never applies it to a list itself.
  final String visibilityScope;

  final Organization? organization;

  factory Employee.fromJson(Map<String, dynamic> json) {
    final rawFirst = JsonSafe.asString(json['first_name']);
    final rawLast = JsonSafe.asString(json['last_name']);
    final rawFull = JsonSafe.asString(json['full_name']);

    String first = rawFirst;
    String last = rawLast;
    if (first.isEmpty && last.isEmpty && rawFull.isNotEmpty) {
      final parts = rawFull.trim().split(RegExp(r'\s+'));
      first = parts.first;
      last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final derivedFull = rawFull.isNotEmpty
        ? rawFull
        : (first.isNotEmpty ? '$first $last'.trim() : '');

    return Employee(
      id: JsonSafe.asInt(json['id'], fallback: -1),
      email: JsonSafe.asString(json['email']),
      fullName: derivedFull,
      initials: JsonSafe.asString(json['initials']),
      role: JsonSafe.asString(json['role'], fallback: 'AGENT'),
      roleDisplay: JsonSafe.asString(json['role_display']),
      availability: JsonSafe.asString(
        json['availability'],
        fallback: 'OFFLINE',
      ),
      avatarUrl: JsonSafe.asString(json['avatar_url']),
      title: JsonSafe.asString(json['title']),
      firstName: first,
      lastName: last,
      phone: JsonSafe.asString(json['phone']),
      // Permissions drive which controls the UI offers. A malformed list
      // must therefore fail closed — an empty set hides everything — rather
      // than throw, which would leave the employee unparseable and the
      // session unusable.
      permissions: JsonSafe.asObjectList(
        json['permissions'],
      ).map((p) => p.toString()).toSet(),
      visibilityScope: JsonSafe.asString(
        json['visibility_scope'],
        fallback: 'ASSIGNED',
      ),
      organization: json['organization'] is Map
          ? Organization.fromJson(JsonSafe.asMap(json['organization']))
          : null,
    );
  }

  bool can(String permission) => permissions.contains(permission);

  /// True for the ADMIN role specifically.
  ///
  /// Backs the four directory-management actions the backend documents as
  /// ADMIN only (add/edit/deactivate employee, add team). Those already carry
  /// a capability slug (`employee.manage`, `team.manage`) that `can()` can
  /// check, but the spec is explicit that the UI must also gate on the role
  /// itself rather than trust the capability mirror alone — see `Perm`'s doc
  /// comment on why that mirror is presentation-only in the first place.
  bool get isAdmin => role == 'ADMIN';

  Employee copyWith({
    String? availability,
    String? firstName,
    String? lastName,
    String? title,
    String? phone,
    String? fullName,
  }) => Employee(
    id: id,
    email: email,
    fullName: fullName ?? this.fullName,
    initials: initials,
    role: role,
    roleDisplay: roleDisplay,
    availability: availability ?? this.availability,
    avatarUrl: avatarUrl,
    title: title ?? this.title,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    phone: phone ?? this.phone,
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
  static const conversationRefreshIntelligence =
      'conversation.refresh_intelligence';
  static const intelligenceOverrideScore = 'intelligence.override_score';
  static const conversionReport = 'conversion.report';
  static const customerView = 'customer.view';
  static const customerManage = 'customer.manage';
  static const employeeView = 'employee.view';
  static const employeeManage = 'employee.manage';
  static const teamView = 'team.view';
  static const teamManage = 'team.manage';
  static const analyticsView = 'analytics.view';
  static const channelView = 'channel.view';
  static const channelManage = 'channel.manage';
  static const routingManage = 'routing.manage';

  /// Record an order, and review the customer details the analyzer extracted.
  /// Held by everyone who talks to customers — including agents, who are the
  /// ones taking the order. QA does not have it: reviewing history is not
  /// recording sales against it.
  static const orderManage = 'order.manage';
}
