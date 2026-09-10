package dk.stepnetwork.webadview_flutter.core

import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

/**
 * STEP Network's remote per-domain lazy-load thresholds, read back from the
 * loaded ad page (`window.stepnetwork.lazyLoad`) in viewport-height PERCENT
 * (100 = one viewport). Port of RemoteLazyLoadConfig; the payload crosses
 * from third-party page JS into native, so parsing is strict.
 */
data class RemoteLazyLoadConfig(val fetch: Double, val render: Double) {

    /** Same rules as iOS: finite, positive, sane upper bound, fetch ≥ render. */
    val isValid: Boolean
        get() = fetch.isFinite() && render.isFinite() &&
            fetch > 0 && render > 0 &&
            fetch <= MAX_PERCENT && render <= MAX_PERCENT &&
            fetch >= render

    fun toJson(): String = JSONObject().put("fetch", fetch).put("render", render).toString()

    companion object {
        const val MAX_PERCENT = 1000.0

        /**
         * Parses `JSON.stringify(window.stepnetwork.lazyLoad)`. Returns null for
         * anything that is not a JSON object with numeric `fetch` and `render`
         * (null, arrays, strings, missing or mistyped keys).
         */
        fun parse(jsonString: String?): RemoteLazyLoadConfig? {
            if (jsonString.isNullOrBlank()) return null
            val value = try {
                JSONTokener(jsonString).nextValue()
            } catch (e: JSONException) {
                return null
            }
            val obj = value as? JSONObject ?: return null
            val fetch = obj.opt("fetch") as? Number ?: return null
            val render = obj.opt("render") as? Number ?: return null
            return RemoteLazyLoadConfig(fetch.toDouble(), render.toDouble())
        }
    }
}
