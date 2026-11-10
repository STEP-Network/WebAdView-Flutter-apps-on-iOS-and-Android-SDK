package dk.stepnetwork.webadview_flutter.core

/**
 * Debug-only performance counters (port of PerfCounters.swift). Events are a
 * few integer adds; a `[SN] [PERF]` line is emitted through SNLog once per
 * one-second window, lazily on the first event of the next window, and only
 * while the debug flag is on. Nothing is formatted while the flag is off.
 */
object PerfCounters {
    enum class Key { EVALUATIONS, WEBVIEW_RESIZES, JS_VIEWABILITY_SENDS, GEOMETRY_BATCHES_IN, HOST_VIEWABILITY_OUT }

    @Volatile
    var clock: () -> Double = { System.nanoTime() / 1_000_000_000.0 }

    private val counts = IntArray(Key.values().size)
    private var webViewsCreated = 0
    private var webViewCreationMs = 0.0
    private var geometryHandlerMicros = 0.0
    private var geometryHandlerMaxMicros = 0.0
    private var windowStart = -1.0

    @Synchronized
    fun increment(key: Key, amount: Int = 1) {
        rollWindow()
        counts[key.ordinal] += amount
    }

    @Synchronized
    fun recordWebViewCreation(milliseconds: Double) {
        rollWindow()
        webViewsCreated++
        webViewCreationMs += milliseconds
    }

    /** Time spent inside the host's geometry handler (µs), for the batch count. */
    @Synchronized
    fun recordGeometryHandler(micros: Double) {
        rollWindow()
        counts[Key.GEOMETRY_BATCHES_IN.ordinal]++
        geometryHandlerMicros += micros
        if (micros > geometryHandlerMaxMicros) geometryHandlerMaxMicros = micros
    }

    private fun rollWindow() {
        val now = clock()
        if (windowStart < 0) { windowStart = now; return }
        if (now - windowStart < 1.0) return
        flush()
        windowStart = now
    }

    private fun flush() {
        val total = counts.sum() + webViewsCreated
        if (total > 0 && SNLog.isEnabled) {
            val batches = counts[Key.GEOMETRY_BATCHES_IN.ordinal]
            val parts = ArrayList<String>()
            parts += "evaluate/s=${counts[Key.EVALUATIONS.ordinal]}"
            parts += "resizes/s=${counts[Key.WEBVIEW_RESIZES.ordinal]}"
            parts += "js/s=${counts[Key.JS_VIEWABILITY_SENDS.ordinal]}"
            if (batches > 0) parts += "geometryIn/s=$batches (avg ${(geometryHandlerMicros / batches).toInt()}µs, max ${geometryHandlerMaxMicros.toInt()}µs)"
            parts += "viewabilityOut/s=${counts[Key.HOST_VIEWABILITY_OUT.ordinal]}"
            if (webViewsCreated > 0) parts += "webviewsCreated=$webViewsCreated (avg ${(webViewCreationMs / webViewsCreated).toInt()} ms)"
            SNLog.d("[SN] [PERF] " + parts.joinToString(" "))
        }
        counts.fill(0)
        webViewsCreated = 0
        webViewCreationMs = 0.0
        geometryHandlerMicros = 0.0
        geometryHandlerMaxMicros = 0.0
    }
}
