import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:emergency_poc/core/api/api_client.dart';
import 'package:emergency_poc/core/api/api_exception.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend backend;

  setUp(() async {
    backend = FakeBackend();
    await backend.start();
  });

  tearDown(() async {
    await backend.stop();
  });

  test('sends Bearer token and Idempotency-Key headers', () async {
    final tokens = InMemoryTokenStore();
    await tokens.save(access: 'ACCESS123', refresh: 'REFRESH123');
    final client = ApiClient(baseUrl: backend.baseUrl, tokenStore: tokens);
    backend.on('POST', '/api/v1/things', (req) async => (201, {'ok': true}));

    final res = await client.request('POST', '/api/v1/things', body: {'a': 1}, idempotencyKey: 'IDEM-1');

    expect(res.status, 201);
    expect(backend.seenAuthorization.last, 'Bearer ACCESS123');
    expect(backend.seenIdempotencyKeys.last, 'IDEM-1');
  });

  test('parses the stable error envelope into ApiException', () async {
    final client = ApiClient(baseUrl: backend.baseUrl, tokenStore: InMemoryTokenStore());
    backend.on('POST', '/api/v1/emergency/sessions', (req) async {
      return (
        409,
        {
          'error': {'code': 'CONFLICT_ACTIVE_SESSION', 'message': 'an active session exists'},
          'existing_session': {'id': 'abc', 'status': 'ACTIVE'},
        }
      );
    });

    await expectLater(
      client.request('POST', '/api/v1/emergency/sessions', body: {}, idempotencyKey: 'k'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.code, 'code', 'CONFLICT_ACTIVE_SESSION')
            .having((e) => e.body?['existing_session']['id'], 'existing id', 'abc'),
      ),
    );
  });

  test('refreshes once on 401 then retries with the new token', () async {
    final tokens = InMemoryTokenStore();
    await tokens.save(access: 'OLD', refresh: 'REFRESH-1');
    final client = ApiClient(baseUrl: backend.baseUrl, tokenStore: tokens);

    backend.on('GET', '/api/v1/users/me', (req) async {
      final auth = backend.seenAuthorization.last;
      if (auth == 'Bearer OLD') return (401, {'error': {'code': 'UNAUTHORIZED'}});
      return (200, {'id': 'u1', 'phone': '+989121234567', 'display_name': 'A'});
    });
    backend.on('POST', '/api/v1/auth/refresh', (req) async {
      return (200, {'access': 'NEW', 'refresh': 'REFRESH-2'});
    });

    final me = await client.request('GET', '/api/v1/users/me');

    expect(me.data['id'], 'u1');
    expect(backend.seenAuthorization, contains('Bearer NEW'));
    final stored = await tokens.readAccess();
    expect(stored, 'NEW');
  });

  test('network failure maps to NETWORK code', () async {
    final client = ApiClient(baseUrl: 'http://127.0.0.1:9', tokenStore: null); // nothing listens
    await expectLater(
      client.request('GET', '/api/v1/users/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
    );
    // silence unused import when jsonEncode not needed on some SDK versions
    jsonEncode;
  });
}
