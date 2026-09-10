package dk.stepnetwork.webadview_flutter.web

import android.content.Context
import android.content.SharedPreferences
import dk.stepnetwork.webadview_flutter.core.RemoteLazyLoadConfig

/**
 * Per-host cache of STEP's remote lazy-load thresholds (port of
 * RemoteLazyLoadStore) so launches after the first start with the tuned
 * values before any ad page has loaded.
 */
class RemoteLazyLoadStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun load(host: String): RemoteLazyLoadConfig? {
        val config = RemoteLazyLoadConfig.parse(prefs.getString(key(host), null)) ?: return null
        return if (config.isValid) config else null
    }

    fun save(config: RemoteLazyLoadConfig, host: String) {
        prefs.edit().putString(key(host), config.toJson()).apply()
    }

    private fun key(host: String) = "sn.lazyLoad.$host"

    companion object {
        const val PREFS_NAME = "webadview_flutter"
    }
}

/** Persistent debug flag (port of DebugSettings), shared with SNLog. */
class DebugSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(RemoteLazyLoadStore.PREFS_NAME, Context.MODE_PRIVATE)

    var isDebugEnabled: Boolean
        get() = prefs.getBoolean(KEY, false)
        set(value) = prefs.edit().putBoolean(KEY, value).apply()

    companion object {
        const val KEY = "isDebugEnabled"
    }
}
