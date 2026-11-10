package dk.stepnetwork.webadview_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import dk.stepnetwork.webadview_flutter.core.AdLoadState
import dk.stepnetwork.webadview_flutter.core.Cancellable
import dk.stepnetwork.webadview_flutter.core.DelayedScheduler
import dk.stepnetwork.webadview_flutter.core.LazyLoadingConfig
import dk.stepnetwork.webadview_flutter.core.SNLog
import dk.stepnetwork.webadview_flutter.core.TemplateUrl
import dk.stepnetwork.webadview_flutter.core.ViewabilityUpdate
import dk.stepnetwork.webadview_flutter.scope.AdScope
import dk.stepnetwork.webadview_flutter.web.AdWebViewController
import dk.stepnetwork.webadview_flutter.web.RemoteLazyLoadStore

/** Main-looper scheduler for the throttle, ticker and polls. */
class MainThreadScheduler : DelayedScheduler {
    private val handler = Handler(Looper.getMainLooper())
    override fun schedule(delayMs: Long, action: () -> Unit): Cancellable {
        val runnable = Runnable(action)
        handler.postDelayed(runnable, delayMs)
        return Cancellable { handler.removeCallbacks(runnable) }
    }
}

/** One entry per Dart `LazyLoadAdScope`: the scope plus its Dart-facing subscriptions. */
class ScopeEntry(val scope: AdScope) {
    private val unsubscribers = HashMap<String, MutableList<() -> Unit>>()
    var isDisposed = false
        private set

    /**
     * Ad controllers kept alive after their Flutter widget was disposed (a
     * `ListView.builder` row scrolled out of the cache extent), oldest first.
     * A widget for the same ad unit re-attaches the controller instead of
     * creating a new WebView and running a new ad request — the same
     * impression simply continues. Bounded; the oldest is destroyed when the
     * pool is full, everything when the scope goes.
     */
    private val retained = ArrayList<Pair<String, AdWebViewController>>()
    /**
     * The controller each live platform view shows. Flutter may create the
     * replacement platform view BEFORE it disposes the old one (same ad unit,
     * widget rebuilt within a frame): the new view takes the controller over,
     * and the old view's dispose must then leave it alone.
     */
    private val attached = HashMap<String, AdWebViewController>()

    /** [onViewability] null = Dart has no listener for this ad: no channel traffic for it. */
    fun registerAd(adUnitId: String, onLoadState: (AdLoadState) -> Unit, onViewability: ((ViewabilityUpdate) -> Unit)?) {
        scope.register(adUnitId)
        unregisterAd(adUnitId, keepScope = true)
        val subs = ArrayList<() -> Unit>()
        subs += scope.addLoadStateListener(adUnitId, onLoadState)
        if (onViewability != null) subs += scope.addViewabilityListener(adUnitId, onViewability)
        unsubscribers[adUnitId] = subs
    }

    /** The Dart widget is gone: a loaded ad is only DETACHED (state + WebView stay, see [retained]). */
    fun unregisterAd(adUnitId: String, keepScope: Boolean = false) {
        unsubscribers.remove(adUnitId)?.forEach { it() }
        if (keepScope) return
        when (scope.loadState(adUnitId)) {
            AdLoadState.FETCHED, AdLoadState.DISPLAYED -> scope.detach(adUnitId)
            else -> scope.unregister(adUnitId)
        }
    }

    /** A platform view starts showing [controller] for [adUnitId]. */
    fun attach(adUnitId: String, controller: AdWebViewController) {
        attached[adUnitId] = controller
    }

    fun isAttached(adUnitId: String, controller: AdWebViewController): Boolean = attached[adUnitId] === controller

    /**
     * The platform view that showed [controller] was disposed: keep it for a
     * later widget of the same ad unit — unless a newer platform view has
     * already taken it over, in which case nothing happens.
     */
    fun release(adUnitId: String, controller: AdWebViewController) {
        if (attached[adUnitId] !== controller) return // superseded: the new view owns it
        attached.remove(adUnitId)
        park(adUnitId, controller)
    }

    private fun park(adUnitId: String, controller: AdWebViewController) {
        if (isDisposed || controller.isDisposed) {
            if (!controller.isDisposed) controller.dispose()
            return
        }
        retained.removeAll { it.first == adUnitId }
        retained.add(adUnitId to controller)
        while (retained.size > RETAINED_LIMIT) {
            val (evictedId, evicted) = retained.removeAt(0)
            evicted.dispose()
            scope.unregister(evictedId)
            SNLog.d("[SN] [FLUTTER] $evictedId: retained pool full — unloaded (will reload when shown again)")
        }
        SNLog.d("[SN] [FLUTTER] $adUnitId: widget disposed — WebView retained for re-attachment (${retained.size}/$RETAINED_LIMIT)")
    }

    /** A new platform view for [adUnitId]: the retained controller if there is one, else the one a not-yet-disposed view still shows. */
    fun takeRetained(adUnitId: String): AdWebViewController? {
        val index = retained.indexOfFirst { it.first == adUnitId }
        if (index >= 0) {
            val controller = retained.removeAt(index).second
            if (controller.isDisposed) return null
            SNLog.d("[SN] [FLUTTER] $adUnitId: widget is back — re-attached the retained WebView (no new ad request)")
            return controller
        }
        val live = attached[adUnitId]
        if (live != null && !live.isDisposed) {
            SNLog.d("[SN] [FLUTTER] $adUnitId: widget rebuilt before Flutter disposed the old view — moved the WebView over (no new ad request)")
            return live
        }
        return null
    }

    fun dispose() {
        isDisposed = true
        unsubscribers.values.flatten().forEach { it() }
        unsubscribers.clear()
        retained.forEach { it.second.dispose() }
        retained.clear()
        attached.values.forEach { if (!it.isDisposed) it.dispose() }
        attached.clear()
        scope.dispose()
    }

    companion object {
        const val RETAINED_LIMIT = 4
    }
}

/** Scopes keyed by the Dart-generated id. Main thread only. */
class ScopeRegistry(private val context: Context) {
    private val entries = LinkedHashMap<String, ScopeEntry>()
    private val scheduler = MainThreadScheduler()

    operator fun get(scopeId: String): ScopeEntry? = entries[scopeId]

    fun create(scopeId: String, config: LazyLoadingConfig): ScopeEntry {
        entries[scopeId]?.let {
            SNLog.d("[SN] [FLUTTER] createScope: scope $scopeId already exists — reusing")
            return it
        }
        // Cached remote thresholds apply before any page has loaded (LazyLoadAdInternalModifier.onAppear).
        val cached = SdkState.adTemplateUrl?.let(TemplateUrl::host)?.let { RemoteLazyLoadStore(context).load(it) }
        val entry = ScopeEntry(AdScope(config, cached, scheduler))
        entries[scopeId] = entry
        return entry
    }

    fun dispose(scopeId: String) {
        entries.remove(scopeId)?.dispose()
    }

    fun disposeAll() {
        entries.values.forEach { it.dispose() }
        entries.clear()
    }

    fun setAppActive(active: Boolean) {
        entries.values.forEach { it.scope.setAppActive(active) }
    }
}
