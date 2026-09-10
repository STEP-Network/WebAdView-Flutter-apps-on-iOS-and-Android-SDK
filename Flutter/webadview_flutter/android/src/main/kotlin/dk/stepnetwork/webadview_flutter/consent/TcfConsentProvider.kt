package dk.stepnetwork.webadview_flutter.consent

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.fragment.app.FragmentActivity
import dk.stepnetwork.webadview_flutter.core.SNLog

/**
 * Bring-your-own-CMP provider (port of TCFConsentProvider): reads the IAB
 * TCF standard location — the app's DEFAULT SharedPreferences, keys
 * `IABTCF_TCString` / `IABTCF_gdprApplies` — and hands consent to the page
 * through the `__tcfapi` stub. Shows no UI of its own.
 */
class TcfConsentProvider(context: Context) : ConsentProvider {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("${context.packageName}_preferences", Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())

    // The framework holds listeners WEAKLY — a strong field reference is required
    // or the listener is silently garbage-collected.
    private var listener: SharedPreferences.OnSharedPreferenceChangeListener? = null

    /** A TC string exists, or the CMP determined GDPR does not apply (== 0, not absent). */
    override val isConsentDetermined: Boolean
        get() {
            val tc = prefs.getString(TC_STRING_KEY, null)
            if (!tc.isNullOrEmpty()) return true
            return prefs.contains(GDPR_APPLIES_KEY) && readGdprApplies() == 0
        }

    override fun start(onChange: () -> Unit) {
        val l = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == TC_STRING_KEY || key == GDPR_APPLIES_KEY) {
                SNLog.d("[SN] [NATIVE] TcfConsentProvider: $key changed")
                mainHandler.post(onChange)
            }
        }
        listener = l
        prefs.registerOnSharedPreferenceChangeListener(l)
        // Consent may already be stored from a previous launch.
        mainHandler.post(onChange)
    }

    override fun javaScriptForWebView(): String {
        val gdprApplies = if (prefs.contains(GDPR_APPLIES_KEY)) readGdprApplies()?.let { it != 0 } else null
        return TcfApiStub.script(prefs.getString(TC_STRING_KEY, null) ?: "", gdprApplies)
    }

    override fun showPreferences(activity: FragmentActivity?) {
        SNLog.d("[SN] [NATIVE] showConsentPreferences: the app owns the consent UI in TCF mode — no-op")
    }

    /** CMPs store the flag as Int; tolerate Long/String/Boolean writers. */
    private fun readGdprApplies(): Int? = when (val v = prefs.all[GDPR_APPLIES_KEY]) {
        is Int -> v
        is Long -> v.toInt()
        is Boolean -> if (v) 1 else 0
        is String -> v.toIntOrNull()
        else -> null
    }

    companion object {
        const val TC_STRING_KEY = "IABTCF_TCString"
        const val GDPR_APPLIES_KEY = "IABTCF_gdprApplies"
    }
}
