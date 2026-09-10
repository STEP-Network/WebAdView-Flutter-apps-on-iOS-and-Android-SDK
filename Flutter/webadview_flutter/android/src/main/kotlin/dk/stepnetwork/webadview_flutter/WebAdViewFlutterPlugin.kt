package dk.stepnetwork.webadview_flutter

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import androidx.fragment.app.FragmentActivity
import dk.stepnetwork.webadview_flutter.consent.DidomiConsentProvider
import dk.stepnetwork.webadview_flutter.core.AdLoadState
import dk.stepnetwork.webadview_flutter.core.LazyLoadingConfig
import dk.stepnetwork.webadview_flutter.core.Rect
import dk.stepnetwork.webadview_flutter.core.SNLog
import dk.stepnetwork.webadview_flutter.core.ViewabilityUpdate
import dk.stepnetwork.webadview_flutter.platformview.AdPlatformViewFactory
import dk.stepnetwork.webadview_flutter.web.DebugSettings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android half of the `webadview_flutter` plugin. Same channel and method set
 * as iOS (see `lib/src/platform/method_channel_webadview.dart`): Dart owns
 * all geometry; native runs the ported lazy-load and viewability engines.
 *
 * NOTE: the file name must stay exactly `WebAdViewFlutterPlugin.kt` (the
 * Flutter tool looks it up by pubspec `pluginClass`); on case-insensitive
 * file systems it collides with the template's `WebadviewFlutterPlugin.kt`.
 */
class WebAdViewFlutterPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var scopes: ScopeRegistry
    private lateinit var application: Application
    private lateinit var debugSettings: DebugSettings
    private var activity: Activity? = null
    private var lifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        application = binding.applicationContext as Application
        scopes = ScopeRegistry(binding.applicationContext)
        debugSettings = DebugSettings(binding.applicationContext)
        SNLog.sink = { Log.d(LOG_TAG, it) }
        SNLog.errorSink = { Log.e(LOG_TAG, it) }
        SNLog.isEnabled = debugSettings.isDebugEnabled
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            AdPlatformViewFactory(binding.binaryMessenger, scopes) { activity },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scopes.disposeAll()
    }

    // ---- ActivityAware: Didomi UI host + app-active gating --------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        (binding.activity as? FragmentActivity)?.let { if (SdkState.isInitialized) SdkState.setupConsentUI(it) }
        installLifecycleCallbacks(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        // The notice is a DialogFragment; the restored FragmentManager re-shows it. Only refresh the reference.
        activity = binding.activity
        installLifecycleCallbacks(binding.activity)
    }

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        removeLifecycleCallbacks()
        (activity as? FragmentActivity)?.let(SdkState::clearConsentUIHost)
        activity = null
        scopes.setAppActive(false)
    }

    /** onPause/onResume of the Flutter activity ≈ willResignActive/didBecomeActive. */
    private fun installLifecycleCallbacks(target: Activity) {
        removeLifecycleCallbacks()
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(a: Activity) { if (a === target) scopes.setAppActive(true) }
            override fun onActivityPaused(a: Activity) { if (a === target) scopes.setAppActive(false) }
            override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityStopped(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {}
        }
        application.registerActivityLifecycleCallbacks(callbacks)
        lifecycleCallbacks = callbacks
    }

    private fun removeLifecycleCallbacks() {
        lifecycleCallbacks?.let(application::unregisterActivityLifecycleCallbacks)
        lifecycleCallbacks = null
    }

    // ---- Dispatch ---------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> initialize(call, result)
                "showConsentPreferences" -> {
                    SdkState.consentProvider?.showPreferences(activity as? FragmentActivity)
                    result.success(null)
                }
                "setDebugEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    debugSettings.isDebugEnabled = enabled
                    SNLog.isEnabled = enabled
                    result.success(null)
                }
                "isDebugEnabled" -> result.success(debugSettings.isDebugEnabled)
                "createScope" -> {
                    val scopeId = call.argument<String>("scopeId") ?: return result.badArgs("scopeId")
                    val config = LazyLoadingConfig(
                        fetchThreshold = call.argument<Number>("fetchThreshold")?.toDouble() ?: 800.0,
                        displayThreshold = call.argument<Number>("displayThreshold")?.toDouble() ?: 200.0,
                        unloadThreshold = call.argument<Number>("unloadThreshold")?.toDouble() ?: 1600.0,
                        unloadingEnabled = call.argument<Boolean>("unloadingEnabled") ?: false,
                    )
                    scopes.create(scopeId, config)
                    SNLog.d("[SN] [FLUTTER] createScope $scopeId (fetch ${config.fetchThreshold.toInt()} / display ${config.displayThreshold.toInt()} / unload ${config.unloadThreshold.toInt()}, unloading ${config.unloadingEnabled})")
                    result.success(null)
                }
                "disposeScope" -> {
                    val scopeId = call.argument<String>("scopeId") ?: return result.badArgs("scopeId")
                    scopes.dispose(scopeId)
                    result.success(null)
                }
                "setScopeVisible" -> {
                    val scopeId = call.argument<String>("scopeId") ?: return result.badArgs("scopeId")
                    scopes[scopeId]?.scope?.setHostVisible(call.argument<Boolean>("visible") ?: true)
                    result.success(null)
                }
                "registerAd" -> registerAd(call, result)
                "unregisterAd" -> {
                    val scopeId = call.argument<String>("scopeId") ?: return result.badArgs("scopeId")
                    val adUnitId = call.argument<String>("adUnitId") ?: return result.badArgs("adUnitId")
                    scopes[scopeId]?.unregisterAd(adUnitId)
                    result.success(null)
                }
                "updateGeometry" -> updateGeometry(call, result)
                "acceptAllConsentForTesting" -> {
                    // Debug-only in the Dart API (kDebugMode gate); the native call exists for automation.
                    (SdkState.consentProvider as? DidomiConsentProvider)?.acceptAllForTesting()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("internal", e.message, null)
        }
    }

    private fun MethodChannel.Result.badArgs(what: String) =
        error("bad_args", "Missing or invalid argument: $what", null)

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        // Hot restart: Dart state is gone, this instance survives — drop every scope.
        scopes.disposeAll()
        if (SdkState.isInitialized) {
            SNLog.d("[SN] [FLUTTER] initialize: native SDK already initialized (hot restart?) — keeping the existing configuration")
            result.success(mapOf("alreadyInitialized" to true))
            return
        }
        val templateUrl = call.argument<String>("adTemplateUrl")
        if (templateUrl.isNullOrBlank() || android.net.Uri.parse(templateUrl).scheme == null) return result.badArgs("adTemplateUrl")
        val mode = when (call.argument<String>("mode") ?: "didomi") {
            "didomi" -> SdkState.Mode.DIDOMI
            "tcf" -> SdkState.Mode.TCF
            "appDidomi" -> SdkState.Mode.APP_DIDOMI
            else -> return result.error("bad_args", "Unknown consent mode", null)
        }
        val apiKey = call.argument<String>("didomiApiKey")
        if (mode == SdkState.Mode.DIDOMI && apiKey.isNullOrBlank()) return result.badArgs("didomiApiKey")
        if (mode == SdkState.Mode.DIDOMI && activity != null && activity !is FragmentActivity) {
            // Didomi's notice/preferences need a FragmentActivity; FlutterActivity is not one.
            result.error(
                "activity_not_fragment",
                "The Didomi consent notice needs a FragmentActivity: make MainActivity extend FlutterFragmentActivity (see the plugin README).",
                null,
            )
            return
        }
        SdkState.initialize(
            application = application,
            mode = mode,
            adTemplateUrl = templateUrl,
            didomiApiKey = apiKey,
            didomiDisableRemoteConfig = call.argument<Boolean>("didomiDisableRemoteConfig") ?: false,
        )
        (activity as? FragmentActivity)?.let(SdkState::setupConsentUI)
        result.success(mapOf("alreadyInitialized" to false))
    }

    private fun registerAd(call: MethodCall, result: MethodChannel.Result) {
        val scopeId = call.argument<String>("scopeId") ?: return result.badArgs("scopeId")
        val adUnitId = call.argument<String>("adUnitId") ?: return result.badArgs("adUnitId")
        val entry = scopes[scopeId] ?: return result.error("unknown_scope", "No scope $scopeId — call createScope first", null)
        entry.registerAd(
            adUnitId,
            onLoadState = { state: AdLoadState ->
                channel.invokeMethod("onLoadState", mapOf("scopeId" to scopeId, "adUnitId" to adUnitId, "state" to state.wireName))
            },
            onViewability = { u: ViewabilityUpdate ->
                channel.invokeMethod(
                    "onViewability",
                    mapOf(
                        "scopeId" to scopeId, "adUnitId" to u.adUnitId, "ratio" to u.ratio, "isVisible" to u.isVisible,
                        "dwell" to u.dwell, "isViewable" to u.isViewable, "becameViewable" to u.becameViewable,
                        "isAppActive" to u.isAppActive, "timestamp" to u.timestamp, "mode" to u.mode.wireName,
                    ),
                )
            },
        )
        result.success(null)
    }

    private fun updateGeometry(call: MethodCall, result: MethodChannel.Result) {
        val scopeId = call.argument<String>("scopeId") ?: return result.badArgs("scopeId")
        val entry = scopes[scopeId] ?: return result.success(null) // stale after disposeScope
        val viewport = rect(call.argument<List<*>>("viewport")) ?: return result.badArgs("viewport")
        val ads = call.argument<Map<*, *>>("ads")
        if (ads != null) {
            for ((key, raw) in ads) {
                val adUnitId = key as? String ?: continue
                val rects = raw as? Map<*, *> ?: continue
                rect(rects["frame"] as? List<*>)?.let { entry.scope.updateAdFrame(adUnitId, it) }
                rect(rects["creative"] as? List<*>)?.let { entry.scope.updateCreativeFrame(adUnitId, it) }
            }
        }
        entry.scope.updateViewport(viewport)
        result.success(null)
    }

    /** `[x, y, w, h]` in logical pixels; every value validated. */
    private fun rect(list: List<*>?): Rect? {
        if (list == null || list.size != 4) return null
        val values = list.map { (it as? Number)?.toDouble() ?: return null }
        if (values.any { !it.isFinite() }) return null
        return Rect(values[0], values[1], values[2], values[3])
    }

    companion object {
        const val CHANNEL_NAME = "dk.stepnetwork.webadview_flutter"
        const val VIEW_TYPE = "webadview_flutter/ad"
        const val LOG_TAG = "SN"
    }
}
