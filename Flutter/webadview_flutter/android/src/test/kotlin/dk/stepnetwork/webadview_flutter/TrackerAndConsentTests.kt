package dk.stepnetwork.webadview_flutter

import dk.stepnetwork.webadview_flutter.consent.TcfApiStub
import dk.stepnetwork.webadview_flutter.core.Cancellable
import dk.stepnetwork.webadview_flutter.core.DelayedScheduler
import dk.stepnetwork.webadview_flutter.core.Rect
import dk.stepnetwork.webadview_flutter.core.ViewabilityMode
import dk.stepnetwork.webadview_flutter.core.ViewabilityUpdate
import dk.stepnetwork.webadview_flutter.core.ViewportClipCalculator
import dk.stepnetwork.webadview_flutter.scope.ViewabilityTracker
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// JVM ports of ViewabilityTrackerTests + the TCF stub's encoding rules.

private val bounds = Rect(0.0, 0.0, 400.0, 800.0)
private fun adFrame(visibleFraction: Double) = Rect(0.0, 700.0 + (1 - visibleFraction) * 100, 100.0, 100.0)

/** Records scheduled ticks so tests can observe the ticker without real time. */
private class RecordingScheduler : DelayedScheduler {
    var scheduled = 0
    var cancelled = 0
    override fun schedule(delayMs: Long, action: () -> Unit): Cancellable {
        scheduled++
        return Cancellable { cancelled++ }
    }
}

private fun makeTracker(): Triple<ViewabilityTracker, (Double) -> Unit, RecordingScheduler> {
    var now = 1000.0
    val scheduler = RecordingScheduler()
    val tracker = ViewabilityTracker(clock = { now }, scheduler = scheduler)
    return Triple(tracker, { dt: Double -> now += dt }, scheduler)
}

class ViewabilityTrackerTest {
    @Test fun `geometry produces updates with the true ratio`() {
        val (t, _, _) = makeTracker()
        val received = ArrayList<ViewabilityUpdate>()
        t.onUpdate = { received += it }
        t.register("ad", ViewabilityMode.DISPLAY)
        t.updateScrollViewBounds(bounds)
        t.updateContentFrame("ad", adFrame(0.75))
        assertTrue(received.isNotEmpty())
        assertEquals(0.75, received.last().ratio, 1e-6)
        assertTrue(received.last().isVisible)
    }

    @Test fun `dwell accrues via the clock and latches at 1s`() {
        val (t, advance, scheduler) = makeTracker()
        var latched = false
        t.onUpdate = { if (it.becameViewable) latched = true }
        t.register("ad", ViewabilityMode.DISPLAY)
        t.updateScrollViewBounds(bounds)
        var y = 300.0
        t.updateContentFrame("ad", Rect(0.0, y, 100.0, 100.0))
        assertTrue(scheduler.scheduled >= 1) // ticker armed while counting
        repeat(4) { advance(0.3); y += 3; t.updateContentFrame("ad", Rect(0.0, y, 100.0, 100.0)) }
        assertTrue(latched)
    }

    @Test fun `host hidden and app inactive reset the timer`() {
        val (t, advance, _) = makeTracker()
        var last: ViewabilityUpdate? = null
        t.onUpdate = { last = it }
        t.register("ad", ViewabilityMode.DISPLAY)
        t.updateScrollViewBounds(bounds)
        t.updateContentFrame("ad", Rect(0.0, 300.0, 100.0, 100.0))
        advance(0.7); t.updateContentFrame("ad", Rect(0.0, 301.0, 100.0, 100.0))
        t.setHostVisible(false)
        assertFalse(last!!.isVisible); assertFalse(last!!.isAppActive)
        t.setHostVisible(true)
        advance(0.6); t.updateContentFrame("ad", Rect(0.0, 302.0, 100.0, 100.0))
        assertFalse(last!!.isViewable)
        advance(0.5); t.updateContentFrame("ad", Rect(0.0, 303.0, 100.0, 100.0))
        assertTrue(last!!.isViewable)
        t.setAppActive(false)
        assertFalse(last!!.isAppActive)
    }

    @Test fun `JS emit policy forwards transitions and 5 percent jumps only`() {
        val (t, _, _) = makeTracker()
        val js = ArrayList<ViewabilityUpdate>()
        t.onJsUpdate = { js += it }
        t.register("ad", ViewabilityMode.DISPLAY)
        t.updateScrollViewBounds(bounds)
        t.updateContentFrame("ad", adFrame(0.60)); assertEquals(1, js.size)
        t.updateContentFrame("ad", adFrame(0.62)); assertEquals(1, js.size) // < 5 %
        t.updateContentFrame("ad", adFrame(0.70)); assertEquals(2, js.size) // ≥ 5 %
        t.updateContentFrame("ad", adFrame(0.40)); assertEquals(3, js.size) // visible → false
    }

    @Test fun `clips emit on significant change and unregister stops everything`() {
        val (t, _, _) = makeTracker()
        val clips = ArrayList<ViewportClipCalculator.Clip>()
        t.onClip = { _, c -> clips += c }
        var updates = 0
        t.onUpdate = { updates++ }
        t.register("ad", ViewabilityMode.DISPLAY)
        t.updateScrollViewBounds(bounds)
        t.updateContentFrame("ad", Rect(0.0, 750.0, 100.0, 100.0)); assertEquals(1, clips.size)
        t.updateContentFrame("ad", Rect(0.0, 751.0, 100.0, 100.0)); assertEquals(1, clips.size)
        t.updateContentFrame("ad", Rect(0.0, 760.0, 100.0, 100.0)); assertEquals(2, clips.size)
        val before = updates
        t.unregister("ad")
        t.updateContentFrame("ad", Rect(0.0, 300.0, 100.0, 100.0))
        t.updateScrollViewBounds(bounds.offsetBy(0.0, 1.0))
        assertEquals(before, updates)
    }
}

class TcfApiStubTest {
    @Test fun `TC string is JSON-encoded and cannot break out`() {
        val hostile = "\"; alert(1); //</script>"
        val script = TcfApiStub.script(hostile, true)
        assertTrue(script.contains("""var tc = {"""))
        assertFalse(script.contains("</script>"))
        assertTrue(script.contains("\\\"; alert(1); //<\\/script>"))
        assertTrue(script.contains("\"gdprApplies\":true"))
        assertTrue(TcfApiStub.script("abc", null).contains("\"gdprApplies\":null"))
        assertTrue(script.contains("eventStatus: 'tcloaded'"))
    }

    @Test fun `TCData carries decoded purpose and vendor maps like a real CMP`() {
        // The STEP template reads tcData.purpose.consents / .legitimateInterests;
        // the decoder itself is exercised in a JS engine by the iOS suite
        // (TCFConsentProviderTests) — the JavaScript is byte-identical here.
        val script = TcfApiStub.script("CQn2q4AQn2q4AAHABADACoFsAP_gAELgAAZQ", true)
        assertTrue(script.contains("function decodeCore(tcString)"))
        assertTrue(script.contains("purpose: { consents: d.purposeConsents || {}, legitimateInterests: d.purposeLegitimateInterests || {} }"))
        assertTrue(script.contains("vendor: { consents: d.vendorConsents || {}, legitimateInterests: d.vendorLegitimateInterests || {} }"))
        assertTrue(script.contains("try { decoded = decodeCore(tc.tcString); } catch (e) { decoded = null; }"))
        assertFalse(script.contains("\$")) // raw Kotlin template markers must not leak into JS
    }
}
