/// Employees screen role/team/status filters, matching the query parameters
/// the web Employees screen sends to `GET /api/employees/`.
///
/// One combined filter state, mirroring `ConversationFilters` for the
/// inbox — `role`, `team` and `is_active` are independent, server-applied
/// filters (see `docs/api/openapi.yaml`), not something this app re-derives
/// client-side.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every role the endpoint's `role` filter accepts — the same five values
/// `employee_form_sheet.dart`'s own role picker offers, since a filter that
/// listed a sixth value would just be offering something the backend refuses.
const kEmployeeRoles = ['ADMIN', 'SUPERVISOR', 'TEAM_LEADER', 'AGENT', 'QA'];

@immutable
class EmployeeFilters {
  const EmployeeFilters({this.role, this.teamId, this.isActive});

  /// One of [kEmployeeRoles], or `null` for "All roles".
  final String? role;

  /// A team id from `teamsProvider`, or `null` for "All teams".
  final int? teamId;

  /// `true`/`false` for Active/Inactive, or `null` for "All".
  final bool? isActive;

  bool get isEmpty => role == null && teamId == null && isActive == null;

  EmployeeFilters copyWith({
    String? role,
    bool clearRole = false,
    int? teamId,
    bool clearTeamId = false,
    bool? isActive,
    bool clearIsActive = false,
  }) => EmployeeFilters(
    role: clearRole ? null : (role ?? this.role),
    teamId: clearTeamId ? null : (teamId ?? this.teamId),
    isActive: clearIsActive ? null : (isActive ?? this.isActive),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmployeeFilters &&
          runtimeType == other.runtimeType &&
          role == other.role &&
          teamId == other.teamId &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(role, teamId, isActive);
}

class EmployeeFiltersController extends Notifier<EmployeeFilters> {
  @override
  EmployeeFilters build() => const EmployeeFilters();

  void setRole(String? role) =>
      state = state.copyWith(role: role, clearRole: role == null);

  void setTeamId(int? teamId) =>
      state = state.copyWith(teamId: teamId, clearTeamId: teamId == null);

  void setIsActive(bool? isActive) => state = state.copyWith(
    isActive: isActive,
    clearIsActive: isActive == null,
  );

  void reset() => state = const EmployeeFilters();
}

/// The Employees screen's active role/team/status filters. Survives screen
/// refresh/reload like `employeeSearchProvider` does — neither is
/// `autoDispose`, so pulling to refresh or navigating away and back keeps
/// whatever was selected.
final employeeFiltersProvider =
    NotifierProvider<EmployeeFiltersController, EmployeeFilters>(
      EmployeeFiltersController.new,
    );
