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

  Future<Map<String, dynamic>> permissions() async {
    final state = await status();
    final perms = state['permissions'];
    return perms is Map ? Map<String, dynamic>.from(perms) : const {};
  }
}
