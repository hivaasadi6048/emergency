package com.emergency.app.emergency_poc

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "emergency.poc/native"
        private const val PERMISSION_REQUEST_CODE = 4711

        // EXPERIMENTAL volume-sequence parameters (docs/architecture.md D-13).
        private const val SEQ_TARGET = 5
        private const val SEQ_WINDOW_MS = 3_000L
        // Trigger policy (owner finding, 2026-10-03): naive 5-in-3s re-fires while the button is
        // mashed continuously. A deliberate sequence must START from silence and detection re-arms
        // only after a cooldown.
        private const val QUIET_START_MS = 1_000L
        private const val REARM_LOCKOUT_MS = 5_000L
    }

    private lateinit var channel: MethodChannel

    // EXPERIMENTAL volume-sequence probe. Foreground-only by design: there is NO public
    // Android API for volume key events outside a focused window (screen off / lock screen /
    // background). AccessibilityService and MediaSession workarounds are forbidden (D-13).
    // The Device Matrix must record those conditions as UNSUPPORTED/PARTIAL — no hacks.
    private var monitoring = false
    private var pressCount = 0
    private var windowStartMs = 0L
    private var lastPressMs = 0L
    private var lockoutUntilMs = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    requestNeededPermissions()
                    result.success(permissionSnapshot())
                }
                "startEmergencyLocationService" -> {
                    val fine = ContextCompat.checkSelfPermission(
                        this, Manifest.permission.ACCESS_FINE_LOCATION,
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!fine) {
                        result.error(
                            "PERMISSION_REQUIRED",
                            "ACCESS_FINE_LOCATION must be granted before starting the location FGS (STARTING->FAILED policy)",
                            null,
                        )
                    } else {
                        PocNativeState.lastError = null
                        EmergencyLocationService.start(this)
                        result.success(nativeStateMap())
                    }
                }
                "stopEmergencyLocationService" -> {
                    EmergencyLocationService.stop(this)
                    result.success(nativeStateMap())
                }
                "getLocationServiceStatus" -> result.success(nativeStateMap())
                "startHardwareTriggerMonitoring" -> {
                    monitoring = true
                    pressCount = 0
                    Log.i("PocVol", "VOL_MONITOR_ARMED")
                    result.success(true)
                }
                "stopHardwareTriggerMonitoring" -> {
                    monitoring = false
                    Log.i("PocVol", "VOL_MONITOR_DISARMED")
                    result.success(true)
                }
                "getNativeEmergencyState" -> result.success(nativeStateMap())
                "getPendingPoints" -> result.success(pendingPointsList())
                "ackUploadedPoints" -> {
                    // C-017: Dart acks uuids ONLY after the backend returned 202 for the batch.
                    val args = call.arguments as? Map<*, *>
                    val uuids = (args?.get("uuids") as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
                    result.success(PocNativeState.acknowledge(uuids))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            channel.invokeMethod("onPermissionsResult", permissionSnapshot())
        }
    }

    private fun permissionSnapshot(): Map<String, Any> {
        val fine = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val notif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else true
        return mapOf(
            "fineLocation" to fine,
            "notifications" to notif,
            // D-06: background location is never requested in the MVP.
            "backgroundLocation" to false,
        )
    }

    private fun requestNeededPermissions() {
        val wanted = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            wanted += Manifest.permission.ACCESS_FINE_LOCATION
            wanted += Manifest.permission.ACCESS_COARSE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
        }
        if (wanted.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, wanted.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (monitoring && event.action == KeyEvent.ACTION_DOWN &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            val now = SystemClock.elapsedRealtime()
            val gap = now - lastPressMs
            lastPressMs = now
            if (now < lockoutUntilMs) {
                Log.i("PocVol", "VOL_PRESS ignored (lockout)")
                return super.dispatchKeyEvent(event)
            }
            if (pressCount > 0 && now - windowStartMs > SEQ_WINDOW_MS) {
                pressCount = 0 // window expired — a fresh sequence is required
            }
            if (pressCount == 0 && gap < QUIET_START_MS) {
                // continuous mashing: a deliberate sequence must start from silence
                Log.i("PocVol", "VOL_PRESS ignored (no quiet start, gap=${gap}ms)")
                return super.dispatchKeyEvent(event)
            }
            if (pressCount == 0) windowStartMs = now
            pressCount++
            Log.i("PocVol", "VOL_PRESS count=$pressCount (gap=${gap}ms)")
            if (pressCount >= SEQ_TARGET && now - windowStartMs <= SEQ_WINDOW_MS) {
                pressCount = 0
                lockoutUntilMs = now + REARM_LOCKOUT_MS
                Log.i("PocVol", "VOL_SEQ_DETECTED (re-arm lockout ${REARM_LOCKOUT_MS}ms)")
                channel.invokeMethod(
                    "onVolumeSequence",
                    mapOf(
                        "detectedAtMs" to System.currentTimeMillis(),
                        "condition" to "FOREGROUND_ONLY",
                        "status" to "EXPERIMENTAL",
                    ),
                )
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun nativeStateMap(): Map<String, Any?> {
        val snapshot = PocNativeState.pointsSnapshot()
        val points = snapshot.takeLast(20).map { p ->
            mapOf(
                "latitude" to p.latitude,
                "longitude" to p.longitude,
                "accuracyM" to p.accuracyM,
                "capturedAtMs" to p.capturedAtMs,
                "source" to p.source,
                "clientUuid" to p.clientUuid,
            )
        }
        return mapOf(
            "serviceState" to PocNativeState.serviceState,
            "lastError" to PocNativeState.lastError,
            "startedAtMs" to PocNativeState.startedAtMs,
            "lastFixAtMs" to PocNativeState.lastFixAtMs,
            "pointCount" to snapshot.size,
            "stallRecoveries" to PocNativeState.stallRecoveries,
            "points" to points,
            "permissions" to permissionSnapshot(),
        )
    }

    /** C-017: the FULL un-acked queue (not just the last 20) with stable uuids —
     *  this is the upload source of truth; replaces reading `points` for upload. */
    private fun pendingPointsList(): List<Map<String, Any?>> =
        PocNativeState.pointsSnapshot().map { p ->
            mapOf(
                "clientUuid" to p.clientUuid,
                "latitude" to p.latitude,
                "longitude" to p.longitude,
                "accuracyM" to p.accuracyM,
                "capturedAtMs" to p.capturedAtMs,
                "source" to p.source,
            )
        }
}
