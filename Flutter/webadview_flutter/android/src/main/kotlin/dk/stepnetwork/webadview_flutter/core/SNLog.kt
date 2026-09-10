package dk.stepnetwork.webadview_flutter.core

/**
 * SDK-wide debug logger (port of SNLog). Gated on the persisted debug flag;
 * the sink is injected so the core stays free of android.util.Log and unit
 * tests can capture output. Prefixes match iOS exactly (`[SN] [NATIVE]`,
 * `[SN] [LLM]`, `[SN] [VIEWABILITY]`, `[SN] [CLIP]`, `[SN] [WebAdView] [HTML]`)
 * so `adb logcat -s SN` / grep '\[SN\]' reads the same on both platforms.
 */
object SNLog {
    @Volatile
    var isEnabled: Boolean = false

    /** Debug sink (android.util.Log.d in production). */
    @Volatile
    var sink: (String) -> Unit = {}

    /**
     * Un-gated error sink. Used ONLY for the two sanctioned mis-integration
     * errors (SDK not initialized, invalid template URL) — never for routine
     * logging.
     */
    @Volatile
    var errorSink: (String) -> Unit = {}

    fun d(message: String) {
        if (isEnabled) sink(message)
    }

    fun error(message: String) {
        errorSink(message)
    }
}
