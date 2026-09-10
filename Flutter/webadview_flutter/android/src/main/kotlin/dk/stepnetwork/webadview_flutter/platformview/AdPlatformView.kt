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
            val ctrl = AdWebViewController(
                context = context,
                adUnitId = adUnitId,
                scope = entry.scope,
                customTargeting = targeting,
                viewportResizingEnabled = viewportResizing,
                debugEnabled = DebugSettings(context).isDebugEnabled,
                remoteStore = RemoteLazyLoadStore(context),
                callbacks = object : AdWebViewController.Callbacks {
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
                },
            )
            controller = ctrl
            container = ctrl.container
            container.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> ctrl.onContainerLayout() }
            SNLog.d("[SN] [FLUTTER] platform view $viewId: hosting $adUnitId in scope $scopeId")
        }
        if (!SdkState.isInitialized) SdkState.warnNotInitializedOnce()
    }

    override fun getView(): View = container

    override fun dispose() {
        controller?.dispose()
        controller = null
        channel.setMethodCallHandler(null)
    }
}
