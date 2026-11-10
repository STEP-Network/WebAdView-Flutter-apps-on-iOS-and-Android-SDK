package dk.stepnetwork.webadview_flutter.scope

import dk.stepnetwork.webadview_flutter.core.Cancellable
import dk.stepnetwork.webadview_flutter.core.DelayedScheduler
import dk.stepnetwork.webadview_flutter.core.PerfCounters
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
    /** Ads whose creative has rendered (adSize received); until then no dwell accrues (port of `rendered`). */
    private val rendered = HashSet<String>()
    private var scrollViewBounds: Rect = Rect.ZERO
    private var isAppActive = true
    private var isHostVisible = true

    private var ticker: Cancellable? = null
    private val tickIntervalMs = 100L

    /** Every measurement update (in-process consumers and tests). */
    var onUpdate: (ViewabilityUpdate) -> Unit = {}

    /** Rate-limited stream for the webview bridge. */
    var onJsUpdate: (ViewabilityUpdate) -> Unit = {}

    /**
     * Rate-limited stream for out-of-process hosts (the Dart channel): the
     * first update, boolean transitions and `becameViewable` immediately;
     * ratio/dwell-only changes at most every [hostIntervalMs] with a trailing
     * coalesced send (≤ 15/s per ad; nothing while idle).
     */
    var onHostUpdate: (ViewabilityUpdate) -> Unit = {}
    private val lastSentToHost = HashMap<String, ViewabilityUpdate>()
    private val lastHostSendTime = HashMap<String, Double>()
    private val pendingHost = LinkedHashMap<String, ViewabilityUpdate>()
    private var hostTrailing: Cancellable? = null
    val hostIntervalMs = 67L
    private val hostRatioDelta = 0.05
    private val hostDwellDelta = 0.1

    /** Viewport clips for hosts with viewport resizing enabled. */
    var onClip: (adUnitId: String, clip: ViewportClipCalculator.Clip) -> Unit = { _, _ -> }

    private val lastSentToJS = HashMap<String, ViewabilityUpdate>()
    private val jsRatioDelta = 0.05
    private val lastClip = HashMap<String, ViewportClipCalculator.Clip>()
    /**
     * Clip cadence: while geometry keeps changing, applies are coalesced to
     * at most one per [clipIntervalMs] per ad (trailing edge) — ≤ 10 webview
     * resizes/s for a partially visible ad instead of one per frame. Regime
     * transitions (full / partial / hidden) always apply immediately, and the
     * exact final slice lands within [clipIntervalMs] of the geometry settling.
     */
    private val lastClipEmitTime = HashMap<String, Double>()
    private val pendingClips = LinkedHashMap<String, ViewportClipCalculator.Clip>()
    private var clipTrailing: Cancellable? = null
    val clipIntervalMs = 100L
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
        rendered.remove(adUnitId)
        lastSentToJS.remove(adUnitId)
        lastSentToHost.remove(adUnitId)
        lastHostSendTime.remove(adUnitId)
        pendingHost.remove(adUnitId)
        lastClip.remove(adUnitId)
        lastClipEmitTime.remove(adUnitId)
        pendingClips.remove(adUnitId)
        lastLogTime.remove(adUnitId)
        SNLog.d("[SN] [VIEWABILITY] Unregistered $adUnitId")
        if (engines.isEmpty()) stopTicker() else evaluate()
    }

    /** Re-arms the engine for a new impression (webview recreated or template (re)loaded); parked until [markRendered]. */
    fun resetImpression(adUnitId: String) {
        val engine = engines[adUnitId] ?: return
        engine.reset()
        rendered.remove(adUnitId)
        lastSentToJS.remove(adUnitId)
        lastSentToHost.remove(adUnitId)
        lastClip.remove(adUnitId)
        lastClipEmitTime.remove(adUnitId)
        pendingClips.remove(adUnitId)
        SNLog.d("[SN] [VIEWABILITY] $adUnitId: new impression — verdict re-armed, waiting for the creative to render")
        evaluate()
    }

    /**
     * The host stopped reporting geometry for an ad whose WebView stays alive
     * (retained for re-attachment): drop its frame and reset any in-progress
     * continuous timer; the latched verdict and the rendered flag survive.
     */
    fun detach(adUnitId: String) {
        val engine = engines[adUnitId] ?: return
        if (contentFrames.remove(adUnitId) == null) return
        val now = clock()
        val update = engine.ingest(Rect.ZERO, scrollViewBounds, isAppActive && isHostVisible, now)
        onUpdate(update)
        forwardToJSIfNeeded(update)
        forwardToHostIfNeeded(update, now) // "not visible" reaches a still-subscribed host
        lastSentToHost.remove(adUnitId) // the next host gets a first update
        pendingHost.remove(adUnitId)
        pendingClips.remove(adUnitId)
        SNLog.d("[SN] [VIEWABILITY] $adUnitId: host detached — measurement paused (verdict kept)")
        evaluate()
    }

    /** The creative has rendered (the page reported its adSize): dwell may accrue from now on. */
    fun markRendered(adUnitId: String) {
        if (!engines.containsKey(adUnitId) || !rendered.add(adUnitId)) return
        SNLog.d("[SN] [VIEWABILITY] $adUnitId: creative rendered — measurement started")
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

    /**
     * Batch form for out-of-process hosts (Dart sends the viewport and every
     * ad's creative frame once per rendered frame): ONE evaluation per batch,
     * none if nothing moved.
     */
    fun updateGeometry(viewport: Rect, frames: Map<String, Rect>) {
        var changed = false
        if (scrollViewBounds != viewport) {
            scrollViewBounds = viewport
            changed = true
        }
        for ((adUnitId, frame) in frames) {
            if (contentFrames[adUnitId] == frame) continue
            contentFrames[adUnitId] = frame
            changed = true
        }
        if (changed) evaluate()
    }

    /** Tests: run the trailing clip/host flushes now instead of waiting. */
    fun flushTrailingForTesting() {
        val now = clock()
        clipTrailing?.cancel(); clipTrailing = null
        for ((id, clip) in pendingClips.toList()) emitClip(id, clip, now)
        hostTrailing?.cancel(); hostTrailing = null
        for ((id, update) in pendingHost.toList()) sendToHost(update, now)
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
        clipTrailing?.cancel(); clipTrailing = null
        hostTrailing?.cancel(); hostTrailing = null
        engines.clear()
    }

    private fun evaluate() {
        if (scrollViewBounds.isEmpty) return
        PerfCounters.increment(PerfCounters.Key.EVALUATIONS)
        val viewport = scrollViewBounds
        val now = clock()
        val isActive = isAppActive && isHostVisible
        var anyCounting = false

        // No defensive copy: nothing registers/unregisters from inside a
        // callback (channel calls are asynchronous, clips go to the controller).
        for ((adUnitId, engine) in engines) {
            val frame = contentFrames[adUnitId] ?: continue
            // Clips flow regardless (applied by the controller once rendered); measurement only for rendered ads.
            forwardClipIfNeeded(adUnitId, frame, viewport)
            if (adUnitId !in rendered) continue
            val previous = engine.state
            val update = engine.ingest(frame, viewport, isActive, now)
            if (engine.state is ViewabilityEngine.State.Counting) anyCounting = true

            onUpdate(update)
            forwardToJSIfNeeded(update)
            forwardToHostIfNeeded(update, now)
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
        if (previous != null && !ViewportClipCalculator.differsSignificantly(previous, clip)) {
            pendingClips.remove(adUnitId)
            return
        }
        val regimeChanged = previous == null ||
            previous.isFullyVisible != clip.isFullyVisible ||
            previous.isFullyHidden != clip.isFullyHidden
        val now = clock()
        val last = lastClipEmitTime[adUnitId]
        if (regimeChanged || last == null || now - last >= clipIntervalMs / 1000.0) {
            emitClip(adUnitId, clip, now)
        } else {
            pendingClips[adUnitId] = clip // latest wins; flushed by the trailing timer
            if (clipTrailing == null) {
                clipTrailing = scheduler.schedule(clipIntervalMs) {
                    clipTrailing = null
                    val t = clock()
                    for ((id, c) in pendingClips.toList()) emitClip(id, c, t)
                }
            }
        }
    }

    private fun emitClip(adUnitId: String, clip: ViewportClipCalculator.Clip, now: Double) {
        lastClip[adUnitId] = clip
        lastClipEmitTime[adUnitId] = now
        pendingClips.remove(adUnitId)
        onClip(adUnitId, clip)
    }

    private fun forwardToHostIfNeeded(update: ViewabilityUpdate, now: Double) {
        val id = update.adUnitId
        val last = lastSentToHost[id]
        val urgent = last == null ||
            last.isVisible != update.isVisible ||
            last.isViewable != update.isViewable ||
            last.isAppActive != update.isAppActive ||
            update.becameViewable
        if (urgent) {
            sendToHost(update, now)
            return
        }
        val significant = abs(last!!.ratio - update.ratio) >= hostRatioDelta ||
            abs(last.dwell - update.dwell) >= hostDwellDelta
        if (!significant) return
        val lastTime = lastHostSendTime[id]
        if (lastTime == null || now - lastTime >= hostIntervalMs / 1000.0) {
            sendToHost(update, now)
        } else {
            pendingHost[id] = update
            if (hostTrailing == null) {
                hostTrailing = scheduler.schedule(hostIntervalMs) {
                    hostTrailing = null
                    val t = clock()
                    for ((_, u) in pendingHost.toList()) sendToHost(u, t)
                }
            }
        }
    }

    private fun sendToHost(update: ViewabilityUpdate, now: Double) {
        lastSentToHost[update.adUnitId] = update
        lastHostSendTime[update.adUnitId] = now
        pendingHost.remove(update.adUnitId)
        onHostUpdate(update)
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
