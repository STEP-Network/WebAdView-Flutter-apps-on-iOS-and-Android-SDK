package dk.stepnetwork.webadview_flutter.core

import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

/**
 * Web → native messages on the `nativeBridge` (bridge-contract §2). Bodies
 * come from the ad page — every field is untrusted; mistyped fields degrade
 * exactly like the iOS handler (adSize dropped, slotId → "unknown").
 */
sealed class BridgeMessage {
    data class Console(val level: String, val message: String) : BridgeMessage()
    data class AdSize(val width: Double, val height: Double) : BridgeMessage()
    data class ImpressionViewable(val slotId: String) : BridgeMessage()
    data class SlotVisibilityChanged(val slotId: String, val visiblePercent: Double?) : BridgeMessage()
    data class Unknown(val type: String?, val raw: String) : BridgeMessage()
    data class Garbage(val raw: String) : BridgeMessage()

    companion object {
        fun parse(json: String?): BridgeMessage {
            if (json == null) return Garbage("")
            val value = try {
                JSONTokener(json).nextValue()
            } catch (e: JSONException) {
                return Garbage(json)
            }
            val obj = value as? JSONObject ?: return Garbage(json)
            val type = obj.opt("type") as? String ?: return Unknown(null, json)
            return when (type) {
                "console" -> Console(
                    level = obj.opt("level") as? String ?: "log",
                    message = obj.opt("message") as? String ?: "",
                )
                "adSize" -> {
                    val w = obj.opt("width") as? Number
                    val h = obj.opt("height") as? Number
                    if (w == null || h == null) Unknown(type, json) else AdSize(w.toDouble(), h.toDouble())
                }
                "impressionViewable" -> ImpressionViewable(obj.opt("slotId") as? String ?: "unknown")
                "slotVisibilityChanged" -> SlotVisibilityChanged(
                    slotId = obj.opt("slotId") as? String ?: "unknown",
                    visiblePercent = (obj.opt("visiblePercent") as? Number)?.toDouble(),
                )
                else -> Unknown(type, json)
            }
        }
    }
}

/** Native → web viewability payload (bridge-contract §4.2). */
object ViewabilityPayload {
    fun json(update: ViewabilityUpdate, nowMs: Long): String = JSONObject()
        .put("ratio", Math.round(update.ratio * 100.0) / 100.0)
        .put("visible", update.isVisible)
        .put("viewable", update.isViewable)
        .put("dwellMs", Math.round(update.dwell * 1000.0))
        .put("thresholdMs", Math.round(update.mode.requiredDurationSeconds * 1000.0))
        .put("mode", update.mode.wireName)
        .put("appActive", update.isAppActive)
        .put("ts", nowMs)
        .toString()
}
