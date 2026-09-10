package dk.stepnetwork.webadview_flutter.web

import android.net.Uri

/**
 * Port of WebAdViewController.shouldHandleExternally: navigations that leave
 * the ad container open in the system browser. Non-http(s) schemes and
 * main-frame navigations to another host are external; sub-frame
 * navigations (GPT creative iframes) stay inside.
 */
object ExternalUrlPolicy {
    fun shouldHandleExternally(targetUrl: String, isMainFrame: Boolean, initialHost: String?): Boolean {
        val uri = Uri.parse(targetUrl)
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return true
        if (!isMainFrame) return false
        val targetHost = uri.host ?: return false
        return initialHost != null && !initialHost.equals(targetHost, ignoreCase = true)
    }
}
