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
import '../../core/models/directory.dart';

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

  Future<Paginated<Team>> teams({int page = 1}) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/teams/',
      query: {'page': page, 'page_size': 100},
    );
    return Paginated.fromJson(data, Team.fromJson);
  }

  Future<Paginated<Customer>> customers({String search = '', int page = 1}) async {
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
}
