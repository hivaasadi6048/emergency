package com.emergency.app.emergency_poc

import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * File-backed location point queue (Phase 5): survives process death, bounded
 * by [LocationPolicy.QUEUE_MAX_POINTS], serialized as JSON lines.
 *
 * Phase 4 discovery (docs/phase-1/4 reports): OneUI silently suspends delivery
 * and process death loses the in-memory buffer — this queue makes points
 * durable until they are uploaded by the Dart side (C-014 bridge).
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
            file.writeText(points.joinToString("\n") { serialize(it) })
        }.onFailure { Log.e("PointQueue", "persist failed", it) }
    }

    private fun serialize(p: PocLocationPoint): String = JSONObject().apply {
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
        )
    }
}
