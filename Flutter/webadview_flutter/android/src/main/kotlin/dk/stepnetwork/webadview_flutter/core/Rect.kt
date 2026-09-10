package dk.stepnetwork.webadview_flutter.core

import kotlin.math.max
import kotlin.math.min

/**
 * Pure rectangle in logical pixels (dp) — the unit Dart reports and the unit
 * every state machine works in. Deliberately not android.graphics.RectF so
 * the core runs in plain JVM unit tests.
 */
data class Rect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = min(x, x + width)
    val maxX: Double get() = max(x, x + width)
    val minY: Double get() = min(y, y + height)
    val maxY: Double get() = max(y, y + height)
    val area: Double get() = width * height
    val isEmpty: Boolean get() = width <= 0.0 || height <= 0.0

    /** Positive width/height (CGRect.standardized). */
    fun standardized(): Rect = Rect(minX, minY, maxX - minX, maxY - minY)

    fun intersects(other: Rect): Boolean = intersection(other) != null

    /** Overlap, or null when the rectangles do not overlap (CGRect.null). */
    fun intersection(other: Rect): Rect? {
        val a = standardized()
        val b = other.standardized()
        val left = max(a.minX, b.minX)
        val top = max(a.minY, b.minY)
        val right = min(a.maxX, b.maxX)
        val bottom = min(a.maxY, b.maxY)
        if (right < left || bottom < top) return null
        return Rect(left, top, right - left, bottom - top)
    }

    /** CGRect.insetBy: negative values grow the rectangle. */
    fun insetBy(dx: Double, dy: Double): Rect =
        Rect(x + dx, y + dy, width - 2 * dx, height - 2 * dy)

    fun offsetBy(dx: Double, dy: Double): Rect = Rect(x + dx, y + dy, width, height)

    companion object {
        val ZERO = Rect(0.0, 0.0, 0.0, 0.0)
    }
}
