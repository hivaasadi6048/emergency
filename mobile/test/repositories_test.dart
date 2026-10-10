import 'package:flutter_test/flutter_test.dart';

import 'package:emergency_poc/data/repositories_impl.dart';
import 'package:emergency_poc/core/api/api_client.dart';
import 'package:emergency_poc/domain/entities.dart';
import 'package:emergency_poc/domain/usecases.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend backend;
  late ApiClient client;
  late InMemoryTokenStore tokens;

  setUp(() async {
    backend = FakeBackend();
    await backend.start();
    tokens = InMemoryTokenStore();
    await tokens.save(access: 'A', refresh: 'R');
    client = ApiClient(baseUrl: backend.baseUrl, tokenStore: tokens);
  });

  tearDown(() async {
    await backend.stop();
  });

  group('ContactRepositoryImpl', () {
    test('list parses the backend array', () async {
      backend.on('GET', '/api/v1/contacts', (req) async {
        return (200, [
          {
            'id': 'c1', 'name': 'Maman', 'phone': '+989121234567',
            'relationship': 'family', 'priority': 0, 'is_active': true,
          }
        ]);
      });
      final repo = ContactRepositoryImpl(client);
      final contacts = await repo.list();
      expect(contacts, hasLength(1));
      expect(contacts.first, isA<ContactEntity>());
      expect(contacts.first.name, 'Maman');
    });

    test('create posts the body and parses the entity', () async {
      backend.on('POST', '/api/v1/contacts', (req) async {
        expect(req.body['name'], 'Baba');
        expect(req.body['phone'], '09121234567'); // raw — backend normalizes
        return (
          201,
          {'id': 'c2', 'name': 'Baba', 'phone': '+989121234567', 'relationship': '', 'priority': 0, 'is_active': true}
        );
      });
      final repo = ContactRepositoryImpl(client);
      final contact = await repo.create(name: 'Baba', phone: '09121234567');
      expect(contact.id, 'c2');
    });
  });

  group('StartEmergencyUseCase', () {
    test('returns (session, created=true) on 201', () async {
      backend.on('POST', '/api/v1/emergency/sessions', (req) async {
        return (201, {'id': 's1', 'status': 'TRIGGERED', 'trigger_type': 'IN_APP_SOS'});
      });
      final usecase = StartEmergencyUseCase(EmergencyRepositoryImpl(client));
      final (session, created) = await usecase(triggerType: 'IN_APP_SOS');
      expect(created, isTrue);
      expect(session.status, EmergencyStatus.triggered);
    });

    test('adopts the existing session on duplicate SOS (409)', () async {
      backend.on('POST', '/api/v1/emergency/sessions', (req) async {
        return (
          409,
          {
            'error': {'code': 'CONFLICT_ACTIVE_SESSION', 'message': 'an active session exists'},
            'existing_session': {'id': 'existing-1', 'status': 'ACTIVE', 'trigger_type': 'IN_APP_SOS'},
          }
        );
      });
      final usecase = StartEmergencyUseCase(EmergencyRepositoryImpl(client));
      final (session, created) = await usecase(triggerType: 'IN_APP_SOS');
      expect(created, isFalse);
      expect(session.id, 'existing-1');
      expect(session.status, EmergencyStatus.active);
    });
  });

  group('EmergencyRepositoryImpl', () {
    test('resolve posts with a fresh idempotency key and parses state', () async {
      backend.on('POST', '/api/v1/emergency/sessions/s9/resolve', (req) async {
        return (200, {'id': 's9', 'status': 'RESOLVED', 'trigger_type': 'IN_APP_SOS'});
      });
      final repo = EmergencyRepositoryImpl(client);
      final session = await repo.resolve('s9');
      expect(session.status, EmergencyStatus.resolved);
      expect(backend.seenIdempotencyKeys.last, isNotNull);
    });

    test('capability report passes the payload verbatim', () async {
      backend.on('POST', '/api/v1/emergency/sessions/s1/capability', (req) async {
        expect(req.body['location_capability'], 'DEGRADED');
        expect(req.body['network_ok'], false);
        return (200, {'id': 's1', 'status': 'DEGRADED', 'trigger_type': 'IN_APP_SOS'});
      });
      final repo = EmergencyRepositoryImpl(client);
      final session = await repo.reportCapability('s1', locationCapability: 'DEGRADED', networkOk: false);
      expect(session.status, EmergencyStatus.degraded);
    });
  });
}
