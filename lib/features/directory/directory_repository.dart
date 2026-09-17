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
import '../../core/api/api_exception.dart';
import '../../core/models/conversation.dart';
import '../../core/models/customer_detail.dart';
import '../../core/models/customer_fields.dart';
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
    int? teamId,
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
        'team': ?teamId,
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
    Map<String, String> fieldFilter = const {},
    int page = 1,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/customers/',
      query: {
        'page': page,
        'page_size': 50,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        ...fieldFilter,
      },
    );
    return Paginated.fromJson(data, Customer.fromJson);
  }

  /// `GET /customers/export/` — the customers list as a UTF-8 CSV
  /// (BOM-prefixed for Excel), every matching row regardless of pagination.
  /// Needs `crm.export` and `customer.view`. Takes the same `search` and
  /// custom-field filters [customers] does — this app has no
  /// lifecycle/language/country filter UI yet, so there is nothing else to
  /// forward; adding those to [customers] later means adding them here too,
  /// not inventing a separate query.
  Future<List<int>> exportCustomersCsv({
    String search = '',
    Map<String, String> fieldFilter = const {},
  }) {
    return _api.getBytes(
      '/customers/export/',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        ...fieldFilter,
      },
    );
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
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/channels/',
        query: {'page_size': 50},
      );
      return Paginated.fromJson(data, ChannelConnection.fromJson);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        final data = await _api.get<Map<String, dynamic>>(
          '/conversations/channels/',
          query: {'page_size': 50},
        );
        return Paginated.fromJson(data, ChannelConnection.fromJson);
      }
      rethrow;
    }
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

  /// Permanently removes a disconnected channel.
  ///
  /// Requires `channel.manage`. The channel must already be disconnected
  /// (`status == 'DISCONNECTED'`). Conversations are preserved server-side
  /// (erased if empty, archived otherwise).
  Future<void> deleteChannel(int channelId) async {
    await _api.delete<dynamic>('/channels/$channelId/');
  }

  // ------------------------------------------------------- integrations
  // Disconnect destroys the stored credential; the connection row and every
  // conversation it carried survive, deactivated. `channel.manage` server-side
  // on every one of these. No request body — the id in the path is the only
  // input the endpoint takes.
  Future<ChannelConnectionState> disconnectInstagram(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/instagram/$channelId/disconnect/',
    );
    return ChannelConnectionState.fromJson(data);
  }

  Future<ChannelConnectionState> disconnectMeta(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/meta/$channelId/disconnect/',
    );
    return ChannelConnectionState.fromJson(data);
  }

  Future<ChannelConnectionState> disconnectTikTok(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/tiktok/$channelId/disconnect/',
    );
    return ChannelConnectionState.fromJson(data);
  }

  Future<ChannelConnectionState> disconnectWhatsApp(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/whatsapp/$channelId/disconnect/',
    );
    return ChannelConnectionState.fromJson(data);
  }

  /// Asks Meta whether this WhatsApp number can send/receive yet and updates
  /// the channel accordingly. A read — it changes nothing at Meta.
  Future<WhatsAppChannelStatus> checkWhatsAppStatus(int channelId) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/whatsapp/$channelId/check-status/',
    );
    return WhatsAppChannelStatus.fromJson(data);
  }

  /// Begins **Business Login for Instagram** — a different product from
  /// [connectMeta]'s Page-based flow. Returns the URL to open in a browser;
  /// Instagram redirects back to `/integrations/instagram/callback/` server-side.
  Future<ChannelAuthorizationUrl> authorizeInstagram() async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/instagram/authorize/',
    );
    return ChannelAuthorizationUrl.fromJson(data);
  }

  /// Begins the Meta OAuth dialog — covers Messenger and Page-linked
  /// Instagram. Returns the URL to open in a browser; Meta redirects back to
  /// `/integrations/meta/callback/` server-side.
  Future<ChannelAuthorizationUrl> connectMeta() async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/meta/connect/',
    );
    return ChannelAuthorizationUrl.fromJson(data);
  }

  /// Begins TikTok Business Account authorization. Returns the URL to open
  /// in a browser; TikTok redirects back to
  /// `/integrations/tiktok/account/callback/` server-side.
  Future<ChannelAuthorizationUrl> authorizeTikTok() async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/tiktok/authorize/',
    );
    return ChannelAuthorizationUrl.fromJson(data);
  }

  /// Begins WhatsApp Embedded Signup for a device that navigates the tab
  /// rather than opening a popup — the mobile-shaped counterpart of the
  /// web popup flow. Returns the URL to open in a browser; Meta redirects
  /// back to `/integrations/meta/callback/` server-side.
  ///
  /// [mode] determines the onboarding flow: `cloud_api` (registering a new
  /// number or moving one to Cloud API) or `coexistence` (keeping the existing
  /// WhatsApp Business mobile app and transferring history).
  Future<ChannelAuthorizationUrl> startWhatsAppEmbeddedSignupMobile({
    String mode = 'cloud_api',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/whatsapp/embedded-signup/mobile/start/',
      body: {'mode': mode},
    );
    return ChannelAuthorizationUrl.fromJson(data);
  }

  /// The manual alternative to Embedded Signup, for a number provisioned in
  /// the Meta dashboard. `POST /integrations/whatsapp/connect/` —
  /// `channel.manage` server-side. The token is verified against Graph
  /// before anything is stored.
  ///
  /// Used both to attach a new number ("Add another number") and — by
  /// resubmitting the same `phoneNumberId` with a freshly generated
  /// `accessToken` — to rotate an existing connection's credential ("Update
  /// token"). Swagger documents no separate update endpoint; a 409 here
  /// ("Already connected to another workspace, or connected through a
  /// different onboarding mode") is surfaced to the caller verbatim via
  /// [ApiException] rather than assumed away.
  Future<ConnectedChannel> connectWhatsApp({
    required String phoneNumberId,
    required String accessToken,
    String? wabaId,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/whatsapp/connect/',
      body: {
        'phone_number_id': phoneNumberId,
        'access_token': accessToken,
        'waba_id': ?wabaId,
      },
    );
    return ConnectedChannel.fromJson(data);
  }

  /// Instagram Login — a distinct API from the Page-based flow behind
  /// [connectMeta]/[authorizeInstagram] — attaches an account by an
  /// Instagram user token pasted from Meta's dashboard "Generate token"
  /// button. `POST /integrations/instagram/connect/` — `channel.manage`
  /// server-side. The account id is derived from the token, not supplied by
  /// the caller.
  Future<ConnectedChannel> connectInstagram({
    required String accessToken,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/integrations/instagram/connect/',
      body: {'access_token': accessToken},
    );
    return ConnectedChannel.fromJson(data);
  }

  /// The conversation-category taxonomy. Open to any active employee, and
  /// not paginated — every role that can see a conversation needs to be able
  /// to render and filter by its category.
  Future<List<ConversationCategory>> categories() async {
    final data = await _api.get<dynamic>('/categories/');
    return JsonSafe.parseList(data, ConversationCategory.fromJson);
  }

  Future<DashboardSummary> dashboard({
    String? preset,
    String? from,
    String? to,
  }) async {
    final query = <String, dynamic>{};
    if (from != null && to != null) {
      query['from'] = from;
      query['to'] = to;
    } else if (preset != null && preset.isNotEmpty) {
      query['preset'] = preset;
    }
    final data = await _api.get<Map<String, dynamic>>(
      '/dashboard/',
      query: query.isEmpty ? null : query,
    );
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
  ///
  /// Supports [preset] ('today', 'last_7_days', 'last_30_days', 'this_month',
  /// 'last_month') or custom [from] and [to] dates ('YYYY-MM-DD'). When supplied,
  /// date filters take precedence over [days] (which defaults to 14 when no
  /// date filter is passed).
  Future<PerformanceReport> performance({
    int? days,
    String? preset,
    String? from,
    String? to,
    int? employeeId,
  }) async {
    final query = <String, dynamic>{};
    if (from != null && to != null) {
      query['from'] = from;
      query['to'] = to;
    } else if (preset != null && preset.isNotEmpty) {
      query['preset'] = preset;
    } else if (days != null) {
      query['days'] = days;
    } else {
      query['days'] = 14;
    }
    if (employeeId != null) {
      query['employee'] = employeeId;
    }
    final data = await _api.get<Map<String, dynamic>>(
      '/dashboard/performance/',
      query: query.isEmpty ? null : query,
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

  /// `GET /orders/export/` — every order the caller may see, as a UTF-8 CSV
  /// (BOM-prefixed for Excel), regardless of pagination. Needs `crm.export`.
  /// Filtered to one customer's orders here — the same `customer` param the
  /// list/export endpoint documents, not a client-side filter over
  /// [customerOrders].
  Future<List<int>> exportOrdersCsv({required int customerId}) {
    return _api.getBytes('/orders/export/', query: {'customer': customerId});
  }

  /// [delivery] carries optional delivery fields keyed by their wire name
  /// (`city`, `address`, …). Blank values are not sent, so a quick order sends
  /// exactly the request it always did.
  Future<Order> recordOrder({
    required int customerId,
    required List<Map<String, dynamic>> items,
    int? conversationId,
    String note = '',
    Map<String, String> delivery = const {},
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/orders/',
      body: {
        'customer': customerId,
        'conversation': ?conversationId,
        'items': items,
        if (note.isNotEmpty) 'note': note,
        for (final field in delivery.entries)
          if (field.value.trim().isNotEmpty) field.key: field.value.trim(),
      },
    );
    return Order.fromJson(data);
  }

  /// Move an order's fulfilment. Changes neither its status nor revenue.
  Future<Order> updateOrderFulfilment(
    int orderId,
    String fulfilmentStatus,
  ) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/orders/$orderId/',
      body: {'fulfilment_status': fulfilmentStatus},
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

  Future<Order> cancelOrder(
    int orderId, {
    bool refunded = false,
    String reason = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/orders/$orderId/cancel/',
      body: {
        'refunded': refunded,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
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

  /// Every active custom field with this customer's value or null.
  Future<List<CustomerFieldRow>> customerFields(int customerId) async {
    final data = await _api.get<dynamic>('/customers/$customerId/fields/');
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((row) => CustomerFieldRow.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// `PATCH /customers/{id}/fields/` — gated server-side on `customer.manage`.
  ///
  /// [values] maps field keys to what the employee entered; null clears a
  /// field. The server validates every value and saves none if one is refused,
  /// naming each refused key under `details['values']`.
  Future<List<CustomerFieldRow>> saveCustomerFields(
    int customerId,
    Map<String, Object?> values,
  ) async {
    final data = await _api.patch<dynamic>(
      '/customers/$customerId/fields/',
      body: {'values': values},
    );
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((row) => CustomerFieldRow.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  // ------------------------------------------------------ field definitions

  /// `GET /customer-fields/` — every field the organization defined, in
  /// display order. Active only unless [includeInactive]. Needs
  /// `customer.view`.
  Future<List<CustomerFieldDefinition>> customerFieldDefinitions({
    bool includeInactive = false,
  }) async {
    final data = await _api.get<List<dynamic>>(
      '/customer-fields/',
      query: {if (includeInactive) 'include_inactive': true},
    );
    return data
        .whereType<Map>()
        .map((row) => CustomerFieldDefinition.fromJson(JsonSafe.asMap(row)))
        .toList();
  }

  /// `POST /customer-fields/` — needs `customer_field.manage`. [key] is
  /// derived from [label] server-side when omitted, and is fixed thereafter.
  Future<CustomerFieldDefinition> createCustomerFieldDefinition({
    required String label,
    required String fieldType,
    String? key,
    bool required = false,
    String helpText = '',
    String placeholder = '',
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/customer-fields/',
      body: {
        'label': label,
        'field_type': fieldType,
        'key': ?key,
        'required': required,
        'help_text': helpText,
        'placeholder': placeholder,
      },
    );
    return CustomerFieldDefinition.fromJson(data);
  }

  /// `PATCH /customer-fields/{id}/` — needs `customer_field.manage`. The key
  /// is never sent: it cannot change once the field exists. Send
  /// `isActive: false` to turn a field off without deleting its values.
  Future<CustomerFieldDefinition> updateCustomerFieldDefinition(
    int id, {
    String? label,
    String? fieldType,
    bool? required,
    bool? isActive,
    String? helpText,
    String? placeholder,
  }) async {
    final data = await _api.patch<Map<String, dynamic>>(
      '/customer-fields/$id/',
      body: {
        'label': ?label,
        'field_type': ?fieldType,
        'required': ?required,
        'is_active': ?isActive,
        'help_text': ?helpText,
        'placeholder': ?placeholder,
      },
    );
    return CustomerFieldDefinition.fromJson(data);
  }

  /// `POST /customer-fields/reorder/` — needs `customer_field.manage`.
  /// [order] lists field ids in their new order; fields left out keep their
  /// current relative order after the listed ones. Returns every field,
  /// active or not, in the new order.
  Future<List<CustomerFieldDefinition>> reorderCustomerFieldDefinitions(
    List<int> order,
  ) async {
    final data = await _api.post<List<dynamic>>(
      '/customer-fields/reorder/',
      body: {'order': order},
    );
    return data
        .whereType<Map>()
        .map((row) => CustomerFieldDefinition.fromJson(JsonSafe.asMap(row)))
        .toList();
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
    int? firstResponseSlaSeconds,
    bool? stickyConversationOwnership,
    int? escalationMaxHops,
    bool? strictResponsibility,
  }) async {
    final body = <String, dynamic>{
      'is_enabled': ?isEnabled,
      'max_open_chats_per_agent': ?maxOpenChatsPerAgent,
      'timezone': ?timezone,
      'first_response_sla_seconds': ?firstResponseSlaSeconds,
      'sticky_conversation_ownership': ?stickyConversationOwnership,
      'escalation_max_hops': ?escalationMaxHops,
      'strict_responsibility': ?strictResponsibility,
    };
    final data = await _api.patch<Map<String, dynamic>>(
      '/routing/policy/',
      body: body,
    );
    return RoutingPolicy.fromJson(data);
  }

  /// `GET /api/routing/responsibilities/` — every rule in the organization,
  /// active and retired. Requires `routing.manage`. There is no team filter
  /// server-side, so a caller that wants one team's rules (the team form's
  /// use case) filters the returned list itself by `RoutingResponsibility.teamId`.
  Future<List<RoutingResponsibility>> routingResponsibilities() async {
    final data = await _api.get<List<dynamic>>('/routing/responsibilities/');
    return data
        .whereType<Map>()
        .map((row) => RoutingResponsibility.fromJson(JsonSafe.asMap(row)))
        .toList();
  }
}
