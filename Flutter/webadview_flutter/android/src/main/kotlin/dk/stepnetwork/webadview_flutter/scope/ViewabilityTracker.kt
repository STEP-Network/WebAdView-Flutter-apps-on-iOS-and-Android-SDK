package dk.stepnetwork.webadview_flutter.scope

import dk.stepnetwork.webadview_flutter.core.Cancellable
import dk.stepnetwork.webadview_flutter.core.DelayedScheduler
import dk.stepnetwork.webadview_flutter.core.Rect
import dk.stepnetwork.webadview_flutter.core.SNLog
import dk.stepnetwork.webadview_flutter.core.ViewabilityEngine
import dk.stepnetwork.webadview_flutter.core.ViewabilityMode
import dk.stepnetwork.webadview_flutter.core.ViewabilityUpdate
import dk.stepnetwork.webadview_flutter.core.ViewportClipCalculator
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Per-scroll-container viewability orchestrator (port of ViewabilityTracker):
 * one engine per ad, a 10 Hz ticker that runs ONLY while some engine is
 * counting, app-active + host-visible gating, and the emit policies for the
 * webview bridge (boolean transitions, ≥5 % ratio delta) and viewport clips
 * (2 dp tolerance). Main thread only; clock and ticker are injectable.
 */
class ViewabilityTracker(
    var clock: () -> Double = { System.nanoTime() / 1_000_000_000.0 },
    private val scheduler: DelayedScheduler = DelayedScheduler { _, _ -> Cancellable {} },
) {
    private val engines = LinkedHashMap<String, ViewabilityEngine>()
    private val contentFrames = HashMap<String, Rect>()
    private var scrollViewBounds: Rect = Rect.ZERO
    private var isAppActive = true
    private var isHostVisible = true

    private var ticker: Cancellable? = null
    private val tickIntervalMs = 100L

    /** Every measurement update (drives the Dart onViewabilityChange). */
    var onUpdate: (ViewabilityUpdate) -> Unit = {}

    /** Rate-limited stream for the webview bridge. */
    var onJsUpdate: (ViewabilityUpdate) -> Unit = {}

    /** Viewport clips for hosts with viewport resizing enabled. */
    var onClip: (adUnitId: String, clip: ViewportClipCalculator.Clip) -> Unit = { _, _ -> }

    private val lastSentToJS = HashMap<String, ViewabilityUpdate>()
    private val jsRatioDelta = 0.05
    private val lastClip = HashMap<String, ViewportClipCalculator.Clip>()
    private val lastLogTime = HashMap<String, Double>()
    private val logInterval = 0.25

    fun register(adUnitId: String, mode: ViewabilityMode) {
        val existing = engines[adUnitId]
        if (existing != null) {
            if (existing.mode != mode) {
                SNLog.d("[SN] [VIEWABILITY] $adUnitId: already registered as ${existing.mode.wireName} — ignoring conflicting mode ${mode.wireName} (first registration wins)")
            }
            return
        }
        engines[adUnitId] = ViewabilityEngine(adUnitId, mode)
        SNLog.d("[SN] [VIEWABILITY] Registered $adUnitId — mode: ${mode.wireName}, needs ≥50% for ${"%.1f".format(mode.requiredDurationSeconds)}s continuous")
        evaluate()
    }

    fun unregister(adUnitId: String) {
        if (engines.remove(adUnitId) == null) return
        contentFrames.remove(adUnitId)
        lastSentToJS.remove(adUnitId)
        lastClip.remove(adUnitId)
        lastLogTime.remove(adUnitId)
        SNLog.d("[SN] [VIEWABILITY] Unregistered $adUnitId")
        if (engines.isEmpty()) stopTicker() else evaluate()
    }

    /** Re-arms the engine for a new impression (webview recreated). */
    fun resetImpression(adUnitId: String) {
        val engine = engines[adUnitId] ?: return
        engine.reset()
        lastSentToJS.remove(adUnitId)
        lastClip.remove(adUnitId)
        SNLog.d("[SN] [VIEWABILITY] $adUnitId: new impression — verdict re-armed")
        evaluate()
    }

    fun updateContentFrame(adUnitId: String, frame: Rect) {
        if (contentFrames[adUnitId] == frame) return
        contentFrames[adUnitId] = frame
        evaluate()
    }

    fun updateScrollViewBounds(bounds: Rect) {
        if (scrollViewBounds == bounds) return
        scrollViewBounds = bounds
        evaluate()
    }

    fun setAppActive(active: Boolean) {
        if (isAppActive == active) return
        isAppActive = active
        SNLog.d(if (active) "[SN] [VIEWABILITY] app became active — measurement resumed"
        else "[SN] [VIEWABILITY] app resigned active — all continuous in-view timers RESET")
        evaluate()
    }

    fun setHostVisible(visible: Boolean) {
        if (isHostVisible == visible) return
        isHostVisible = visible
        SNLog.d(if (visible) "[SN] [VIEWABILITY] host screen visible — measurement resumed"
        else "[SN] [VIEWABILITY] host screen covered — all continuous in-view timers RESET")
        evaluate()
    }

    fun dispose() {
        stopTicker()
        engines.clear()
    }

    private fun evaluate() {
        if (scrollViewBounds.isEmpty) return
        val viewport = scrollViewBounds
        val now = clock()
        val isActive = isAppActive && isHostVisible
        var anyCounting = false

        for ((adUnitId, engine) in engines.entries.toList()) {
            val frame = contentFrames[adUnitId] ?: continue
            val previous = engine.state
            val update = engine.ingest(frame, viewport, isActive, now)
            if (engine.state is ViewabilityEngine.State.Counting) anyCounting = true

            onUpdate(update)
            forwardToJSIfNeeded(update)
            forwardClipIfNeeded(adUnitId, frame, viewport)
            log(update, previous, engine.state, now)
        }

        if (anyCounting && isActive) startTickerIfNeeded() else stopTicker()
    }

    private fun startTickerIfNeeded() {
        if (ticker != null) return
        ticker = scheduler.schedule(tickIntervalMs) {
            ticker = null
            evaluate()
        }
    }

    private fun stopTicker() {
        ticker?.cancel()
        ticker = null
    }

    private fun forwardClipIfNeeded(adUnitId: String, adFrame: Rect, viewport: Rect) {
        val clip = ViewportClipCalculator.clip(adFrame, viewport)
        val previous = lastClip[adUnitId]
        if (previous != null && !ViewportClipCalculator.differsSignificantly(previous, clip)) return
        lastClip[adUnitId] = clip
        onClip(adUnitId, clip)
    }

    private fun forwardToJSIfNeeded(update: ViewabilityUpdate) {
        val last = lastSentToJS[update.adUnitId]
        val booleanTransition = last == null ||
            last.isVisible != update.isVisible ||
            last.isViewable != update.isViewable ||
            last.isAppActive != update.isAppActive
        val ratioJump = last == null || abs(last.ratio - update.ratio) >= jsRatioDelta
        if (booleanTransition || update.becameViewable || ratioJump) {
            lastSentToJS[update.adUnitId] = update
            onJsUpdate(update)
        }
    }

    private fun log(update: ViewabilityUpdate, previous: ViewabilityEngine.State, current: ViewabilityEngine.State, now: Double) {
        if (!SNLog.isEnabled) return
        val percent = (update.ratio * 100).roundToInt()
        val duration = "%.2f".format(update.mode.requiredDurationSeconds)
        if (current != previous) {
            when (current) {
                is ViewabilityEngine.State.Counting ->
                    SNLog.d("[SN] [VIEWABILITY] ${update.adUnitId}: $percent% visible — ≥50% reached, continuous timer STARTED (needs ${"%.1f".format(update.mode.requiredDurationSeconds)}s, ${update.mode.wireName})")
                ViewabilityEngine.State.Idle ->
                    SNLog.d(if (!update.isAppActive) "[SN] [VIEWABILITY] ${update.adUnitId}: app inactive — continuous timer RESET"
                    else "[SN] [VIEWABILITY] ${update.adUnitId}: dipped to $percent% (<50%) — continuous timer RESET")
                ViewabilityEngine.State.Viewable ->
                    SNLog.d("[SN] [VIEWABILITY] ${update.adUnitId}: $percent% visible | in-view ${"%.2f".format(update.dwell)}s / ${duration}s (${update.mode.wireName}) | ✅ VIEWABLE (latched)")
            }
            lastLogTime[update.adUnitId] = now
            return
        }
        if (current is ViewabilityEngine.State.Counting) {
            val last = lastLogTime[update.adUnitId] ?: 0.0
            if (now - last >= logInterval) {
                lastLogTime[update.adUnitId] = now
                val verdict = if (update.isViewable) "VIEWABLE" else "NOT VIEWABLE"
                SNLog.d("[SN] [VIEWABILITY] ${update.adUnitId}: $percent% visible | in-view ${"%.2f".format(update.dwell)}s / ${duration}s (${update.mode.wireName}) | $verdict")
            }
        }
    }
}
