import 'entities.dart';

/// Raised by EmergencyRepository.createSession when an active session already
/// exists (backend 409 CONFLICT_ACTIVE_SESSION + existing_session).
class SessionConflictException implements Exception {
  final SessionEntity existing;
  SessionConflictException(this.existing);
  @override
  String toString() => 'SessionConflictException(${existing.id})';
}

abstract class AuthRepository {
  /// Returns the OTP code in backend dev-mode (OTP_DEV_MODE), otherwise null.
  Future<String?> requestOtp(String phone);
  Future<UserEntity> verifyOtp(String phone, String code);
  Future<UserEntity> me();
  Future<void> logout();
}

abstract class ContactRepository {
  Future<List<ContactEntity>> list();
  Future<ContactEntity> create({required String name, required String phone, String? relationship});
  Future<ContactEntity> update(String id, {String? name, String? phone, String? relationship});
  Future<void> delete(String id);
}

abstract class EmergencyRepository {
  Future<SessionEntity> createSession({required String triggerType, String? deviceId});
  Future<SessionEntity> getSession(String id);
  Future<List<SessionEntity>> history();
  Future<List<EventEntity>> events(String id);
  Future<SessionEntity> resolve(String id);
  Future<SessionEntity> cancel(String id);
  Future<SessionEntity> reportCapability(String id, {required String locationCapability, required bool networkOk});
  Future<void> uploadLocations(String sessionId, List<Map<String, dynamic>> points);
}
