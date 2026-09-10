package dk.stepnetwork.webadview_flutter.core

/** Port of WebAdViewController.assembleTemplateURLString. */
object TemplateUrl {

    /**
     * `didomi-disable-notice=true` is guaranteed (consent is collected natively
     * and injected — the in-page notice must stay suppressed), `aym_debug=true`
     * in debug mode, and a cache-buster.
     */
    fun assemble(baseUrl: String, debugEnabled: Boolean, randomValue: String): String {
        var url = baseUrl
        fun append(parameter: String) {
            url += (if (url.contains("?")) "&" else "?") + parameter
        }
        if (!url.contains("didomi-disable-notice")) append("didomi-disable-notice=true")
        if (debugEnabled) append("aym_debug=true")
        append("rnd=$randomValue")
        return url
    }

    /** Scheme + host (+ port) of a URL, or null. Used for origin-restricted injection. */
    fun origin(url: String): String? {
        val parsed = try { java.net.URI(url) } catch (e: Exception) { return null }
        val scheme = parsed.scheme ?: return null
        val host = parsed.host ?: return null
        if (scheme != "http" && scheme != "https") return null
        return if (parsed.port > 0) "$scheme://$host:${parsed.port}" else "$scheme://$host"
    }

    fun host(url: String): String? = try { java.net.URI(url).host } catch (e: Exception) { null }
}
