package dk.stepnetwork.webadview_flutter

import android.app.Application
import androidx.fragment.app.FragmentActivity
import dk.stepnetwork.webadview_flutter.consent.AppDidomiConsentProvider
import dk.stepnetwork.webadview_flutter.consent.ConsentProvider
import dk.stepnetwork.webadview_flutter.consent.DidomiConsentProvider
import dk.stepnetwork.webadview_flutter.consent.TcfConsentProvider
import dk.stepnetwork.webadview_flutter.core.SNLog

/**
 * Process-wide SDK configuration (port of WebAdViewSDK.configuration): the
 * consent provider gating every ad load and the ad template URL. Survives
 * Flutter hot restarts like its iOS counterpart; the first configuration
 * wins. Also fans consent changes out to every live ad controller (the
 * NotificationCenter equivalent).
 */
object SdkState {
    var consentProvider: ConsentProvider? = null
        private set
    var adTemplateUrl: String? = null
        private set
    val isInitialized: Boolean get() = adTemplateUrl != null

    private val consentListeners = LinkedHashSet<() -> Unit>()
    private var didWarnNotInitialized = false
    private var didomiUiHost: FragmentActivity? = null

    enum class Mode { DIDOMI, TCF, APP_DIDOMI }

    fun initialize(
        application: Application,
        mode: Mode,
        adTemplateUrl: String,
        didomiApiKey: String?,
        didomiDisableRemoteConfig: Boolean,
    ) {
        if (isInitialized) {
            SNLog.d("[SN] [NATIVE] WebAdViewSDK.initialize called more than once — ignoring")
            return
        }
        val provider: ConsentProvider = when (mode) {
            Mode.DIDOMI -> DidomiConsentProvider(application, requireNotNull(didomiApiKey), didomiDisableRemoteConfig)
            Mode.TCF -> TcfConsentProvider(application)
            Mode.APP_DIDOMI -> AppDidomiConsentProvider(TcfConsentProvider(application))
        }
        consentProvider = provider
        this.adTemplateUrl = adTemplateUrl
        provider.start {
            // Providers post on the main thread; every held-back ad re-checks the gate.
            consentListeners.toList().forEach { it() }
        }
        didomiUiHost?.let { setupConsentUI(it) }
    }

    /** Gives the SDK-owned Didomi its host activity (DidomiWrapper equivalent). */
    fun setupConsentUI(activity: FragmentActivity) {
        didomiUiHost = activity
        (consentProvider as? DidomiConsentProvider)?.setupUI(activity)
    }

    fun clearConsentUIHost(activity: FragmentActivity) {
        if (didomiUiHost === activity) didomiUiHost = null
    }

    fun addConsentListener(listener: () -> Unit) {
        consentListeners.add(listener)
    }

    fun removeConsentListener(listener: () -> Unit) {
        consentListeners.remove(listener)
    }

    /** Un-gated, once: mis-integration must never be silent (sanctioned error #1). */
    fun warnNotInitializedOnce() {
        if (isInitialized || didWarnNotInitialized) return
        didWarnNotInitialized = true
        SNLog.error(
            "[SN] [ERROR] WebAdViewSdk.initialize was never called — the consent provider is not set up and ads cannot load. Call WebAdViewSdk.initialize before runApp (see the plugin README).",
        )
    }
}
