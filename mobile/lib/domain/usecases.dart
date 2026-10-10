import 'entities.dart';
import 'repositories.dart';

/// SOS entry point: creates a session and transparently adopts the backend's
/// active session when one already exists (duplicate SOS never fails the UX).
class StartEmergencyUseCase {
  final EmergencyRepository _repo;
  StartEmergencyUseCase(this._repo);

  Future<(SessionEntity, bool created)> call({required String triggerType, String? deviceId}) async {
    try {
      final session = await _repo.createSession(triggerType: triggerType, deviceId: deviceId);
      return (session, true);
    } on SessionConflictException catch (e) {
      return (e.existing, false);
    }
  }
}

/// Resolve with explicit confirmation handled by the UI; the repository keeps
/// the operation idempotent.
class ResolveEmergencyUseCase {
  final EmergencyRepository _repo;
  ResolveEmergencyUseCase(this._repo);

  Future<SessionEntity> call(String sessionId) => _repo.resolve(sessionId);
}
