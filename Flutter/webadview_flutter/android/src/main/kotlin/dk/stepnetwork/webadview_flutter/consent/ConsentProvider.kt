package dk.stepnetwork.webadview_flutter.consent

import androidx.fragment.app.FragmentActivity

/**
 * Where the user's consent answer comes from (port of ConsentProvider).
 * Ads load only while [isConsentDetermined] is true; every readiness or
 * consent change is reported through the callback given to [start].
 */
interface ConsentProvider {
    val isConsentDetermined: Boolean

    /** Starts observing. [onChange] must be invoked on the main thread. */
    fun start(onChange: () -> Unit)

    /** Native → web consent hand-off script, injected at document start. */
    fun javaScriptForWebView(): String

    /** Opens the consent preferences UI (no-op where the app owns the CMP). */
    fun showPreferences(activity: FragmentActivity?)
}
