package dk.stepnetwork.webadview_flutter.platformview

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import dk.stepnetwork.webadview_flutter.ScopeRegistry
import dk.stepnetwork.webadview_flutter.SdkState
import dk.stepnetwork.webadview_flutter.WebAdViewFlutterPlugin
import dk.stepnetwork.webadview_flutter.core.SNLog
import dk.stepnetwork.webadview_flutter.web.AdWebViewController
import dk.stepnetwork.webadview_flutter.web.DebugSettings
import dk.stepnetwork.webadview_flutter.web.RemoteLazyLoadStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates one [AdPlatformView] per Dart platform view. */
class AdPlatformViewFactory(
    private val messenger: BinaryMessenger,
    private val scopes: ScopeRegistry,
    private val currentActivity: () -> Activity?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return AdPlatformView(context, viewId, params, messenger, scopes, currentActivity)
    }
}

/**
 * Hosts one ad's [AdWebViewController] and forwards its per-ad events to
 * Dart on the view's own channel (`dk.stepnetwork.webadview_flutter/ad/<viewId>`).
 */
class AdPlatformView(
    context: Context,
    viewId: Int,
    params: Map<String, Any?>,
    messenger: BinaryMessenger,
    scopes: ScopeRegistry,
    private val currentActivity: () -> Activity?,
) : PlatformView {

    private val channel = MethodChannel(messenger, "${WebAdViewFlutterPlugin.CHANNEL_NAME}/ad/$viewId")
    private val container: FrameLayout
    private var controller: AdWebViewController? = null
    private var entry: dk.stepnetwork.webadview_flutter.ScopeEntry? = null
    private var adUnitId: String? = null

    init {
        val scopeId = params["scopeId"] as? String
        val adUnitId = params["adUnitId"] as? String
        val entry = scopeId?.let { scopes[it] }
        if (scopeId == null || adUnitId == null || entry == null) {
            SNLog.d("[SN] [FLUTTER] platform view $viewId: missing/unknown scope ($scopeId) or adUnitId — empty view")
            container = FrameLayout(context)
        } else {
            @Suppress("UNCHECKED_CAST")
            val targeting = (params["customTargeting"] as? Map<String, Any?>)?.mapNotNull { (k, v) ->
                val values = (v as? List<*>)?.filterIsInstance<String>() ?: (v as? String)?.let { listOf(it) }
                if (values.isNullOrEmpty()) null else k to values
            }?.toMap() ?: emptyMap()
            val viewportResizing = params["viewportResizing"] as? Boolean ?: true
            this.entry = entry
            this.adUnitId = adUnitId
            val callbacks = object : AdWebViewController.Callbacks {
                override fun onAdSize(width: Double, height: Double) {
                    channel.invokeMethod("onAdSize", mapOf("width" to width, "height" to height))
                }

                override fun onActiveViewImpression(slotId: String) {
                    channel.invokeMethod("onActiveViewImpression", mapOf("slotId" to slotId))
                }

                override fun onRenderProcessGone() {
                    channel.invokeMethod("onRenderProcessGone", null)
                }

                override fun openExternal(uri: Uri) {
                    val intent = Intent(Intent.ACTION_VIEW, uri)
                    val activity = currentActivity()
                    val launcher: Context = activity ?: context.applicationContext.also {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    try {
                        launcher.startActivity(intent)
                    } catch (e: ActivityNotFoundException) {
                        SNLog.d("[SN] [NATIVE] External URL handler: no activity for $uri")
                    }
                }
            }
            // A retained controller (the widget was disposed and is back)
            // continues the same impression; otherwise this is a new ad.
            val retained = entry.takeRetained(adUnitId)
            val ctrl = retained?.also { it.callbacks = callbacks } ?: AdWebViewController(
                context = context,
                adUnitId = adUnitId,
                scope = entry.scope,
                customTargeting = targeting,
                viewportResizingEnabled = viewportResizing,
                debugEnabled = DebugSettings(context).isDebugEnabled,
                remoteStore = RemoteLazyLoadStore(context),
                callbacks = callbacks,
            )
            controller = ctrl
            container = ctrl.container
            (container.parent as? android.view.ViewGroup)?.removeView(container) // left over from the previous host
            entry.attach(adUnitId, ctrl)
            if (retained != null) {
                // The new widget starts at its initial size: tell it the real one now.
                retained.lastAdSize?.let { (w, h) -> callbacks.onAdSize(w, h) }
            }
            SNLog.d("[SN] [FLUTTER] platform view $viewId: hosting $adUnitId in scope $scopeId${if (retained != null) " (re-attached)" else ""}")
        }
        if (!SdkState.isInitialized) SdkState.warnNotInitializedOnce()
    }

    override fun getView(): View = container

    override fun dispose() {
        // Keep the ad alive for a widget that comes back (ListView rows).
        channel.setMethodCallHandler(null)
        val ctrl = controller
        controller = null
        if (ctrl == null) return
        val e = entry
        val id = adUnitId
        if (e != null && id != null) {
            if (e.isAttached(id, ctrl)) ctrl.callbacks = NoopCallbacks // ours; a newer view's callbacks must stay
            e.release(id, ctrl) // no-op when a newer view took the controller over
        } else {
            ctrl.dispose()
        }
    }

    private object NoopCallbacks : AdWebViewController.Callbacks {
        override fun onAdSize(width: Double, height: Double) {}
        override fun onActiveViewImpression(slotId: String) {}
        override fun onRenderProcessGone() {}
        override fun openExternal(uri: Uri) {}
    }
}
