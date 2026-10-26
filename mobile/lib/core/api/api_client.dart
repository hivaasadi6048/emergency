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

/// C-021 — outcome of a (coordinated) token refresh attempt.
enum RefreshOutcome {
  /// New access token stored — retry the original request.
  success,

  /// Refresh truly rejected (400/401/403 or no token) — clear + AUTH_EXPIRED.
  dead,

  /// Server refused to JUDGE the refresh right now (429 rate-limit, 5xx).
  /// The session is NOT dead: keep tokens, retry on a later tick. Treating
  /// this as fatal falsely logged the owner out (device test 2026-10-20).
  transient,
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

  /// C-021 — the single in-flight refresh, shared by every 401 path.
  Future<RefreshOutcome>? _refreshInFlight;

  /// C-021 — single-flight refresh: all concurrent 401s await the SAME refresh
  /// instead of each firing its own. Without this, one token-expiry moment
  /// produced N parallel refreshes carrying the same refresh token; the server
  /// (ROTATE_REFRESH_TOKENS + BLACKLIST_AFTER_ROTATION) rotated once and
  /// rejected the rest (401 blacklisted / 429 throttled — device test
  /// 2026-10-20: 15+ refresh attempts within one second), each of which looked
  /// like a dead session and forced a false logout.
  Future<RefreshOutcome> _refreshSingleFlight() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final f = tokenStore!.tryRefresh(this).whenComplete(() => _refreshInFlight = null);
    _refreshInFlight = f;
    return f;
  }

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
      final outcome = await _refreshSingleFlight();
      if (outcome == RefreshOutcome.success) {
        return request(method, path, body: body, idempotencyKey: idempotencyKey, auth: auth, allowRefresh: false);
      }
      if (outcome == RefreshOutcome.transient) {
        // C-021: throttled/hiccup is NOT a dead session. Surface as NETWORK so
        // the outer one-retry and the next 3s polling tick pick it up — no
        // token clear, no logout.
        throw ApiException(status: 0, code: 'NETWORK', message: 'refresh temporarily unavailable; will retry');
      }
      // outcome == dead — C-020: the auth session is unrecoverable (signing key
      // changed, refresh expired/rotated/blacklisted). Clear the dead tokens and
      // raise a DISTINCT code so AppState can route back to login instead of
      // looping 401s behind a generic error banner.
      await tokenStore!.clear();
      throw ApiException(status: 401, code: 'AUTH_EXPIRED', message: 'session expired; re-login required');
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

  /// C-021: returns a [RefreshOutcome] instead of bool — a throttled/hiccuped
  /// refresh (429/5xx) must NOT be reported as a dead session.
  Future<RefreshOutcome> tryRefresh(ApiClient client);
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
  Future<RefreshOutcome> tryRefresh(ApiClient client) async {
    final refresh = _refresh;
    if (refresh == null || refresh.isEmpty) return RefreshOutcome.dead;
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
        return RefreshOutcome.success;
      }
      return RefreshOutcome.dead;
    } on ApiException catch (e) {
      // C-021: 429 (rate-limited) or 5xx — the server refused to process the
      // refresh NOW but said nothing about the token being invalid. Keep the
      // tokens; a later tick retries. 400/401/403 → genuinely dead.
      if (e.status == 429 || e.status >= 500) return RefreshOutcome.transient;
      return RefreshOutcome.dead;
    }
  }
}
