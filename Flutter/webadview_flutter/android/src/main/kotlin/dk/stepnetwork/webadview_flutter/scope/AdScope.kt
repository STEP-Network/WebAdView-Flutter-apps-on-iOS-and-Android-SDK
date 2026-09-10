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
        manager.onStateChange = { id, state -> loadStateListeners[id]?.toList()?.forEach { it(state) } }
        tracker.onUpdate = { u -> viewabilityListeners[u.adUnitId]?.toList()?.forEach { it(u) } }
        tracker.onJsUpdate = { u -> jsListeners[u.adUnitId]?.toList()?.forEach { it(u) } }
        tracker.onClip = { id, clip -> clipListeners[id]?.toList()?.forEach { it(clip) } }
    }

    // ---- geometry (dp, Flutter-view coordinates) ----------------------------

    fun updateViewport(rect: Rect) {
        manager.updateScrollViewBounds(rect)
        tracker.updateScrollViewBounds(rect)
    }

    fun updateAdFrame(adUnitId: String, frame: Rect) = manager.updateAdFrame(adUnitId, frame)

    fun updateCreativeFrame(adUnitId: String, frame: Rect) = tracker.updateContentFrame(adUnitId, frame)

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

    fun setHostVisible(visible: Boolean) = tracker.setHostVisible(visible)

    fun setAppActive(active: Boolean) = tracker.setAppActive(active)

    fun loadState(adUnitId: String): AdLoadState = manager.adStates[adUnitId] ?: AdLoadState.NOT_LOADED

    // ---- listeners (a subscription replays the current state, like `$adStates`) --

    fun addLoadStateListener(adUnitId: String, listener: (AdLoadState) -> Unit): () -> Unit {
        loadStateListeners.getOrPut(adUnitId) { ArrayList() }.add(listener)
        manager.adStates[adUnitId]?.let(listener)
        return { loadStateListeners[adUnitId]?.remove(listener) }
    }

    fun addViewabilityListener(adUnitId: String, listener: (ViewabilityUpdate) -> Unit): () -> Unit {
        viewabilityListeners.getOrPut(adUnitId) { ArrayList() }.add(listener)
        return { viewabilityListeners[adUnitId]?.remove(listener) }
    }

    fun addJsListener(adUnitId: String, listener: (ViewabilityUpdate) -> Unit): () -> Unit {
        jsListeners.getOrPut(adUnitId) { ArrayList() }.add(listener)
        return { jsListeners[adUnitId]?.remove(listener) }
    }

    fun addClipListener(adUnitId: String, listener: (ViewportClipCalculator.Clip) -> Unit): () -> Unit {
        clipListeners.getOrPut(adUnitId) { ArrayList() }.add(listener)
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
