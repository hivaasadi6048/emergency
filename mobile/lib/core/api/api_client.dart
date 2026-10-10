import 'dart:convert';
import 'dart:io';

import 'api_exception.dart';

class ApiResult {
  final int status;

  /// Map body (most endpoints) — empty map for list bodies.
  final Map<String, dynamic> data;

  /// Untouched decoded body — List for array endpoints (contacts/history/events).
  final Object? raw;
  ApiResult({required this.status, required this.data, this.raw});
}

String extractErrorCode(Map<String, dynamic>? body) {
  if (body == null) return 'UNKNOWN';
  final err = body['error'];
  if (err is Map<String, dynamic>) return (err['code'] ?? 'UNKNOWN').toString();
  return 'UNKNOWN';
}

String extractErrorMessage(Map<String, dynamic>? body) {
  if (body == null) return '';
  final err = body['error'];
  if (err is Map<String, dynamic>) return (err['message'] ?? '').toString();
  return '';
}

/// Zero-dependency HTTP client on dart:io (no pub packages — see change-log
/// C-012). Adds the Bearer token, injects Idempotency-Key, parses the stable
/// error envelope and retries once after a successful token refresh on 401.
class ApiClient {
  ApiClient({required this.baseUrl, this.tokenStore});

  /// Mutable so the Settings screen can point the app at another backend.
  String baseUrl;
  final TokenStore? tokenStore;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

  Future<ApiResult> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    bool auth = true,
    bool allowRefresh = true,
  }) async {
    // one retry on transport failures — the dev adb-reverse tunnel blips when
    // USB re-enumerates; a single immediate retry absorbs most of them
    try {
      return await _requestOnce(method, path,
          body: body, idempotencyKey: idempotencyKey, auth: auth, allowRefresh: allowRefresh);
    } on ApiException catch (e) {
      if (e.code != 'NETWORK') rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _requestOnce(method, path,
          body: body, idempotencyKey: idempotencyKey, auth: auth, allowRefresh: allowRefresh);
    }
  }

  Future<ApiResult> _requestOnce(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    bool auth = true,
    bool allowRefresh = true,
  }) async {
    Object? decoded;
    int status;
    try {
      final req = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (auth) {
        final access = await tokenStore?.readAccess();
        if (access != null && access.isNotEmpty) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $access');
        }
      }
      if (idempotencyKey != null) req.headers.set('Idempotency-Key', idempotencyKey);
      if (body != null) {
        // MUST set Content-Length explicitly: without it dart:io switches to
        // chunked transfer-encoding, and Python's http.server (Django dev
        // server) cannot parse chunked bodies — the body arrives EMPTY and the
        // leftover chunk bytes corrupt the keep-alive connection
        // (owner-visible as «شماره موبایل معتبر نیست», change-log B-018).
        final bodyBytes = utf8.encode(jsonEncode(body));
        req.headers.contentLength = bodyBytes.length;
        req.add(bodyBytes);
      }
      final res = await req.close();
      status = res.statusCode;
      final text = await res.transform(utf8.decoder).join();
      if (text.isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          decoded = {'raw': text};
        }
      }
    } on SocketException catch (e) {
      throw ApiException(status: 0, code: 'NETWORK', message: e.message);
    } on HttpException catch (e) {
      throw ApiException(status: 0, code: 'NETWORK', message: e.message);
    }

    if (status == 401 && auth && allowRefresh && tokenStore != null) {
      final refreshed = await tokenStore!.tryRefresh(this);
      if (refreshed) {
        return request(method, path, body: body, idempotencyKey: idempotencyKey, auth: auth, allowRefresh: false);
      }
    }

    if (status >= 400) {
      throw ApiException(
        status: status,
        code: extractErrorCode(decoded is Map<String, dynamic> ? decoded : null),
        message: extractErrorMessage(decoded is Map<String, dynamic> ? decoded : null),
        body: decoded is Map<String, dynamic> ? decoded : null,
      );
    }
    return ApiResult(
      status: status,
      data: decoded is Map<String, dynamic> ? decoded : {},
      raw: decoded,
    );
  }
}

/// Token storage abstraction. Phase 4 keeps tokens in memory for the app run —
/// persistence moves to secure storage in the hardening phase (documented
/// limitation; pub mirrors were unavailable for storage packages).
abstract class TokenStore {
  Future<String?> readAccess();
  Future<bool> tryRefresh(ApiClient client);
  Future<void> save({required String access, required String refresh});
  Future<void> clear();
}

class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<String?> readAccess() async => _access;

  @override
  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }

  @override
  Future<bool> tryRefresh(ApiClient client) async {
    final refresh = _refresh;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await client.request(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refresh': refresh},
        auth: false,
        allowRefresh: false,
      );
      final newAccess = res.data['access'];
      if (newAccess is String && newAccess.isNotEmpty) {
        _access = newAccess;
        final newRefresh = res.data['refresh'];
        if (newRefresh is String && newRefresh.isNotEmpty) _refresh = newRefresh;
        return true;
      }
      return false;
    } on ApiException {
      return false;
    }
  }
}
