/// Data access for the directory, reporting and settings screens.
///
/// Every method is a thin call onto an endpoint the web client already uses.
/// No filtering and no permission logic: the backend decides what this employee
/// may see, and a second opinion here would only be a second thing to keep
/// correct. A role that may not call one of these gets a 403, which the UI
/// treats as an answer rather than an error — but it should rarely happen,
/// because the drawer does not offer the screen in the first place.
library;

import '../../core/api/api_client.dart';
import '../../core/models/conversation.dart';
import '../../core/models/customer_detail.dart';
import '../../core/models/directory.dart';
import '../../core/models/performance.dart';
import '../../core/models/routing_policy.dart';
import '../../core/utils/json_safe.dart';

class DirectoryRepository {
  DirectoryRepository(this._api);

  final ApiClient _api;

  Future<Paginated<DirectoryEmployee>> employees({
    String search = '',
    String? role,
    bool? isActive,
    int page = 1,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/employees/',
      query: {
        'page': page,
        'page_size': 50,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'role': ?role,
        'is_active': ?isActive,
      },
    );
    return Paginated.fromJson(data, DirectoryEmployee.fromJson);
  }

  /// Currently-available agents, unpaginated. Unlike filtering the paginated
  /// list client-side, this returns the whole set in one call — the right
  /// source for an "online now" toggle or a transfer picker.
  Future<List<DirectoryEmployee>> onlineEmployees() async {
    final data = await _api.get<dynamic>('/employees/online/');
    return JsonSafe.parseList(data, DirectoryEmployee.fromJson);
  }

  Future<Paginated<Team>> teams({int page = 1}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/teams/',
      query: {'page': page, 'page_size': 100},
    );
    return Paginated.fromJson(data, Team.fromJson);
  }

  Future<Paginated<Customer>> customers({
    String search = '',
    int page = 1,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/customers/',
      query: {
        'page': page,
        'page_size': 50,
        if (search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return Paginated.fromJson(data, Customer.fromJson);
  }

  /// The customer detail representation — adds `confirmed_purchase_count`
  /// and the full `facts` list that the list representation omits.
  Future<CustomerDetail> customerDetail(int customerId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/customers/$customerId/',
    );
    return CustomerDetail.fromJson(data);
  }

  /// `PATCH /customers/{id}/` — gated server-side on `customer.manage`.
  ///
  /// [fields] should only carry what actually changed; the caller decides
  /// that, this method just forwards it. The response is the full detail
  /// representation, the same shape [customerDetail] returns.
  Future<CustomerDetail> updateCustomer(
    int customerId,
    Map<String, dynamic> fields,
  ) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/customers/$customerId/',
      body: fields,
    );
    return CustomerDetail.fromJson(data);
  }

  /// `POST /employees/` — ADMIN only server-side (`employee.manage`).
  ///
  /// The response is richer than [DirectoryEmployee] models (working hours,
  /// work schedule, routing/capacity fields) but every field that type does
  /// read — id, name, role, availability, active state, teams — is present
  /// verbatim, so reusing it here is a safe subset rather than a guess.
  Future<DirectoryEmployee> createEmployee(Map<String, dynamic> fields) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/employees/',
      body: fields,
    );
    return DirectoryEmployee.fromJson(data);
  }

  /// `PATCH /employees/{id}/` — ADMIN only server-side (`employee.manage`).
  ///
  /// [fields] should only carry what the administrator actually changed —
  /// notably never a password the admin did not intend to reset.
  Future<DirectoryEmployee> updateEmployee(
    int employeeId,
    Map<String, dynamic> fields,
  ) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/employees/$employeeId/',
      body: fields,
    );
    return DirectoryEmployee.fromJson(data);
  }

  /// `DELETE /employees/{id}/` — ADMIN only server-side (`employee.manage`).
  ///
  /// Despite the verb, this deactivates rather than deletes: employees are
  /// referenced by messages, assignments and audit events, so the row stays
  /// and `is_active` flips to false. The backend refuses self-deactivation
  /// with a 400 rather than a 403 — surface that like any other validation
  /// error, not as a permission failure.
  Future<DirectoryEmployee> deactivateEmployee(int employeeId) async {
    final data = await _api.delete<Map<String, dynamic>>(
      '/employees/$employeeId/',
    );
    return DirectoryEmployee.fromJson(data);
  }

  /// `POST /teams/` — ADMIN only server-side (`team.manage`).
  ///
  /// `member_ids`/`leader_ids` outside the caller's organization are silently
  /// dropped by the backend rather than attached — nothing to reconcile here.
  /// [Team.fromJson] already reads a `members`/`leaders` object list (it only
  /// needs `full_name` off each for the leader-names line and a count for
  /// the rest), so the created-team response reuses it directly.
  Future<Team> createTeam(Map<String, dynamic> fields) async {
    final data = await _api.post<Map<String, dynamic>>('/teams/', body: fields);
    return Team.fromJson(data);
  }

  /// `PATCH /teams/{id}/` — ADMIN only server-side (`team.manage`).
  ///
  /// [fields] should only carry what the administrator actually changed.
  Future<Team> updateTeam(int teamId, Map<String, dynamic> fields) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/teams/$teamId/',
      body: fields,
    );
    return Team.fromJson(data);
  }

  /// `DELETE /teams/{id}/` — ADMIN only server-side (`team.manage`).
  ///
  /// Soft deactivates rather than deleting: teams are referenced by past
  /// conversations and assignments, so the row stays and `is_active` flips to false.
  Future<Team> deactivateTeam(int teamId) async {
    final data = await _api.delete<Map<String, dynamic>>('/teams/$teamId/');
    return Team.fromJson(data);
  }

  Future<Paginated<Conversation>> customerConversations(int customerId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/customers/$customerId/conversations/',
    );
    return Paginated.fromJson(data, Conversation.fromJson);
  }

  Future<Paginated<ChannelConnection>> channels() async {
    final data = await _api.get<Map<String, dynamic>>(
      '/channels/',
      query: {'page_size': 50},
    );
    return Paginated.fromJson(data, ChannelConnection.fromJson);
  }

  /// Stop showing this channel's conversations without disconnecting it.
  /// Ingestion and analysis continue; the inbox just stops surfacing them.
  Future<ChannelConnection> muteChannel(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/channels/$channelId/mute/',
    );
    return ChannelConnection.fromJson(data);
  }

  /// Return this channel to the inbox, backlog and all.
  Future<ChannelConnection> unmuteChannel(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/channels/$channelId/unmute/',
    );
    return ChannelConnection.fromJson(data);
  }

  /// Run the adapter's liveness check. Always 200 — read
  /// [ChannelTestResult.ok] rather than catching an exception.
  Future<ChannelTestResult> testChannel(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/channels/$channelId/test/',
    );
    return ChannelTestResult.fromJson(data);
  }

  /// The conversation-category taxonomy. Open to any active employee, and
  /// not paginated — every role that can see a conversation needs to be able
  /// to render and filter by its category.
  Future<List<ConversationCategory>> categories() async {
    final data = await _api.get<dynamic>('/categories/');
    return JsonSafe.parseList(data, ConversationCategory.fromJson);
  }

  Future<DashboardSummary> dashboard() async {
    final data = await _api.get<Map<String, dynamic>>('/dashboard/');
    return DashboardSummary.fromJson(data);
  }

  /// Volume per connected channel. Requires `analytics.view` server-side.
  Future<List<ChannelVolume>> channelVolume() async {
    final data = await _api.get<dynamic>('/dashboard/channels/');
    final rows = data is List ? data : const [];
    return rows
        .map((r) => ChannelVolume.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Per-employee performance for everyone the caller may report on.
  ///
  /// Open to every employee; the backend narrows the *result set* by role. An
  /// agent gets a one-row report about themselves, which is why this needs no
  /// permission check here — asking is always allowed and the answer is already
  /// scoped.
  Future<PerformanceReport> performance({int days = 14}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/dashboard/performance/',
      query: {'days': days},
    );
    return PerformanceReport.fromJson(data);
  }

  // ------------------------------------------------------------------ orders
  Future<List<Order>> conversationOrders(int conversationId) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/orders/',
      query: {'conversation': conversationId},
    );
    return Paginated.fromJson(data, Order.fromJson).results;
  }

  Future<List<Order>> customerOrders(int customerId) async {
    final data = await _api.get<dynamic>('/customers/$customerId/orders/');
    final rows = data is Map
        ? (data['results'] as List? ?? const [])
        : (data as List);
    return rows
        .map((o) => Order.fromJson(Map<String, dynamic>.from(o as Map)))
        .toList();
  }

  Future<Order> recordOrder({
    required int customerId,
    required List<Map<String, dynamic>> items,
    int? conversationId,
    String note = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/orders/',
      body: {
        'customer': customerId,
        'conversation': ?conversationId,
        'items': items,
        if (note.isNotEmpty) 'note': note,
      },
    );
    return Order.fromJson(data);
  }

  /// Attest that an order is real. The only route to CONFIRMED.
  Future<Order> confirmOrder(int orderId, {String note = ''}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/orders/$orderId/confirm/',
      body: {'note': note},
    );
    return Order.fromJson(data);
  }

  Future<Order> cancelOrder(int orderId, {bool refunded = false}) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/orders/$orderId/cancel/',
      body: {'refunded': refunded},
    );
    return Order.fromJson(data);
  }

  // ------------------------------------------------------- customer details
  Future<List<CustomerFact>> customerFacts(int customerId) async {
    final data = await _api.get<dynamic>('/customers/$customerId/facts/');
    final rows = data is List ? data : const [];
    return rows
        .map((f) => CustomerFact.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();
  }

  Future<CustomerFact> recordFact({
    required int customerId,
    required String key,
    required String value,
    int? conversationId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/customers/$customerId/facts/',
      body: {'key': key, 'value': value, 'conversation': ?conversationId},
    );
    return CustomerFact.fromJson(data);
  }

  /// Accept or turn down one of the analyzer's suggestions.
  ///
  /// [value] corrects it on the way through — the common case is right digits,
  /// wrong formatting, and forcing a reject plus a retype is how agents stop
  /// reviewing altogether.
  Future<CustomerFact> reviewFact({
    required int customerId,
    required int factId,
    required bool confirmed,
    String? value,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/customers/$customerId/facts/$factId/review/',
      body: {'confirmed': confirmed, 'value': ?value},
    );
    return CustomerFact.fromJson(data);
  }

  // ------------------------------------------------------- routing policy
  Future<RoutingPolicy> routingPolicy() async {
    final data = await _api.get<Map<String, dynamic>>('/routing/policy/');
    return RoutingPolicy.fromJson(data);
  }

  Future<RoutingPolicy> updateRoutingPolicy({
    bool? isEnabled,
    int? maxOpenChatsPerAgent,
    String? timezone,
  }) async {
    final body = <String, dynamic>{
      'is_enabled': ?isEnabled,
      'max_open_chats_per_agent': ?maxOpenChatsPerAgent,
      'timezone': ?timezone,
    };
    final data = await _api.patch<Map<String, dynamic>>(
      '/routing/policy/',
      body: body,
    );
    return RoutingPolicy.fromJson(data);
  }
}
