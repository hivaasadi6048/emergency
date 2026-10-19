package com.emergency.app.emergency_poc

import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * File-backed location point queue (Phase 5): survives process death, bounded
 * by [LocationPolicy.QUEUE_MAX_POINTS], serialized as JSON lines.
 *
 * Phase 4 discovery (docs/phase-1/4 reports): OneUI silently suspends delivery
 * and process death loses the in-memory buffer — this queue makes points
 * durable until they are uploaded by the Dart side (C-014 bridge).
 *
 * C-016/C-017: every point carries a capture-time client_uuid (survives
 * restarts — the dedupe key C-02) and the queue exposes acknowledge() so the
 * Dart uploader drains it ONLY after the backend accepted the batch. The queue
 * is therefore always exactly "what the server has not yet confirmed".
 */
class PersistentPointQueue(private val file: File, private val maxPoints: Int) {

    private val points = ArrayDeque<PocLocationPoint>()

    init {
        load()
    }

    @Synchronized
    fun snapshot(): List<PocLocationPoint> = points.toList()

    @Synchronized
    fun add(point: PocLocationPoint) {
        if (points.size >= maxPoints) points.removeFirst()
        points.addLast(point)
        persist()
    }

    /** C-017: remove acked (server-confirmed) points; returns how many were removed.
     *  Unknown uuids are ignored — ack is idempotent. */
    @Synchronized
    fun acknowledge(uuids: Set<String>): Int {
        if (uuids.isEmpty()) return 0
        val before = points.size
        points.removeAll { it.clientUuid in uuids }
        val removed = before - points.size
        if (removed > 0) persist()
        return removed
    }

    @Synchronized
    fun clear() {
        points.clear()
        file.delete()
    }

    private fun load() {
        if (!file.exists()) return
        runCatching {
            file.readLines().filter { it.isNotBlank() }.forEach { line ->
                runCatching { points.addLast(parse(line)) }
                    .onFailure { Log.w("PointQueue", "skipped malformed queue line") }
            }
        }
    }

    private fun persist() {
        runCatching {
            // atomic-ish write (C-017): process death mid-write must not corrupt the queue
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(points.joinToString("\n") { serialize(it) })
            if (!tmp.renameTo(file)) {
                file.writeText(tmp.readText())
                tmp.delete()
            }
        }.onFailure { Log.e("PointQueue", "persist failed", it) }
    }

    private fun serialize(p: PocLocationPoint): String = JSONObject().apply {
        put("uuid", p.clientUuid)
        put("lat", p.latitude)
        put("lng", p.longitude)
        put("acc", p.accuracyM ?: JSONObject.NULL)
        put("spd", p.speedMps ?: JSONObject.NULL)
        put("brg", p.bearingDeg ?: JSONObject.NULL)
        put("ts", p.capturedAtMs)
        put("src", p.source)
    }.toString()

    private fun parse(line: String): PocLocationPoint {
        val j = JSONObject(line)
        return PocLocationPoint(
            latitude = j.getDouble("lat"),
            longitude = j.getDouble("lng"),
            accuracyM = if (j.isNull("acc")) null else j.getDouble("acc").toFloat(),
            speedMps = if (j.isNull("spd")) null else j.getDouble("spd").toFloat(),
            bearingDeg = if (j.isNull("brg")) null else j.getDouble("brg").toFloat(),
            capturedAtMs = j.getLong("ts"),
            source = j.getString("src"),
            // C-016: legacy pre-update lines have no uuid — mint one so no point is lost.
            // One-time caveat: such legacy points may be uploaded once more (documented in phase-5-report).
            clientUuid = if (j.isNull("uuid")) UUID.randomUUID().toString() else j.getString("uuid"),
        )
    }
}
