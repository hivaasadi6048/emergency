import '../domain/entities.dart';
import '../domain/repositories.dart';
import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/uuid.dart';

class AuthRepositoryImpl implements AuthRepository {
  final ApiClient _client;
  final TokenStore _tokens;
  AuthRepositoryImpl(this._client, this._tokens);

  @override
  Future<String?> requestOtp(String phone) async {
    final res = await _client.request('POST', '/api/v1/auth/request-otp', body: {'phone': phone}, auth: false);
    final code = res.data['debug_code'];
    return code is String ? code : null; // only in backend OTP_DEV_MODE
  }

  @override
  Future<UserEntity> verifyOtp(String phone, String code) async {
    final res = await _client.request(
      'POST',
      '/api/v1/auth/verify-otp',
      body: {'phone': phone, 'code': code, 'device_platform': 'ANDROID', 'device_identifier': 'flutter-phase4'},
      auth: false,
    );
    await _tokens.save(access: res.data['access'] as String? ?? '', refresh: res.data['refresh'] as String? ?? '');
    return UserEntity.fromJson(res.data['user'] as Map<String, dynamic>);
  }

  @override
  Future<UserEntity> me() async {
    final res = await _client.request('GET', '/api/v1/users/me');
    return UserEntity.fromJson(res.data);
  }

  @override
  Future<void> logout() async {
    // refresh token lives only in memory in Phase 4 — clearing it is the logout
    await _tokens.clear();
  }
}

class ContactRepositoryImpl implements ContactRepository {
  final ApiClient _client;
  ContactRepositoryImpl(this._client);

  @override
  Future<List<ContactEntity>> list() async {
    final res = await _client.request('GET', '/api/v1/contacts');
    final items = res.raw is List ? res.raw as List : const [];
    return items.whereType<Map<String, dynamic>>().map(ContactEntity.fromJson).toList();
  }

  @override
  Future<ContactEntity> create({required String name, required String phone, String? relationship}) async {
    final res = await _client.request('POST', '/api/v1/contacts', body: {
      'name': name,
      'phone': phone,
      'relationship': ?relationship,
    });
    return ContactEntity.fromJson(res.data);
  }

  @override
  Future<ContactEntity> update(String id, {String? name, String? phone, String? relationship}) async {
    final res = await _client.request('PATCH', '/api/v1/contacts/$id', body: {
      'name': ?name,
      'phone': ?phone,
      'relationship': ?relationship,
    });
    return ContactEntity.fromJson(res.data);
  }

  @override
  Future<void> delete(String id) async {
    await _client.request('DELETE', '/api/v1/contacts/$id');
  }
}

class EmergencyRepositoryImpl implements EmergencyRepository {
  final ApiClient _client;
  EmergencyRepositoryImpl(this._client);

  @override
  Future<SessionEntity> createSession({required String triggerType, String? deviceId}) async {
    try {
      final res = await _client.request(
        'POST',
        '/api/v1/emergency/sessions',
        body: {'trigger_type': triggerType, 'device_id': ?deviceId},
        idempotencyKey: uuidV4(),
      );
      return SessionEntity.fromJson(res.data);
    } on ApiException catch (e) {
      if (e.isConflictActiveSession) {
        final existing = e.body?['existing_session'];
        if (existing is Map<String, dynamic>) {
          throw SessionConflictException(SessionEntity.fromJson(existing));
        }
      }
      rethrow;
    }
  }

  @override
  Future<SessionEntity> getSession(String id) async {
    final res = await _client.request('GET', '/api/v1/emergency/sessions/$id');
    return SessionEntity.fromJson(res.data);
  }

  @override
  Future<List<SessionEntity>> history() async {
    final res = await _client.request('GET', '/api/v1/emergency/sessions');
    final items = res.raw is List ? res.raw as List : const [];
    return items.whereType<Map<String, dynamic>>().map(SessionEntity.fromJson).toList();
  }

  @override
  Future<List<EventEntity>> events(String id) async {
    final res = await _client.request('GET', '/api/v1/emergency/sessions/$id/events');
    final items = res.raw is List ? res.raw as List : const [];
    return items.whereType<Map<String, dynamic>>().map(EventEntity.fromJson).toList();
  }

  @override
  Future<SessionEntity> resolve(String id) async {
    final res = await _client.request(
      'POST',
      '/api/v1/emergency/sessions/$id/resolve',
      idempotencyKey: uuidV4(),
    );
    return SessionEntity.fromJson(res.data);
  }

  @override
  Future<SessionEntity> cancel(String id) async {
    final res = await _client.request(
      'POST',
      '/api/v1/emergency/sessions/$id/cancel',
      idempotencyKey: uuidV4(),
    );
    return SessionEntity.fromJson(res.data);
  }

  @override
  Future<SessionEntity> reportCapability(String id, {required String locationCapability, required bool networkOk}) async {
    final res = await _client.request(
      'POST',
      '/api/v1/emergency/sessions/$id/capability',
      body: {'location_capability': locationCapability, 'network_ok': networkOk},
    );
    return SessionEntity.fromJson(res.data);
  }

  @override
  Future<void> uploadLocations(String sessionId, List<Map<String, dynamic>> points) async {
    await _client.request(
      'POST',
      '/api/v1/locations',
      body: {'session_id': sessionId, 'points': points},
      idempotencyKey: uuidV4(),
    );
  }
}
