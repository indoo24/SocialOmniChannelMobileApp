/// Device registration for push. `POST /api/devices/*` — see
/// `NOTIFICATIONS_INTEGRATION.md` §3.
///
/// There is no device *model*: every call here is fire-and-forget from the
/// app's point of view, and the backend row (`EmployeeDevice`) is never read
/// back into the client.
library;

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';

class DeviceRepository {
  DeviceRepository(this._api);

  final ApiClient _api;

  static void _log(String message) => debugPrint('[DeviceRepository] $message');

  /// Idempotent on `deviceIdentifier` — safe to call on every launch and
  /// again whenever the FCM token rotates.
  Future<void> register({
    required String deviceIdentifier,
    required String platform,
    String? pushToken,
  }) async {
    _log(
      'register() start — device: $deviceIdentifier, platform: $platform, '
      'hasToken: ${pushToken != null && pushToken.isNotEmpty}',
    );
    try {
      await _api.post<dynamic>(
        '/devices/register/',
        body: {
          'device_identifier': deviceIdentifier,
          'platform': platform,
          if (pushToken != null && pushToken.isNotEmpty)
            'push_token': pushToken,
        },
      );
      _log('register() succeeded — device: $deviceIdentifier');
    } on ApiException catch (error) {
      _log(
        'register() failed — device: $deviceIdentifier, '
        '${error.runtimeType}(status: ${error.statusCode}, code: '
        '${error.code}): ${error.message}',
      );
      rethrow;
    }
  }

  /// Cheap "still alive" ping. A `not_registered` error means the row is
  /// gone (e.g. the backend pruned a dead token) — the caller should
  /// [register] again.
  Future<void> heartbeat({
    required String deviceIdentifier,
    String? pushToken,
  }) async {
    _log('heartbeat() start — device: $deviceIdentifier');
    try {
      await _api.post<dynamic>(
        '/devices/heartbeat/',
        body: {
          'device_identifier': deviceIdentifier,
          if (pushToken != null && pushToken.isNotEmpty)
            'push_token': pushToken,
        },
      );
      _log('heartbeat() succeeded — device: $deviceIdentifier');
    } on ApiException catch (error) {
      _log(
        'heartbeat() failed — device: $deviceIdentifier, '
        '${error.runtimeType}(status: ${error.statusCode}, code: '
        '${error.code}): ${error.message}',
      );
      rethrow;
    }
  }

  /// Deactivates the device row so push stops. Never errors on an unknown
  /// device, so this is always safe to call from logout cleanup.
  Future<void> unregister(String deviceIdentifier) async {
    _log('unregister() start — device: $deviceIdentifier');
    try {
      await _api.post<dynamic>(
        '/devices/unregister/',
        body: {'device_identifier': deviceIdentifier},
      );
      _log('unregister() succeeded — device: $deviceIdentifier');
    } on ApiException catch (error) {
      _log(
        'unregister() failed — device: $deviceIdentifier, '
        '${error.runtimeType}(status: ${error.statusCode}, code: '
        '${error.code}): ${error.message}',
      );
      rethrow;
    }
  }
}
