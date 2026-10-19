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
  // C-016/C-017: client_uuid is born NATIVE-side at capture time and lives in the
  // persistent queue — stable across restarts, so server dedupe (C-02) holds.
  // This set is only a within-session upload guard (bounded, belt-and-braces).
  final Set<String> _uploadedUuids = {};
  // Points captured more than this before the current session's start belong to an
  // older (already terminal) session and are discarded+acked instead of re-attributed.
  static const int _sessionSkewSlackMs = 120000;

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
      _uploadedUuids.clear(); // new session, fresh upload guard

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

  /// Uploads the native pending queue (temp bridge, docs/change-log.md C-014/C-016/C-017).
  /// Correctness contract:
  ///  - client_uuid comes FROM the native queue (born at capture time) — stable across
  ///    retries AND process restarts, so the backend's (session, client_uuid) dedupe holds;
  ///  - points are acked (drained) ONLY after the backend accepted the batch — a crash
  ///    between upload and ack causes a re-upload with the SAME uuid → duplicate is
  ///    swallowed server-side, no duplicate rows, no lost points;
  ///  - points older than the current session's start are drained WITHOUT upload (their
  ///    session is already terminal and can no longer receive locations).
  Future<void> _uploadNativePoints(String sessionId) async {
    final pending = await native.pendingPoints();
    if (pending.isEmpty) return;

    final startedAtMs = activeSession?.startedAt?.millisecondsSinceEpoch;
    final batch = <Map<String, dynamic>>[];
    final staleUuids = <String>[];
    for (final p in pending) {
      final clientUuid = (p['clientUuid'] ?? '').toString();
      final capturedMs = (p['capturedAtMs'] as num?)?.toInt();
      if (clientUuid.isEmpty || capturedMs == null) continue;
      if (_uploadedUuids.contains(clientUuid)) continue;
      if (startedAtMs != null && capturedMs < startedAtMs - _sessionSkewSlackMs) {
        staleUuids.add(clientUuid);
        continue;
      }
      batch.add({
        'client_uuid': clientUuid,
        'latitude': p['latitude'],
        'longitude': p['longitude'],
        'accuracy_m': p['accuracyM'],
        'captured_at': DateTime.fromMillisecondsSinceEpoch(capturedMs, isUtc: true).toIso8601String(),
        'source': (p['source'] ?? 'FGS_GPS').toString(),
      });
    }

    if (staleUuids.isNotEmpty) {
      final drained = await native.ackUploadedPoints(staleUuids);
      debugPrint('locations.staleDiscarded session=$sessionId requested=${staleUuids.length} drained=$drained');
    }
    if (batch.isEmpty) return;

    await emergencyRepo.uploadLocations(sessionId, batch); // throws → nothing acked, retried next tick
    _uploadedUuids.addAll(batch.map((b) => b['client_uuid'] as String));
    if (_uploadedUuids.length > 500) {
      // keep the guard bounded; acked points can never come back (drained natively)
      _uploadedUuids.remove(_uploadedUuids.first);
    }
    final drained = await native.ackUploadedPoints(batch.map((b) => b['client_uuid'] as String).toList());
    debugPrint('locations.uploaded session=$sessionId count=${batch.length} drained=$drained');
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
