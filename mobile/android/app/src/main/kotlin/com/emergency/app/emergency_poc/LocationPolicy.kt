/**
 * LocationPolicy — single configuration point for the native engine
 * (docs/architecture.md §10: "LocationPolicy را Configuration Object کن").
 *
 * Phase 5 keeps these as one compile-time object; loading them from device
 * settings (so intervals can change without a release) is the remaining
 * Phase 5 item, tracked in docs/phase-5-report.md.
 */
object LocationPolicy {
    /** Emergency mode: conservative fixed interval — battery measurement in Phase 5 may revise it. */
    const val LOCATION_INTERVAL_MS = 10_000L
    const val LOCATION_MIN_DISTANCE_M = 5f

    /** Location freshness watchdog (B-019/B-018 era fixes, formalized here). */
    const val WATCHDOG_PERIOD_MS = 15_000L
    const val STALL_THRESHOLD_MS = 45_000L

    /** Offline queue caps (docs/failure-model.md §4). */
    const val QUEUE_MAX_POINTS = 200
    const val QUEUE_FILE_NAME = "emergency_point_queue.jsonl"
}
