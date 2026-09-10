package dk.stepnetwork.webadview_flutter.consent

import android.app.Application
import android.os.Handler
import android.os.Looper
import androidx.fragment.app.FragmentActivity
import dk.stepnetwork.webadview_flutter.core.SNLog
import io.didomi.sdk.Didomi
import io.didomi.sdk.DidomiInitializeParameters
import io.didomi.sdk.events.ConsentChangedEvent
import io.didomi.sdk.events.EventListener

// The ONLY files importing io.didomi.* are the two providers in this file —
// mirrors the iOS rule that keeps Didomi confined.

/**
 * Standard mode (port of DidomiConsentProvider): the SDK owns Didomi —
 * initialization, the notice (presented from the host FragmentActivity via
 * [setupUI]), change events, and the native→web hand-off.
 */
class DidomiConsentProvider(
    private val application: Application,
    private val apiKey: String,
    private val disableRemoteConfig: Boolean,
) : ConsentProvider {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val didomi: Didomi get() = Didomi.getInstance()

    override val isConsentDetermined: Boolean
        get() = safely(false) { didomi.isReady && !didomi.isUserStatusPartial }

    override fun start(onChange: () -> Unit) {
        didomi.initialize(
            application,
            DidomiInitializeParameters(apiKey = apiKey, disableDidomiRemoteConfig = disableRemoteConfig),
        )
        didomi.onReady {
            SNLog.d("[SN] [NATIVE] Didomi SDK is ready")
            mainHandler.post(onChange)
            didomi.addEventListener(object : EventListener() {
                override fun consentChanged(event: ConsentChangedEvent) {
                    SNLog.d("[SN] [NATIVE] Consent event received")
                    mainHandler.post(onChange)
                }
            })
        }
    }

    override fun javaScriptForWebView(): String =
        safely("") { if (didomi.isReady) didomi.getJavaScriptForWebView() else "" }

    override fun showPreferences(activity: FragmentActivity?) {
        if (activity == null) {
            SNLog.d("[SN] [NATIVE] showPreferences: no FragmentActivity attached")
            return
        }
        safely(Unit) { didomi.showPreferences(activity) }
    }

    /** Gives Didomi a host for its notice/preferences (the DidomiWrapper equivalent). */
    fun setupUI(activity: FragmentActivity) {
        safely(Unit) { didomi.setupUI(activity) }
    }

    /** Test-automation only: grants full consent through the official API. */
    fun acceptAllForTesting() {
        didomi.onReady { safely(Unit) { didomi.setUserAgreeToAll() } }
    }

    private inline fun <T> safely(fallback: T, block: () -> T): T = try {
        block()
    } catch (e: Exception) {
        // Several Didomi getters throw before readiness (DidomiNotReadyException).
        SNLog.d("[SN] [NATIVE] Didomi call failed: ${e.message}")
        fallback
    }
}

/**
 * App-owned Didomi (port of AppDidomiConsentProvider): the app initializes
 * Didomi itself (e.g. through the didomi_sdk Flutter plugin). The gate asks
 * Didomi directly whether the user has answered; the page hand-off is the
 * `__tcfapi` stub. Fail-closed: if the app never initializes Didomi, ads
 * never load.
 */
class AppDidomiConsentProvider(private val tcf: TcfConsentProvider) : ConsentProvider {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val didomi: Didomi get() = Didomi.getInstance()

    override val isConsentDetermined: Boolean
        get() = try { didomi.isReady && !didomi.isUserStatusPartial } catch (e: Exception) { false }

    override fun start(onChange: () -> Unit) {
        tcf.start(onChange)
        // Deliberately NOT calling initialize — the app owns it.
        didomi.onReady {
            SNLog.d("[SN] [NATIVE] App-owned Didomi is ready")
            mainHandler.post(onChange)
            didomi.addEventListener(object : EventListener() {
                override fun consentChanged(event: ConsentChangedEvent) {
                    SNLog.d("[SN] [NATIVE] App-owned Didomi consent event received")
                    mainHandler.post(onChange)
                }
            })
        }
    }

    override fun javaScriptForWebView(): String = tcf.javaScriptForWebView()

    override fun showPreferences(activity: FragmentActivity?) {
        if (activity == null) return
        try { didomi.showPreferences(activity) } catch (e: Exception) {
            SNLog.d("[SN] [NATIVE] Didomi showPreferences failed: ${e.message}")
        }
    }
}
