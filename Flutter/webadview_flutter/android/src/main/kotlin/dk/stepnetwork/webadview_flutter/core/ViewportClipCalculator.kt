package dk.stepnetwork.webadview_flutter.core

import kotlin.math.abs

/**
 * Visible slice of an ad for viewport resizing (port of ViewportClipCalculator):
 * the WebView is resized to exactly this slice so GPT Active View measures
 * against the true visible viewport.
 */
object ViewportClipCalculator {

    /** Ad-local geometry of the visible slice. */
    data class Clip(val sliceFrame: Rect, val isFullyVisible: Boolean, val isFullyHidden: Boolean) {
        /** Page scroll offset so the slice shows the right creative pixels. */
        val contentOffsetX: Double get() = sliceFrame.x
        val contentOffsetY: Double get() = sliceFrame.y
    }

    fun clip(adFrame: Rect, viewport: Rect): Clip {
        val ad = adFrame.standardized()
        val vp = viewport.standardized()
        if (ad.width <= 0 || ad.height <= 0 || vp.isEmpty) {
            return Clip(Rect.ZERO, isFullyVisible = false, isFullyHidden = true)
        }
        val inter = ad.intersection(vp)
        if (inter == null || inter.width <= 0 || inter.height <= 0) {
            return Clip(Rect.ZERO, isFullyVisible = false, isFullyHidden = true)
        }
        val slice = Rect(inter.minX - ad.minX, inter.minY - ad.minY, inter.width, inter.height)
        val fullyVisible = slice == Rect(0.0, 0.0, ad.width, ad.height)
        return Clip(slice, isFullyVisible = fullyVisible, isFullyHidden = false)
    }

    /** Whether two clips differ enough to apply (sub-dp noise is ignored). */
    fun differsSignificantly(a: Clip, b: Clip, tolerance: Double = 2.0): Boolean {
        if (a.isFullyVisible != b.isFullyVisible || a.isFullyHidden != b.isFullyHidden) return true
        val ra = a.sliceFrame
        val rb = b.sliceFrame
        return abs(ra.minX - rb.minX) > tolerance ||
            abs(ra.minY - rb.minY) > tolerance ||
            abs(ra.width - rb.width) > tolerance ||
            abs(ra.height - rb.height) > tolerance
    }
}
