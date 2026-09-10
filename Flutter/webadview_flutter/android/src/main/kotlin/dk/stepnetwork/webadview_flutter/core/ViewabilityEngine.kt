package dk.stepnetwork.webadview_flutter.core

/** IAB/MRC threshold profile (port of ViewabilityMode). Always DISPLAY today. */
enum class ViewabilityMode(val wireName: String, val requiredDurationSeconds: Double) {
    DISPLAY("display", 1.0),
    VIDEO("video", 2.0);

    val requiredRatio: Double get() = 0.5
}

/** Snapshot of one measurement pass (port of ViewabilityUpdate). */
data class ViewabilityUpdate(
    val adUnitId: String,
    val ratio: Double,
    val isVisible: Boolean,
    val dwell: Double,
    val mode: ViewabilityMode,
    val isViewable: Boolean,
    val becameViewable: Boolean,
    val isAppActive: Boolean,
    val timestamp: Double,
)

/**
 * Pure per-ad viewability state machine (port of ViewabilityEngine):
 * idle → counting when ratio ≥ 50 % and the app is active; counting → idle on
 * any dip or backgrounding (timer RESETS); counting → viewable when the
 * continuous dwell reaches the mode's duration (latched until reset()).
 * Time is in seconds (monotonic).
 */
class ViewabilityEngine(val adUnitId: String, val mode: ViewabilityMode) {

    sealed class State {
        object Idle : State()
        data class Counting(val since: Double) : State()
        object Viewable : State()
    }

    var state: State = State.Idle
        private set

    private var countingSince: Double? = null

    fun ingest(adFrame: Rect, viewport: Rect, isAppActive: Boolean, time: Double): ViewabilityUpdate {
        val ratio = intersectionRatio(adFrame, viewport)
        val isVisible = isAppActive && ratio >= mode.requiredRatio
        var becameViewable = false

        when (val s = state) {
            State.Idle -> if (isVisible) {
                state = State.Counting(time)
                countingSince = time
            }
            is State.Counting -> if (!isVisible) {
                state = State.Idle
                countingSince = null
            } else if (time - s.since >= mode.requiredDurationSeconds) {
                state = State.Viewable
                becameViewable = true
            }
            State.Viewable -> if (isVisible) {
                if (countingSince == null) countingSince = time
            } else {
                countingSince = null
            }
        }

        val dwell = when (val s = state) {
            State.Idle -> 0.0
            is State.Counting -> time - s.since
            State.Viewable -> countingSince?.let { time - it } ?: 0.0
        }

        return ViewabilityUpdate(
            adUnitId = adUnitId,
            ratio = ratio,
            isVisible = isVisible,
            dwell = dwell,
            mode = mode,
            isViewable = state == State.Viewable,
            becameViewable = becameViewable,
            isAppActive = isAppActive,
            timestamp = time,
        )
    }

    fun reset() {
        state = State.Idle
        countingSince = null
    }

    companion object {
        /** Fraction of [adFrame]'s area inside [viewport] (0–1). */
        fun intersectionRatio(adFrame: Rect, viewport: Rect): Double {
            val ad = adFrame.standardized()
            val vp = viewport.standardized()
            val adArea = ad.area
            if (adArea <= 0.0 || vp.isEmpty) return 0.0
            val inter = ad.intersection(vp) ?: return 0.0
            return (inter.area / adArea).coerceIn(0.0, 1.0)
        }
    }
}
