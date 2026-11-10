package dk.stepnetwork.webadview_flutter.scope

import dk.stepnetwork.webadview_flutter.core.AdLoadState
import dk.stepnetwork.webadview_flutter.core.DelayedScheduler
import dk.stepnetwork.webadview_flutter.core.LazyLoadingConfig
import dk.stepnetwork.webadview_flutter.core.LazyLoadingManager
import dk.stepnetwork.webadview_flutter.core.Rect
import dk.stepnetwork.webadview_flutter.core.RemoteLazyLoadConfig
import dk.stepnetwork.webadview_flutter.core.ViewabilityMode
import dk.stepnetwork.webadview_flutter.core.ViewabilityUpdate
import dk.stepnetwork.webadview_flutter.core.ViewportClipCalculator
import java.util.concurrent.CopyOnWriteArrayList

/**
 * One scope per Dart `LazyLoadAdScope` (port of WebAdScope): the container's
 * lazy-load state machine plus viewability measurement, fed with the
 * geometry Dart reports. Per-ad listeners fan the outputs out to the Dart
 * channel and to the ad's webview controller.
 */
class AdScope(
    config: LazyLoadingConfig,
    cachedRemote: RemoteLazyLoadConfig?,
    scheduler: DelayedScheduler,
    now: () -> Long = System::currentTimeMillis,
    clock: () -> Double = { System.nanoTime() / 1_000_000_000.0 },
) {
    val manager = LazyLoadingManager(now, scheduler)
    val tracker = ViewabilityTracker(clock, scheduler)

    /** Per-ad load-state listeners (Dart + the webview controller). */
    private val loadStateListeners = HashMap<String, MutableList<(AdLoadState) -> Unit>>()
    private val viewabilityListeners = HashMap<String, MutableList<(ViewabilityUpdate) -> Unit>>()
    private val jsListeners = HashMap<String, MutableList<(ViewabilityUpdate) -> Unit>>()
    private val clipListeners = HashMap<String, MutableList<(ViewportClipCalculator.Clip) -> Unit>>()

    init {
        manager.configure(config)
        if (cachedRemote != null) manager.applyRemote(cachedRemote)
        manager.onStateChange = { id, state -> loadStateListeners[id]?.forEach { it(state) } }
        // Hosts get the rate-limited stream (see ViewabilityTracker.onHostUpdate).
        tracker.onHostUpdate = { u -> viewabilityListeners[u.adUnitId]?.forEach { it(u) } }
        tracker.onJsUpdate = { u -> jsListeners[u.adUnitId]?.forEach { it(u) } }
        tracker.onClip = { id, clip -> clipListeners[id]?.forEach { it(clip) } }
    }

    /** Geometry of one ad for [updateGeometry]. */
    class AdGeometry(
        /** Whole ad frame, label included (lazy loading). */
        val frame: Rect,
        /** Creative-only frame (viewability). */
        val creative: Rect,
    )

    // ---- geometry (dp, Flutter-view coordinates) ----------------------------

    fun updateViewport(rect: Rect) {
        manager.updateScrollViewBounds(rect)
        tracker.updateScrollViewBounds(rect)
    }

    fun updateAdFrame(adUnitId: String, frame: Rect) = manager.updateAdFrame(adUnitId, frame)

    fun updateCreativeFrame(adUnitId: String, frame: Rect) = tracker.updateContentFrame(adUnitId, frame)

    /**
     * Preferred entry point: the viewport and every ad's geometry in ONE call
     * per rendered frame — each state machine runs exactly one pass per batch
     * (the per-item methods above each run a pass of their own).
     */
    fun updateGeometry(viewport: Rect, ads: Map<String, AdGeometry>) {
        val frames = HashMap<String, Rect>(ads.size * 2)
        val creatives = HashMap<String, Rect>(ads.size * 2)
        for ((id, g) in ads) {
            frames[id] = g.frame
            creatives[id] = g.creative
        }
        manager.updateGeometry(viewport, frames)
        tracker.updateGeometry(viewport, creatives)
    }

    // ---- registration ---------------------------------------------------------

    fun register(adUnitId: String) = tracker.register(adUnitId, ViewabilityMode.DISPLAY)

    fun unregister(adUnitId: String) {
        manager.removeAd(adUnitId)
        tracker.unregister(adUnitId)
        loadStateListeners.remove(adUnitId)
        viewabilityListeners.remove(adUnitId)
        jsListeners.remove(adUnitId)
        clipListeners.remove(adUnitId)
    }

    /**
     * The host stopped reporting geometry for an ad whose controller it keeps
     * alive for re-attachment (disposed widget): load state, impression and
     * verdict survive; nothing is measured or transitioned until geometry
     * is reported again.
     */
    fun detach(adUnitId: String) {
        manager.detachAd(adUnitId)
        tracker.detach(adUnitId)
    }

    fun setHostVisible(visible: Boolean) = tracker.setHostVisible(visible)

    fun setAppActive(active: Boolean) = tracker.setAppActive(active)

    fun loadState(adUnitId: String): AdLoadState = manager.adStates[adUnitId] ?: AdLoadState.NOT_LOADED

    // ---- listeners (a subscription replays the current state, like `$adStates`) --

    fun addLoadStateListener(adUnitId: String, listener: (AdLoadState) -> Unit): () -> Unit {
        loadStateListeners.getOrPut(adUnitId) { CopyOnWriteArrayList() }.add(listener)
        manager.adStates[adUnitId]?.let(listener)
        return { loadStateListeners[adUnitId]?.remove(listener) }
    }

    fun addViewabilityListener(adUnitId: String, listener: (ViewabilityUpdate) -> Unit): () -> Unit {
        viewabilityListeners.getOrPut(adUnitId) { CopyOnWriteArrayList() }.add(listener)
        return { viewabilityListeners[adUnitId]?.remove(listener) }
    }

    fun addJsListener(adUnitId: String, listener: (ViewabilityUpdate) -> Unit): () -> Unit {
        jsListeners.getOrPut(adUnitId) { CopyOnWriteArrayList() }.add(listener)
        return { jsListeners[adUnitId]?.remove(listener) }
    }

    fun addClipListener(adUnitId: String, listener: (ViewportClipCalculator.Clip) -> Unit): () -> Unit {
        clipListeners.getOrPut(adUnitId) { CopyOnWriteArrayList() }.add(listener)
        return { clipListeners[adUnitId]?.remove(listener) }
    }

    fun dispose() {
        manager.dispose()
        tracker.dispose()
        loadStateListeners.clear()
        viewabilityListeners.clear()
        jsListeners.clear()
        clipListeners.clear()
    }
}
