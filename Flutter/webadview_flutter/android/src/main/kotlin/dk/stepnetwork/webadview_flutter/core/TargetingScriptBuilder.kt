package dk.stepnetwork.webadview_flutter.core

import org.json.JSONArray
import org.json.JSONObject

/**
 * Builds the GPT custom-targeting script (port of TargetingScriptBuilder).
 * Keys and values are JSON-encoded — quotes, newlines or `</script>` in
 * targeting values cannot break out of the script. Never string-interpolate
 * targeting into JavaScript anywhere else.
 */
object TargetingScriptBuilder {

    /** null when there is nothing to target. Keys are sorted for determinism. */
    fun script(params: Map<String, List<String>>): String? {
        val entries = params.entries
            .filter { it.value.isNotEmpty() }
            .sortedBy { it.key }
        if (entries.isEmpty()) return null

        val body = StringBuilder()
        // Android injects at document start, before the page created googletag.
        body.append("window.googletag = window.googletag || {};\n")
        body.append("googletag.cmd = googletag.cmd || [];\n")
        body.append("googletag.cmd.push(function () {\n")
        for ((key, values) in entries) {
            val jsonKey = neutralize(JSONObject.quote(key))
            val jsonValues = neutralize(JSONArray(values).toString())
            body.append("  googletag.pubads().setTargeting(").append(jsonKey).append(", ").append(jsonValues).append(");\n")
        }
        body.append("});")
        return body.toString()
    }

    /** `</` → `<\/` so a value can never terminate an enclosing script tag. */
    internal fun neutralize(json: String): String = json.replace("</", "<\\/")
}
