package dk.stepnetwork.webadview_flutter.web

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.MotionEvent
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.JsResult
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import dk.stepnetwork.webadview_flutter.SdkState
import dk.stepnetwork.webadview_flutter.core.AdLoadState
import dk.stepnetwork.webadview_flutter.core.BridgeMessage
import dk.stepnetwork.webadview_flutter.core.RemoteLazyLoadConfig
import dk.stepnetwork.webadview_flutter.core.SNLog
import dk.stepnetwork.webadview_flutter.core.TargetingScriptBuilder
import dk.stepnetwork.webadview_flutter.core.TemplateUrl
import dk.stepnetwork.webadview_flutter.core.ViewabilityPayload
import dk.stepnetwork.webadview_flutter.core.ViewabilityUpdate
import dk.stepnetwork.webadview_flutter.core.ViewportClipCalculator
import dk.stepnetwork.webadview_flutter.scope.AdScope
import org.json.JSONTokener
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * One ad's WebView and everything around it — the Kotlin twin of
 * WebAdViewController (bridge-contract §1–§4): consent-gated template load,
 * document-start injections, the `nativeBridge`, the manual render trigger
 * (once per loaded page), remote lazy-load read-back, external-URL handling,
 * consent-change reload, and viewport resizing inside a stable container.
 *
 * Geometry from the scope is in dp; only this class converts to pixels
 * (LayoutParams and scrollTo). Main thread only.
 */
@SuppressLint("SetJavaScriptEnabled")
class AdWebViewController(
    private val context: Context,
    val adUnitId: String,
    private val scope: AdScope,
    private val customTargeting: Map<String, List<String>>,
    private val viewportResizingEnabled: Boolean,
    private val debugEnabled: Boolean,
    private val remoteStore: RemoteLazyLoadStore,
    private val callbacks: Callbacks,
) {
    interface Callbacks {
        fun onAdSize(width: Double, height: Double)
        fun onActiveViewImpression(slotId: String)
        fun onRenderProcessGone()
        fun openExternal(uri: Uri)
    }

    /** Flutter sizes this container to the FULL ad frame; the WebView inside is clipped. */
    val container: FrameLayout = FrameLayout(context)
    var webView: WebView? = null
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private val density: Float = context.resources.displayMetrics.density
    private val baseUrl: String = SdkState.adTemplateUrl ?: run { SdkState.warnNotInitializedOnce(); "" }
    private val templateOrigin: String? = TemplateUrl.origin(baseUrl)
    private var initialHost: String? = TemplateUrl.host(baseUrl)

    var hasLoadedContent = false
        private set
    private var pageLoaded = false
    private var pendingRenderAfterLoad = false
    private var hasTriggeredRender = false
    private var hasRenderedAd = false
    private var pendingClip: ViewportClipCalculator.Clip? = null
    private var lastAppliedRegime: String? = null
    private var loadedConsentJs: String? = null
    private var remoteConfigPollAttempts = 0
    private val scriptHandlers = ArrayList<ScriptHandler>()
    private var documentStartSupported = false
    private var fallbackBundle: String? = null
    private val unsubscribers = ArrayList<() -> Unit>()
    private val consentListener: () -> Unit = { onConsentChanged() }
    private var disposed = false

    init {
        setupWebView()
        // Subscribe FIRST, then re-arm — the tracker does not replay.
        unsubscribers += scope.addLoadStateListener(adUnitId) { state -> if (state == AdLoadState.DISPLAYED) renderIfPageReadyElseDefer() }
        unsubscribers += scope.addJsListener(adUnitId) { sendViewability(it) }
        if (viewportResizingEnabled) {
            unsubscribers += scope.addClipListener(adUnitId) { applyViewportClip(it) }
        }
        scope.tracker.resetImpression(adUnitId)
        SdkState.addConsentListener(consentListener)
        checkConsentAndLoad()
    }

    // ---- WebView setup ---------------------------------------------------------

    private fun setupWebView() {
        val wv = WebView(context)
        wv.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            // Pin the page scale to 1 (bridge-contract §8, finding 3). Chromium's
            // resize anchoring keeps the visible CSS width constant whenever the
            // WebView's WIDTH changes (300 ↔ 320 between ad refreshes), so the scale
            // ratchets upward and the creative renders zoomed and cropped. Honour
            // the template's viewport meta (width=device-width) and disable zoom;
            // PAGE_SCALE_PIN adds minimum/maximum-scale=1 so nothing can drift.
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true)
        wv.isVerticalScrollBarEnabled = false
        wv.isHorizontalScrollBarEnabled = false
        wv.overScrollMode = WebView.OVER_SCROLL_NEVER
        // No user scrolling inside the ad (taps still click; programmatic scrollTo still works).
        wv.setOnTouchListener { _, event -> event.action == MotionEvent.ACTION_MOVE }
        wv.setBackgroundColor(0x00000000)
        WebView.setWebContentsDebuggingEnabled(debugEnabled)
        wv.webViewClient = Client()
        wv.webChromeClient = ChromeClient()
        installBridge(wv)

        wv.layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        container.addView(wv)
        webView = wv
        SNLog.d("[SN] [NATIVE] WebAdViewController: WebView setup")
    }

    /** Web → native bridge: origin-restricted WebMessageListener, JS-interface fallback. */
    private fun installBridge(wv: WebView) {
        val origin = templateOrigin
        if (origin != null && WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(wv, "nativeBridge", setOf(origin)) { _, message, _, isMainFrame, _ ->
                val data = message.data
                if (isMainFrame) mainHandler.post { handleBridgeMessage(data) }
            }
        } else {
            wv.addJavascriptInterface(object {
                @JavascriptInterface
                fun postMessage(json: String) {
                    mainHandler.post { handleBridgeMessage(json) }
                }
            }, "nativeBridge")
        }
    }

    // ---- Bridge messages (untrusted page input) ---------------------------------

    fun handleBridgeMessage(json: String?) {
        when (val msg = BridgeMessage.parse(json)) {
            is BridgeMessage.Console ->
                SNLog.d("[SN] [WebAdView] [HTML] [${msg.level.uppercase()}] ${msg.message}")
            is BridgeMessage.AdSize -> {
                SNLog.d("[SN] [WebAdView] [HTML] [adSize] width: ${msg.width}, height: ${msg.height}")
                callbacks.onAdSize(msg.width, msg.height)
                scope.tracker.markRendered(adUnitId) // the creative exists now: viewability may start counting
                if (!hasRenderedAd) {
                    hasRenderedAd = true
                    val pending = pendingClip
                    if (viewportResizingEnabled && pending != null) {
                        mainHandler.post { applyViewportClip(pending) }
                    }
                }
            }
            is BridgeMessage.ImpressionViewable -> {
                SNLog.d("[SN] [VIEWABILITY] [ACTIVEVIEW] ${msg.slotId}: impressionViewable — Google counted a viewable impression")
                callbacks.onActiveViewImpression(msg.slotId)
            }
            is BridgeMessage.SlotVisibilityChanged ->
                msg.visiblePercent?.let { SNLog.d("[SN] [VIEWABILITY] [ACTIVEVIEW] ${msg.slotId}: GPT reports ${it.toInt()}% visible") }
            is BridgeMessage.Unknown -> SNLog.d("[SN] [WebAdView] [HTML] [Unknown type] ${msg.raw}")
            is BridgeMessage.Garbage -> SNLog.d("[SN] [WebAdView] [HTML] ${msg.raw}")
        }
    }

    // ---- Consent gate ------------------------------------------------------------

    private val isConsentDetermined: Boolean
        get() = SdkState.consentProvider?.isConsentDetermined == true

    private fun checkConsentAndLoad() {
        if (isConsentDetermined && !hasLoadedContent) {
            loadAdContent()
            SNLog.d("[SN] [NATIVE] WebAdViewController: Consent already given, loading WebAdViews")
        }
    }

    private fun onConsentChanged() {
        if (disposed || !isConsentDetermined) return
        if (!hasLoadedContent) {
            loadAdContent()
            SNLog.d("[SN] [NATIVE] WebAdViewController: Consent changed")
        } else {
            val current = SdkState.consentProvider?.javaScriptForWebView()
            if (current != null && current != loadedConsentJs) {
                SNLog.d("[SN] [NATIVE] WebAdViewController: Consent changed after load — reloading $adUnitId with the new consent")
                reloadAdContent()
            }
        }
    }

    private fun reloadAdContent() {
        val wv = webView ?: return
        if (!hasLoadedContent) return
        wv.stopLoading()
        scriptHandlers.forEach { it.remove() }
        scriptHandlers.clear()
        hasLoadedContent = false
        hasRenderedAd = false
        loadAdContent()
    }

    // ---- Load ---------------------------------------------------------------------

    fun loadAdContent() {
        if (hasLoadedContent) return
        val wv = webView ?: return
        hasLoadedContent = true
        pageLoaded = false
        hasTriggeredRender = false
        if (scope.loadState(adUnitId) == AdLoadState.DISPLAYED) pendingRenderAfterLoad = true

        scope.tracker.resetImpression(adUnitId)

        val consentJs = SdkState.consentProvider?.javaScriptForWebView() ?: ""
        loadedConsentJs = consentJs

        val scripts = ArrayList<String>()
        scripts += InjectedScripts.BRIDGE_SHIM                       // Android-only (bridge-contract §2)
        scripts += InjectedScripts.PAGE_SCALE_PIN                    // Android-only (bridge-contract §8, finding 3)
        if (consentJs.isNotEmpty()) scripts += consentJs             // must precede the page's CMP / GPT tags
        scripts += InjectedScripts.VIEWABILITY_SHIM
        scripts += InjectedScripts.adUnitId(adUnitId)
        TargetingScriptBuilder.script(customTargeting)?.let {
            scripts += it
            SNLog.d("[SN] [NATIVE] Injected custom targeting with ${customTargeting.size} parameters")
        }
        scripts += InjectedScripts.IMPRESSION_VIEWABLE_LISTENER
        if (debugEnabled) scripts += InjectedScripts.DEBUG_BUNDLE
        installDocumentStartScripts(wv, scripts)
        SNLog.d("[SN] [NATIVE] Injected adUnitId to JS (window.stepnetwork.adUnitId): $adUnitId")

        val url = TemplateUrl.assemble(baseUrl, debugEnabled, UUID.randomUUID().toString())
        if (baseUrl.isEmpty() || Uri.parse(url).scheme == null) {
            // Sanctioned error #2: an empty template URL must fail LOUDLY.
            SNLog.error("[SN] [ERROR] WebAdViewController: no valid ad template URL — ad '$adUnitId' will not load. Did you call WebAdViewSdk.initialize?")
            hasLoadedContent = false
            return
        }
        initialHost = TemplateUrl.host(url)
        wv.loadUrl(url)
        SNLog.d("[SN] [NATIVE] WebAdViewController: Loading URL $url")
    }

    private fun installDocumentStartScripts(wv: WebView, scripts: List<String>) {
        val origin = templateOrigin
        documentStartSupported = origin != null && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (documentStartSupported) {
            for (script in scripts) {
                scriptHandlers += WebViewCompat.addDocumentStartJavaScript(wv, script, setOf(origin!!))
            }
            fallbackBundle = null
        } else {
            // Rare (very old WebView): inject as early as Android allows.
            SNLog.d("[SN] [NATIVE] document-start scripts unsupported by this WebView — injecting at onPageStarted (consent hand-off may race page scripts)")
            fallbackBundle = scripts.joinToString("\n;\n")
        }
    }

    // ---- Render trigger: exactly once per loaded page ----------------------------

    private fun renderIfPageReadyElseDefer() {
        if (hasTriggeredRender) return
        if (pageLoaded) {
            scheduleRenderTrigger(100)
        } else {
            SNLog.d("[SN] [LLM] WebAdViewController: displayed before the page finished loading — render deferred to onPageFinished")
            pendingRenderAfterLoad = true
        }
    }

    private fun scheduleRenderTrigger(delayMs: Long) {
        hasTriggeredRender = true
        pendingRenderAfterLoad = false
        mainHandler.postDelayed({ triggerAdRendering() }, delayMs)
    }

    private fun triggerAdRendering() {
        val wv = webView ?: run {
            SNLog.d("[SN] [LLM] WebAdViewController: Cannot trigger ad rendering - WebView is null")
            return
        }
        SNLog.d("[SN] [LLM] WebAdViewController: Triggering ad rendering for $adUnitId")
        wv.evaluateJavascript(InjectedScripts.triggerAdRendering(adUnitId)) { }
    }

    private fun handlePageFinished() {
        pageLoaded = true
        if (pendingRenderAfterLoad && !hasTriggeredRender) scheduleRenderTrigger(100)
        // A fresh page resets its scroll offset — re-apply the clip.
        pendingClip?.let { if (hasRenderedAd) applyViewportClip(it) }
    }

    // ---- Remote lazy-load read-back (bridge-contract §3.2) ------------------------

    private fun pollRemoteLazyLoadConfig() {
        val wv = webView ?: return
        wv.evaluateJavascript(InjectedScripts.REMOTE_LAZY_LOAD_POLL) { result ->
            // evaluateJavascript returns JSON: a string arrives quoted, null as "null".
            val payload = try { JSONTokener(result ?: "null").nextValue() as? String } catch (e: Exception) { null }
            if (handleRemoteLazyLoadPayload(payload)) return@evaluateJavascript
            remoteConfigPollAttempts += 1
            if (remoteConfigPollAttempts < 10) {
                mainHandler.postDelayed({ if (webView != null) pollRemoteLazyLoadConfig() }, 500)
            } else {
                SNLog.d("[SN] [LLM] No remote lazyLoad config on page (window.stepnetwork.lazyLoad); keeping current thresholds")
            }
        }
    }

    fun handleRemoteLazyLoadPayload(json: String?): Boolean {
        val config = RemoteLazyLoadConfig.parse(json) ?: return false
        if (!config.isValid) return false
        initialHost?.let { remoteStore.save(config, it) }
        scope.manager.applyRemote(config)
        return true
    }

    // ---- Native → web viewability (bridge-contract §4) -----------------------------

    private fun sendViewability(update: ViewabilityUpdate) {
        val wv = webView ?: return
        if (!hasLoadedContent) return
        val json = ViewabilityPayload.json(update, System.currentTimeMillis())
        wv.evaluateJavascript("window.stepnetwork && window.stepnetwork._onViewability && window.stepnetwork._onViewability($json);", null)
    }

    // ---- Viewport resizing (bridge-contract §4.4) -----------------------------------

    fun applyViewportClip(clip: ViewportClipCalculator.Clip) {
        if (!viewportResizingEnabled) return
        pendingClip = clip
        val wv = webView ?: return
        if (!hasRenderedAd) return // never clip before the creative rendered

        val fullW = container.width
        val fullH = container.height
        val widthPx: Int
        val heightPx: Int
        val leftPx: Int
        val topPx: Int
        val scrollX: Int
        val scrollY: Int
        val regime: String
        when {
            clip.isFullyVisible -> { widthPx = fullW; heightPx = fullH; leftPx = 0; topPx = 0; scrollX = 0; scrollY = 0; regime = "full" }
            clip.isFullyHidden -> { widthPx = fullW; heightPx = max(1, density.roundToInt()); leftPx = 0; topPx = 0; scrollX = 0; scrollY = 0; regime = "sliver" }
            else -> {
                val s = clip.sliceFrame
                widthPx = max(1, (s.width * density).roundToInt())
                heightPx = max(1, (s.height * density).roundToInt())
                leftPx = (s.x * density).roundToInt()
                topPx = (s.y * density).roundToInt()
                scrollX = (clip.contentOffsetX * density).roundToInt()
                scrollY = (clip.contentOffsetY * density).roundToInt()
                regime = "partial"
            }
        }
        if (fullW == 0 || fullH == 0) return // not laid out yet; onLayout re-applies

        val lp = wv.layoutParams as FrameLayout.LayoutParams
        val unchanged = lp.width == widthPx && lp.height == heightPx && lp.leftMargin == leftPx && lp.topMargin == topPx &&
            wv.scrollX == scrollX && wv.scrollY == scrollY
        if (unchanged) return

        lp.width = widthPx
        lp.height = heightPx
        lp.leftMargin = leftPx
        lp.topMargin = topPx
        wv.layoutParams = lp
        // The scroll range only grows after the smaller layout is applied.
        wv.post { wv.scrollTo(scrollX, scrollY) }
        if (regime != lastAppliedRegime) {
            lastAppliedRegime = regime
            SNLog.d("[SN] [CLIP] $adUnitId: webview viewport -> ${(widthPx / density).roundToInt()}x${(heightPx / density).roundToInt()} (offset y: ${(scrollY / density).roundToInt()}, $regime)")
        }
    }

    /** Called by the platform view when Flutter re-lays out the container. */
    fun onContainerLayout() {
        val clip = pendingClip ?: return
        if (viewportResizingEnabled && hasRenderedAd) applyViewportClip(clip)
    }

    // ---- Teardown ------------------------------------------------------------------

    fun dispose() {
        disposed = true
        SdkState.removeConsentListener(consentListener)
        unsubscribers.forEach { it() }
        unsubscribers.clear()
        mainHandler.removeCallbacksAndMessages(null)
        webView?.let { wv ->
            wv.stopLoading()
            scriptHandlers.forEach { it.remove() }
            container.removeView(wv)
            wv.destroy()
        }
        webView = null
        SNLog.d("[SN] [LLM] WebAdViewController: Unloaded WebView for $adUnitId")
    }

    // ---- Clients -------------------------------------------------------------------

    private inner class Client : WebViewClient() {
        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            fallbackBundle?.let { view.evaluateJavascript(it, null) }
        }

        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) {
            // Expected to stay silent: PAGE_SCALE_PIN pins the scale. Logged so a regression is visible.
            SNLog.d("[SN] [CLIP] $adUnitId: page scale changed $oldScale -> $newScale")
        }

        override fun onPageFinished(view: WebView, url: String?) {
            remoteConfigPollAttempts = 0
            pollRemoteLazyLoadConfig()
            handlePageFinished()
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val target = request.url.toString()
            if (ExternalUrlPolicy.shouldHandleExternally(target, request.isForMainFrame, initialHost)) {
                SNLog.d("[SN] [NATIVE] External URL handler: opening externally: $target")
                callbacks.openExternal(request.url)
                return true
            }
            return false
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            SNLog.d("[SN] [NATIVE] WebView render process gone for $adUnitId — recreating")
            dispose()
            callbacks.onRenderProcessGone()
            return true // handled: do not crash the app
        }
    }

    private inner class ChromeClient : WebChromeClient() {
        /** target=_blank / window.open: capture the URL in a throwaway WebView and open it externally. */
        override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
            val popup = WebView(view.context)
            popup.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                    SNLog.d("[SN] [NATIVE] External URL handler: Popup window opened externally.")
                    callbacks.openExternal(request.url)
                    mainHandler.post { popup.destroy() }
                    return true
                }
            }
            (resultMsg.obj as WebView.WebViewTransport).webView = popup
            resultMsg.sendToTarget()
            return true
        }

        override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            SNLog.d("[SN] [WebAdView] [HTML] [ALERT] $message")
            result.confirm()
            return true
        }

        override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            result.confirm()
            return true
        }
    }
}
