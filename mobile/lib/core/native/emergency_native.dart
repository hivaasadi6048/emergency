import 'package:flutter/services.dart';

/// Temporary bridge to the Kotlin native layer (Phase 1 PoC channel).
/// Phase 5 replaces this with a formal Pigeon-typed API (change-log C-013).
class EmergencyNative {
  static const _channel = MethodChannel('emergency.poc/native');

  Future<Map<String, dynamic>> _call(String method) async {
    try {
      final raw = await _channel.invokeMethod(method);
      return Map<String, dynamic>.from(raw as Map);
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  Future<Map<String, dynamic>> startLocationService() => _call('startEmergencyLocationService');

  Future<Map<String, dynamic>> requestPermissions() => _call('requestPermissions');

  Future<Map<String, dynamic>> stopLocationService() => _call('stopEmergencyLocationService');

  Future<Map<String, dynamic>> status() => _call('getLocationServiceStatus');

  /// C-017: the FULL un-acked native queue (stable capture-time uuids) —
  /// the upload source of truth; survives process restarts.
  Future<List<Map<String, dynamic>>> pendingPoints() async {
    try {
      final raw = await _channel.invokeMethod('getPendingPoints');
      return (raw as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// C-017: acks server-confirmed points so they leave the native queue.
  /// Returns how many were drained (0 also on channel failure — the points
  /// simply stay pending and get re-uploaded idempotently next tick).
  Future<int> ackUploadedPoints(List<String> uuids) async {
    if (uuids.isEmpty) return 0;
    try {
      final raw = await _channel.invokeMethod('ackUploadedPoints', {'uuids': uuids});
      return raw is num ? raw.toInt() : 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<Map<String, dynamic>> permissions() async {
    final state = await status();
    final perms = state['permissions'];
    return perms is Map ? Map<String, dynamic>.from(perms) : const {};
  }
}
