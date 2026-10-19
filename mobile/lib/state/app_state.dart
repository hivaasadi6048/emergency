import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/native/emergency_native.dart';

import '../data/repositories_impl.dart';
import '../domain/entities.dart';
import '../domain/usecases.dart';

/// Single application state holder (ChangeNotifier) — widgets never call the
/// API directly (Phase 4 acceptance: "API Call داخل Widget نباشد").
class AppState extends ChangeNotifier {
  final TokenStore tokens;
  final ApiClient client;
  final AuthRepositoryImpl authRepo;
  final ContactRepositoryImpl contactRepo;
  final EmergencyRepositoryImpl emergencyRepo;
  final EmergencyNative native;
  final StartEmergencyUseCase startEmergency;

  AppState({
    required this.tokens,
    required this.client,
    required this.authRepo,
    required this.contactRepo,
    required this.emergencyRepo,
    required this.native,
  }) : startEmergency = StartEmergencyUseCase(emergencyRepo);

  UserEntity? user;
  String? lastError;

  List<ContactEntity> contacts = [];
  SessionEntity? activeSession;
  List<SessionEntity> history = [];
  List<EventEntity> activeEvents = [];
  bool busy = false;
  Timer? _poll;
  bool _nativeStartAttempted = false;
  // capturedAtMs -> client_uuid of points already handed to the upload queue;
  // stable keys keep backend dedupe (C-02) correct across retries.
  final Map<int, String> _uploadedPointKeys = {};

  bool get isLoggedIn => user != null;
  bool get hasActiveSession => activeSession != null && !activeSession!.status.isTerminal;

  // ── auth ────────────────────────────────────────────────────────────────
  /// Returns the dev-mode code when the backend provides one; empty string on
  /// success WITHOUT a code (cloud/test-mode server); null on failure.
  Future<String?> requestOtp(String phone) async {
    _setError(null);
    notifyListeners();
    try {
      final code = await authRepo.requestOtp(phone);
      return code ?? '';
    } on ApiException catch (e) {
      _setError(e.persianMessage);
      notifyListeners();
      return null;
    }
  }

  Future<bool> verifyOtp(String phone, String code) async {
    busy = true;
    notifyListeners();
    try {
      user = await authRepo.verifyOtp(phone, code);
      await loadContacts();
      await refreshActiveFromBackend();
      return true;
    } on ApiException catch (e) {
      _setError(e.persianMessage);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restoreSession() async {
    try {
      user = await authRepo.me();
      await loadContacts();
      await refreshActiveFromBackend();
      notifyListeners();
    } on ApiException {
      // no valid in-memory session (Phase 4 tokens are run-scoped)
    }
  }

  Future<void> logout() async {
    await authRepo.logout();
    _stopPolling();
    user = null;
    activeSession = null;
    contacts = [];
    notifyListeners();
  }

  // ── contacts ────────────────────────────────────────────────────────────
  Future<void> loadContacts() async {
    try {
      contacts = await contactRepo.list();
      notifyListeners();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
    }
  }

  Future<bool> addContact({required String name, required String phone, String? relationship}) async {
    try {
      await contactRepo.create(name: name, phone: phone, relationship: relationship);
      await loadContacts();
      return true;
    } on ApiException catch (e) {
      _setError(e.persianMessage);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateContact(String id, {String? name, String? phone, String? relationship}) async {
    try {
      await contactRepo.update(id, name: name, phone: phone, relationship: relationship);
      await loadContacts();
      return true;
    } on ApiException catch (e) {
      _setError(e.persianMessage);
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteContact(String id) async {
    try {
      await contactRepo.delete(id);
      await loadContacts();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
      notifyListeners();
    }
  }

  // ── emergency ───────────────────────────────────────────────────────────
  Future<void> sos() async {
    if (hasActiveSession || busy) return;
    busy = true;
    _setError(null);
    _nativeStartAttempted = false;
    notifyListeners();
    try {
      final (session, _) = await startEmergency(triggerType: 'IN_APP_SOS');
      activeSession = session;
      _uploadedPointKeys.clear(); // new session, fresh dedupe keys

      // Permission gate: a fresh install has NO runtime permissions — request
      // them and wait briefly; without fine location the FGS cannot run and
      // the session is reported FAILED honestly (no silent stuck TRIGGERED).
      await native.requestPermissions();
      bool fine = false;
      for (var i = 0; i < 20; i++) {
        final perms = await native.permissions();
        if (perms['fineLocation'] == true) {
          fine = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!fine) {
        activeSession = await emergencyRepo.reportCapability(
          session.id,
          locationCapability: 'FAILED',
          networkOk: true,
        );
        _setError('مجوز موقعیت داده نشد — ردیابی ممکن نیست. از تنظیمات مجوز را فعال کنید.');
        _stopPolling();
        return;
      }

      // Native FGS starts right after the trigger (temporary bridge; Pigeon in Phase 5)
      await native.startLocationService();
      _nativeStartAttempted = true;
      _startPolling();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> resolveActive() async {
    final session = activeSession;
    if (session == null) return;
    busy = true;
    notifyListeners();
    try {
      activeSession = await emergencyRepo.resolve(session.id);
      await _finishIfTerminal();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancelActive() async {
    final session = activeSession;
    if (session == null) return;
    busy = true;
    notifyListeners();
    try {
      activeSession = await emergencyRepo.cancel(session.id);
      await _finishIfTerminal();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> clearFinishedSession() async {
    await _finishIfTerminal();
    activeSession = null;
    activeEvents = [];
    notifyListeners();
  }

  Future<void> loadHistory() async {
    try {
      history = await emergencyRepo.history();
      notifyListeners();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
    }
  }

  Future<void> loadEvents(String sessionId) async {
    try {
      activeEvents = await emergencyRepo.events(sessionId);
      notifyListeners();
    } on ApiException catch (e) {
      _setError(e.persianMessage);
    }
  }

  Future<void> refreshActiveFromBackend() async {
    try {
      final sessions = await emergencyRepo.history();
      final open = sessions.where((s) => !s.status.isTerminal).toList();
      activeSession = open.isEmpty ? null : open.first;
      if (hasActiveSession) {
        // resume tracking for an open session (e.g. app reinstalled mid-session)
        await native.startLocationService();
        _nativeStartAttempted = true;
        _startPolling();
      }
      notifyListeners();
    } on ApiException {
      // offline at startup — SOS screen still usable, poll will retry
    }
  }

  void _startPolling() {
    if (_poll != null) return;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _tick() async {
    final session = activeSession;
    if (session == null || session.status.isTerminal) {
      _stopPolling();
      return;
    }
    try {
      // 1) report native capability facts (backend composes the state)
      if (_nativeStartAttempted && !_isBusyStatus(session.status)) {
        final nativeState = await native.status();
        final serviceState = (nativeState['serviceState'] ?? 'STOPPED').toString();
        if (serviceState == 'ACTIVE' || serviceState == 'DEGRADED' || serviceState == 'FAILED') {
          activeSession = await emergencyRepo.reportCapability(
            session.id,
            locationCapability: serviceState,
            networkOk: true,
          );
        }
        // 1b) upload native location points — early Phase 5 pipeline preview
        // over the temporary bridge (docs/change-log.md C-014)
        if (_isIngestable(activeSession!.status)) {
          await _uploadNativePoints(activeSession!.id);
        }
      }
      // 2) refresh authoritative state
      activeSession = await emergencyRepo.getSession(session.id);
      if (activeSession!.status.isTerminal) {
        await native.stopLocationService(); // privacy: stop collection when session ends
        _stopPolling();
      }
    } on ApiException {
      // transient (offline/backend down): keep last known state, retry next tick
    }
    notifyListeners();
  }

  bool _isBusyStatus(EmergencyStatus s) => s == EmergencyStatus.resolving || s == EmergencyStatus.resolved;

  bool _isIngestable(EmergencyStatus s) =>
      s == EmergencyStatus.starting || s == EmergencyStatus.active || s == EmergencyStatus.degraded;

  /// Reads the native point buffer (temp bridge) and uploads unseen points.
  /// client_uuid keys are stable per capturedAtMs so retries dedupe on the
  /// server (constraint C-02) instead of creating duplicate rows.

  /// UUID derived from session id + capture time — stable across app restarts
  /// (uuidV4 would break server-side dedupe after a process death, C-02).
  String _stablePointUuid(String sessionId, int capturedMs) {
    int h = 0x5a17;
    final src = '$sessionId:$capturedMs';
    for (final c in src.codeUnits) {
      h = (h ^ c) * 0x01000193 & 0x7fffffff;
    }
    final hex = h.toRadixString(16).padLeft(8, '0') +
        (capturedMs & 0xffffffff).toRadixString(16).padLeft(8, '0') +
        sessionId.replaceAll('-', '').substring(0, 12);
    final p = hex.padRight(32, '0').substring(0, 32);
    return '${p.substring(0, 8)}-${p.substring(8, 12)}-4${p.substring(13, 16)}-8${p.substring(17, 20)}-${p.substring(20, 32)}';
  }

  Future<void> _uploadNativePoints(String sessionId) async {
    final nativeState = await native.status();
    final pointsRaw = (nativeState['points'] as List?) ?? const [];
    final batch = <Map<String, dynamic>>[];
    for (final p in pointsRaw) {
      if (p is! Map) continue;
      final m = Map<String, dynamic>.from(p);
      final capturedMs = (m['capturedAtMs'] as num?)?.toInt();
      if (capturedMs == null || _uploadedPointKeys.containsKey(capturedMs)) continue;
      // DETERMINISTIC id: same (session, capturedAt) must always map to the
      // same client_uuid so a re-upload after process restart dedupes on the
      // server (constraint C-02) instead of creating duplicate rows.
      final clientUuid = _stablePointUuid(sessionId, capturedMs);
      _uploadedPointKeys[capturedMs] = clientUuid;
      batch.add({
        'client_uuid': clientUuid,
        'latitude': m['latitude'],
        'longitude': m['longitude'],
        'accuracy_m': m['accuracyM'],
        'captured_at': DateTime.fromMillisecondsSinceEpoch(capturedMs, isUtc: true).toIso8601String(),
        'source': (m['source'] ?? 'FGS_GPS').toString(),
      });
    }
    if (batch.isEmpty) return;
    if (_uploadedPointKeys.length > 500) {
      // keep the dedupe map bounded; old keys are long-consumed points
      final keys = _uploadedPointKeys.keys.toList()..sort();
      for (final k in keys.take(_uploadedPointKeys.length - 500)) {
        _uploadedPointKeys.remove(k);
      }
    }
    await emergencyRepo.uploadLocations(sessionId, batch);
    debugPrint('locations.uploaded session=$sessionId count=${batch.length}');
  }

  Future<void> _finishIfTerminal() async {
    final s = activeSession;
    if (s != null && s.status.isTerminal) {
      await native.stopLocationService(); // privacy: collection stops with the session
      _stopPolling();
      await loadHistory();
    }
  }

  void _setError(String? message) => lastError = message;
}
