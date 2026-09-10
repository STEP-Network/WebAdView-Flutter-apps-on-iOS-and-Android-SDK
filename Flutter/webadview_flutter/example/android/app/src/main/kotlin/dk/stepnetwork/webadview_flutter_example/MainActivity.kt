package dk.stepnetwork.webadview_flutter_example

import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Didomi's consent notice and preferences need a FragmentActivity host —
// the one MainActivity change a Flutter app makes for this plugin.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SimulatedCmpBridge.install(this, flutterEngine)
    }
}

/**
 * DEMO ONLY — plays the role of the app's own TCF-certified consent platform
 * (consent mode 3). A certified CMP records the user's answer in the IAB TCF
 * standard location, the app's DEFAULT SharedPreferences, keys
 * `IABTCF_TCString` and `IABTCF_gdprApplies`; this bridge writes two fixed,
 * valid TC strings there (accept all / decline all). The ad SDK's
 * `TcfConsentProvider` reads those keys exactly as it would for Cookiebot,
 * OneTrust or Usercentrics. Dart can only choose accept/decline/clear — no
 * string ever crosses the channel.
 */
object SimulatedCmpBridge {
    private const val TC_STRING_KEY = "IABTCF_TCString"
    private const val GDPR_APPLIES_KEY = "IABTCF_gdprApplies"

    // Valid TCF v2.2 strings (same as the native SimulatedCMP demo).
    private const val ACCEPT_TC_STRING = "CQn2q4AQn2q4AAHABADACoFsAP_gAELgAAZQLrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCQGEAIACABgACgBIAIAABAAAAABAAQAAAAIAAIAAAAAAEIBAIJCAAAAABAkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAgAAAjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAILrgR9C5cSWlBeTBXYIsAOAQXwFAAIIAgAAAAAgABCBqAIIQCUGEAIACAAAAAABAAIAABAAAIABAAQAABAIAQIBAAAAAAIBAIACAAAAABQkBQAAAAAgAAEAAAgEASAAAAgAAEQNIiQEAAEAAgjAAAIAAAAAAIAAAAAAAAAAEAAAAAgCAAEAAAAAAAAAAAABAIgAAAAAAAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAJCADAAEGVw.ILrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCUGEAIACABgACgBIAIAABAAAIABAAQAABAIAQIBAAAAAEIBAIJCAAAAABQkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAkAAgjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA"
    private const val DECLINE_TC_STRING = "CQn2q4AQn2q4AAHABADACoFgAAAAAAAAAAZQAAAGfgAgGfABIQAYAAgyuA.ILrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCUGEAIACABgACgBIAIAABAAAIABAAQAABAIAQIBAAAAAEIBAIJCAAAAABQkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAkAAgjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA"

    fun install(context: Context, engine: FlutterEngine) {
        // The default SharedPreferences file — the same one TcfConsentProvider reads.
        val prefs = context.getSharedPreferences("${context.packageName}_preferences", Context.MODE_PRIVATE)
        MethodChannel(engine.dartExecutor.binaryMessenger, "newshub/simulated_cmp").setMethodCallHandler { call, result ->
            when (call.method) {
                "answer" -> {
                    val accept = call.argument<Boolean>("accept")
                    if (accept == null) {
                        result.error("bad_args", "accept (Boolean) is required", null)
                    } else {
                        prefs.edit()
                            .putString(TC_STRING_KEY, if (accept) ACCEPT_TC_STRING else DECLINE_TC_STRING)
                            .putInt(GDPR_APPLIES_KEY, 1)
                            .apply()
                        result.success(null)
                    }
                }
                "clear" -> {
                    prefs.edit().remove(TC_STRING_KEY).remove(GDPR_APPLIES_KEY).apply()
                    result.success(null)
                }
                "read" -> result.success(prefs.getString(TC_STRING_KEY, null))
                else -> result.notImplemented()
            }
        }
    }
}
