package dk.stepnetwork.webadview_flutter.core

import kotlin.math.max

/** A scheduled callback that can be cancelled (Handler.postDelayed in production). */
fun interface Cancellable {
    fun cancel()
}

/** Delayed scheduler seam: `schedule(delayMs) { … }`. */
fun interface DelayedScheduler {
    fun schedule(delayMs: Long, action: () -> Unit): Cancellable
}

/**
 * Per-scroll-container lazy-load state machine (port of LazyLoadingManager):
 * notLoaded → fetched → displayed, optional unload with 2 s hysteresis, 67 ms
 * throttle. Geometry in dp; remote thresholds in viewport-height %.
 * Main thread only; the clock and scheduler are injectable for tests.
 */
class LazyLoadingManager(
    var now: () -> Long = System::currentTimeMillis,
    private val scheduler: DelayedScheduler = DelayedScheduler { _, _ -> Cancellable {} },
) {
    val adStates: MutableMap<String, AdLoadState> = LinkedHashMap()
    val adUnitFrames: MutableMap<String, Rect> = LinkedHashMap()
    var scrollViewBounds: Rect = Rect.ZERO
        private set

    var fetchThreshold: Double = 800.0
    var displayThreshold: Double = 200.0
    var unloadThreshold: Double = 1600.0
    var unloadingEnabled: Boolean = false

    /** STEP's remote values (viewport-height %). When set they always win. */
    var remoteConfig: RemoteLazyLoadConfig? = null
        private set

    /** Fires on every state change (replaces the Combine publisher). */
    var onStateChange: (adUnitId: String, state: AdLoadState) -> Unit = { _, _ -> }

    private var throttle: Cancellable? = null
    private var lastUpdateTime: Long = Long.MIN_VALUE / 2
    private val throttleIntervalMs = 67L

    private val unloadCandidates: MutableMap<String, Long> = HashMap()
    private val unloadStabilityDelayMs = 2000L

    fun configure(config: LazyLoadingConfig) {
        fetchThreshold = config.fetchThreshold
        displayThreshold = config.displayThreshold
        unloadThreshold = config.unloadThreshold
        unloadingEnabled = config.unloadingEnabled
    }

    /** Applies a remote config; invalid configs are ignored. Returns whether applied. */
    fun applyRemote(config: RemoteLazyLoadConfig): Boolean {
        if (!config.isValid) {
            SNLog.d("[SN] [LLM] Remote lazyLoad config ignored (invalid values): fetch ${config.fetch}, render ${config.render}")
            return false
        }
        remoteConfig = config
        SNLog.d("[SN] [LLM] Remote lazyLoad thresholds applied: fetch ${config.fetch}% of viewport, render ${config.render}%")
        triggerVisibilityCheck()
        return true
    }

    fun updateAdFrame(adId: String, frame: Rect) {
        val wasNew = adUnitFrames[adId] == null
        if (adUnitFrames[adId] != frame) {
            adUnitFrames[adId] = frame
            triggerVisibilityCheck()
            if (wasNew && !scrollViewBounds.isEmpty) {
                SNLog.d("[SN] [LLM] New ad frame registered for $adId, performing immediate visibility check")
                checkAdVisibility()
            }
        }
    }

    fun updateScrollViewBounds(bounds: Rect) {
        if (scrollViewBounds != bounds) {
            scrollViewBounds = bounds
            triggerVisibilityCheck()
        }
    }

    /** Forgets an ad unit entirely (frame, state, unload candidacy). */
    fun removeAd(adId: String) {
        adUnitFrames.remove(adId)
        unloadCandidates.remove(adId)
        if (adStates.remove(adId) != null) {
            SNLog.d("[SN] [LLM] Ad $adId removed from lazy loading")
        }
    }

    fun dispose() {
        throttle?.cancel()
        throttle = null
    }

    private fun triggerVisibilityCheck() {
        val current = now()
        val sinceLast = current - lastUpdateTime
        if (sinceLast >= throttleIntervalMs) {
            lastUpdateTime = current
            checkAdVisibility()
        } else if (throttle == null) {
            throttle = scheduler.schedule(throttleIntervalMs - sinceLast) {
                throttle = null
                lastUpdateTime = now()
                checkAdVisibility()
            }
        }
    }

    private fun checkAdVisibility() {
        if (scrollViewBounds.isEmpty) {
            SNLog.d("[SN] [LLM] checkAdVisibility: scrollViewBounds is empty. Skipping.")
            return
        }
        val remote = remoteConfig
        val fetchDistance: Double
        val displayDistance: Double
        if (remote != null) {
            fetchDistance = scrollViewBounds.height * remote.fetch / 100.0
            displayDistance = scrollViewBounds.height * remote.render / 100.0
        } else {
            fetchDistance = fetchThreshold
            displayDistance = displayThreshold
        }
        val fetchZone = scrollViewBounds.insetBy(0.0, -fetchDistance)
        val displayZone = scrollViewBounds.insetBy(0.0, -displayDistance)
        // Unload must stay at least as far out as fetch (hysteresis).
        val unloadZone = scrollViewBounds.insetBy(0.0, -max(unloadThreshold, fetchDistance))
        val current = now()

        for ((adId, adFrame) in adUnitFrames.entries.toList()) {
            val state = adStates[adId] ?: AdLoadState.NOT_LOADED
            var newState: AdLoadState? = null

            if (state == AdLoadState.NOT_LOADED && adFrame.intersects(fetchZone)) {
                newState = AdLoadState.FETCHED
                unloadCandidates.remove(adId)
            } else if (state == AdLoadState.FETCHED && adFrame.intersects(displayZone)) {
                newState = AdLoadState.DISPLAYED
                unloadCandidates.remove(adId)
            } else if ((state == AdLoadState.FETCHED || state == AdLoadState.DISPLAYED) &&
                !adFrame.intersects(unloadZone) && unloadingEnabled
            ) {
                val since = unloadCandidates[adId]
                if (since == null) {
                    unloadCandidates[adId] = current
                    SNLog.d("[SN] [LLM] Ad $adId marked as unload candidate")
                } else if (current - since >= unloadStabilityDelayMs) {
                    newState = AdLoadState.UNLOADED
                    unloadCandidates.remove(adId)
                }
            } else if (state == AdLoadState.UNLOADED && adFrame.intersects(fetchZone)) {
                newState = AdLoadState.NOT_LOADED
                unloadCandidates.remove(adId)
            } else {
                unloadCandidates.remove(adId)
            }

            if (newState != null && newState != state) {
                SNLog.d("[SN] [LLM] Ad $adId TRANSITION: ${state.wireName} -> ${newState.wireName}")
                adStates[adId] = newState
                onStateChange(adId, newState)
            }
        }
    }
}
