/// Whether the device has a network interface up — Wi-Fi, mobile data,
/// ethernet or a VPN — from `connectivity_plus`.
///
/// This is only half the question. A phone on Wi-Fi with no internet behind
/// it, or one that cannot reach the backend, still reports a network here.
/// Whether the server answers is decided by sending the real request (see
/// `AuthController.restore`); this only says when sending it is pointless.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';

abstract class ConnectivityMonitor {
  /// True when some network interface is up, false when none is, null when
  /// the platform could not say.
  Future<bool?> hasNetwork();

  /// Whether a network interface is up, each time that changes. Repeats are
  /// dropped, so a Wi-Fi to mobile-data handover that never went down emits
  /// nothing.
  Stream<bool> get changes;
}

class PlatformConnectivityMonitor implements ConnectivityMonitor {
  PlatformConnectivityMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isUp(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool?> hasNetwork() async {
    try {
      return _isUp(await _connectivity.checkConnectivity());
    } catch (error) {
      // No plugin (a test, an unsupported platform): unknown, not offline.
      AppLog.debug('Connectivity', 'check failed: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_isUp).distinct();
}

final connectivityMonitorProvider = Provider<ConnectivityMonitor>(
  (ref) => PlatformConnectivityMonitor(),
);
