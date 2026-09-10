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

    fun registerAd(adUnitId: String, onLoadState: (AdLoadState) -> Unit, onViewability: (ViewabilityUpdate) -> Unit) {
        scope.register(adUnitId)
        unregisterAd(adUnitId, keepScope = true)
        val subs = ArrayList<() -> Unit>()
        subs += scope.addLoadStateListener(adUnitId, onLoadState)
        subs += scope.addViewabilityListener(adUnitId, onViewability)
        unsubscribers[adUnitId] = subs
    }

    fun unregisterAd(adUnitId: String, keepScope: Boolean = false) {
        unsubscribers.remove(adUnitId)?.forEach { it() }
        if (!keepScope) scope.unregister(adUnitId)
    }

    fun dispose() {
        unsubscribers.values.flatten().forEach { it() }
        unsubscribers.clear()
        scope.dispose()
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
