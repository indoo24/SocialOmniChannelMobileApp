/// Repository for in-app admin notifications.
///
/// Calls exact endpoints documented in OpenAPI spec:
/// - GET /api/notifications/
/// - GET /api/notifications/{id}/
/// - GET /api/notifications/unread-count/
/// - POST /api/notifications/{id}/read/
/// - POST /api/notifications/read-all/
library;

import '../../core/api/api_client.dart';
import '../../core/models/notification.dart';
import '../../core/utils/json_safe.dart';

class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  /// Fetches a paginated page of notifications.
  Future<PaginatedNotificationList> list({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? ordering,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/notifications/',
      query: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (ordering != null && ordering.isNotEmpty) 'ordering': ordering,
      },
    );
    return PaginatedNotificationList.fromJson(data);
  }

  /// Fetches a single notification by id.
  Future<NotificationModel> detail(int id) async {
    final data = await _api.get<Map<String, dynamic>>('/notifications/$id/');
    return NotificationModel.fromJson(data);
  }

  /// Fetches how many notifications are unread.
  Future<int> unreadCount() async {
    final data = await _api.get<Map<String, dynamic>>(
      '/notifications/unread-count/',
    );
    return JsonSafe.asInt(data['unread']);
  }

  /// Marks a single notification as read.
  Future<NotificationModel> markRead(int id) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/notifications/$id/read/',
    );
    return NotificationModel.fromJson(data);
  }

  /// Marks all notifications as read.
  Future<void> markAllRead() async {
    await _api.post<dynamic>('/notifications/read-all/');
  }
}
