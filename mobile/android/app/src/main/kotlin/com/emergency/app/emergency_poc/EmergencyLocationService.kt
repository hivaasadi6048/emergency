package com.emergency.app.emergency_poc

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** One collected location point. [capturedAtMs] is the device-side capture time (kept separate from receive time later). */
data class PocLocationPoint(
    val latitude: Double,
    val longitude: Double,
    val accuracyM: Float?,
    val speedMps: Float?,
    val bearingDeg: Float?,
    val capturedAtMs: Long,
    val source: String,
)

/** Shared native state observed by the Flutter bridge. */
object PocNativeState {
    const val STOPPED = "STOPPED"
    const val ACTIVE = "ACTIVE"
    const val DEGRADED = "DEGRADED"
    const val FAILED = "FAILED"

    private var queue: PersistentPointQueue? = null

    /** Called from the service onCreate — the queue file lives in app storage
     * and survives process death (Phase 5 persistent queue). */
    fun initQueue(filesDir: java.io.File) {
        if (queue == null) {
            queue = PersistentPointQueue(
                java.io.File(filesDir, LocationPolicy.QUEUE_FILE_NAME),
                LocationPolicy.QUEUE_MAX_POINTS,
            )
        }
    }

    @Volatile var serviceState: String = STOPPED
    @Volatile var lastError: String? = null
    @Volatile var startedAtMs: Long? = null
    @Volatile var lastFixAtMs: Long? = null
    @Volatile var stallRecoveries: Int = 0

    @Synchronized
    fun addPoint(point: PocLocationPoint) {
        queue?.add(point)
        lastFixAtMs = point.capturedAtMs
    }

    @Synchronized
    fun pointsSnapshot(): List<PocLocationPoint> = queue?.snapshot() ?: emptyList()
}

/**
 * PHASE 1 PoC: native Foreground Service with foregroundServiceType="location".
 *
 * Constraints implemented per docs/architecture.md:
 * - started only from the foreground (SOS tap in app) — Android 12+ background-start restriction (D-05);
 * - requires ACCESS_FINE_LOCATION granted BEFORE start (Android 14 FGS type=location enforcement);
 * - framework LocationManager only, no Play Services dependency — deliberate PoC decision;
 * - while-in-use permission; ACCESS_BACKGROUND_LOCATION intentionally NOT requested (D-06);
 * - START_STICKY kept on purpose: reboot behavior is open question Q-05 and must be measured per OEM.
 *
 * Location freshness watchdog (added after SM-A217F/OneUI 4 findings, 2026-10-01/03):
 * OneUI silently suspends fix delivery to the app (request stays registered, GNSS keeps
 * producing fixes system-level) during screen-off/secure-lock — while our status would still
 * read ACTIVE. Policy per docs/failure-model.md (no hidden failures): if no fix arrives within
 * STALL_THRESHOLD_MS, the service reports DEGRADED honestly and re-requests updates (public
 * API recovery), returning to ACTIVE on the next delivered fix.
 */
class EmergencyLocationService : Service() {

    companion object {
        private const val TAG = "EmergencyLocSvc"
        private const val CHANNEL_ID = "emergency_poc_fgs"
        private const val NOTIFICATION_ID = 42

        // LocationPolicy — emergency mode, conservative fixed interval for the PoC.
        // Final values come from battery measurement in PHASE 5 (docs/architecture.md §10).
        const val LOCATION_INTERVAL_MS = LocationPolicy.LOCATION_INTERVAL_MS
        const val LOCATION_MIN_DISTANCE_M = LocationPolicy.LOCATION_MIN_DISTANCE_M

        // Watchdog policy — reported honestly instead of silently trusting the platform.
        const val WATCHDOG_PERIOD_MS = LocationPolicy.WATCHDOG_PERIOD_MS
        const val STALL_THRESHOLD_MS = LocationPolicy.STALL_THRESHOLD_MS

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, EmergencyLocationService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, EmergencyLocationService::class.java))
        }
    }

    private val listener = LocationListener { location -> onLocation(location) }
    private val watchdog = Handler(Looper.getMainLooper())
    private var lastFixElapsedMs = 0L
    private var stalled = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        PocNativeState.initQueue(filesDir)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val fineGranted = ContextCompat.checkSelfPermission(
            this, android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!fineGranted) {
            // Android 14+ throws if a location FGS starts without the runtime permission — enforce our own policy first.
            PocNativeState.serviceState = PocNativeState.FAILED
            PocNativeState.lastError = "FGS_START_DENIED_LOCATION_PERMISSION"
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification("در حال راه‌اندازی…")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            PocNativeState.serviceState = PocNativeState.FAILED
            PocNativeState.lastError = "FGS_START_FAILURE: ${e.javaClass.simpleName}"
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return START_NOT_STICKY
        }

        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val gpsOn = isProviderEnabled(lm, LocationManager.GPS_PROVIDER)
        val netOn = isProviderEnabled(lm, LocationManager.NETWORK_PROVIDER)

        if (!gpsOn && !netOn) {
            PocNativeState.serviceState = PocNativeState.DEGRADED
            PocNativeState.lastError = "LOCATION_SERVICES_OFF"
            updateNotification("DEGRADED — سرویس موقعیت دستگاه خاموش است")
            // B-019: the watchdog MUST run even here — when the user re-enables
            // location services, its re-request recovers without a new SOS.
            watchdog.removeCallbacks(watchdogTick)
            watchdog.postDelayed(watchdogTick, WATCHDOG_PERIOD_MS)
            return START_STICKY
        }

        var anyRequested = false
        if (gpsOn) anyRequested = requestSafely(lm, LocationManager.GPS_PROVIDER) || anyRequested
        if (netOn) anyRequested = requestSafely(lm, LocationManager.NETWORK_PROVIDER) || anyRequested

        PocNativeState.serviceState = if (gpsOn && netOn) PocNativeState.ACTIVE else PocNativeState.DEGRADED
        if (PocNativeState.startedAtMs == null) PocNativeState.startedAtMs = System.currentTimeMillis()
        lastFixElapsedMs = SystemClock.elapsedRealtime()
        stalled = false
        updateNotification(
            if (PocNativeState.serviceState == PocNativeState.ACTIVE) "ACTIVE — جمع‌آوری موقعیت فعال است"
            else "DEGRADED — یکی از providerهای موقعیت غیرفعال است",
        )
        watchdog.removeCallbacks(watchdogTick)
        watchdog.postDelayed(watchdogTick, WATCHDOG_PERIOD_MS)
        return START_STICKY
    }

    private val watchdogTick = object : Runnable {
        override fun run() {
            val sinceMs = SystemClock.elapsedRealtime() - lastFixElapsedMs
            if (sinceMs > STALL_THRESHOLD_MS && PocNativeState.serviceState != PocNativeState.FAILED) {
                if (!stalled) {
                    stalled = true
                    PocNativeState.stallRecoveries++
                }
                PocNativeState.serviceState = PocNativeState.DEGRADED
                PocNativeState.lastError =
                    "LOCATION_DELIVERY_STALL: no fix for ${sinceMs / 1000}s — re-requesting (recovery #${PocNativeState.stallRecoveries})"
                Log.w(TAG, PocNativeState.lastError ?: "stall")
                reRequestUpdates()
                updateNotification("DEGRADED — قطع موقت تحویل موقعیت؛ تلاش بازیابی #${PocNativeState.stallRecoveries}")
            } else if (stalled && sinceMs <= STALL_THRESHOLD_MS) {
                // a fix arrived after recovery — back to honest ACTIVE
                stalled = false
                PocNativeState.serviceState = PocNativeState.ACTIVE
                PocNativeState.lastError = null
                updateNotification("ACTIVE — تحویل موقعیت بازیابی شد")
            }
            watchdog.postDelayed(this, WATCHDOG_PERIOD_MS)
        }
    }

    private fun reRequestUpdates() {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            lm.removeUpdates(listener)
        } catch (e: SecurityException) {
            // permission revoked — nothing to re-request
        }
        if (isProviderEnabled(lm, LocationManager.GPS_PROVIDER)) {
            requestSafely(lm, LocationManager.GPS_PROVIDER)
        }
        if (isProviderEnabled(lm, LocationManager.NETWORK_PROVIDER)) {
            requestSafely(lm, LocationManager.NETWORK_PROVIDER)
        }
    }

    private fun isProviderEnabled(lm: LocationManager, provider: String): Boolean =
        try {
            lm.isProviderEnabled(provider)
        } catch (e: IllegalArgumentException) {
            false
        }

    private fun requestSafely(lm: LocationManager, provider: String): Boolean =
        try {
            lm.requestLocationUpdates(provider, LOCATION_INTERVAL_MS, LOCATION_MIN_DISTANCE_M, listener, mainLooper)
            true
        } catch (e: SecurityException) {
            PocNativeState.lastError = "PROVIDER_REQUEST_DENIED: $provider"
            false
        } catch (e: IllegalArgumentException) {
            false
        }

    private fun onLocation(location: Location) {
        // compileSdk 36 stubs declare Location.getProvider() as @Nullable.
        val provider = location.provider ?: "unknown"
        val point = PocLocationPoint(
            latitude = location.latitude,
            longitude = location.longitude,
            accuracyM = if (location.hasAccuracy()) location.accuracy else null,
            speedMps = if (location.hasSpeed()) location.speed else null,
            bearingDeg = if (location.hasBearing()) location.bearing else null,
            capturedAtMs = location.time,
            source = if (provider == LocationManager.GPS_PROVIDER) "FGS_GPS" else "FGS_${provider.uppercase()}",
        )
        PocNativeState.addPoint(point)
        lastFixElapsedMs = SystemClock.elapsedRealtime()
        val clock = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(point.capturedAtMs))
        updateNotification("آخرین نقطه: $clock (±${point.accuracyM ?: "?"}m)")
    }

    override fun onDestroy() {
        watchdog.removeCallbacks(watchdogTick)
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            lm.removeUpdates(listener)
        } catch (e: SecurityException) {
            // permission revoked while running — nothing left to clean up
        }
        if (PocNativeState.serviceState != PocNativeState.FAILED) PocNativeState.serviceState = PocNativeState.STOPPED
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(CHANNEL_ID, "Emergency PoC Tracking", NotificationManager.IMPORTANCE_LOW)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("PoC ایمنی — ردیابی موقعیت")
        .setContentText(text)
        .setSmallIcon(android.R.drawable.ic_menu_mylocation)
        .setOngoing(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .build()

    private fun updateNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }
}
