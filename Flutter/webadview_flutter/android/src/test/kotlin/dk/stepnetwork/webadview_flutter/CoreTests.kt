package dk.stepnetwork.webadview_flutter

import dk.stepnetwork.webadview_flutter.core.AdLoadState
import dk.stepnetwork.webadview_flutter.core.BridgeMessage
import dk.stepnetwork.webadview_flutter.core.Cancellable
import dk.stepnetwork.webadview_flutter.core.DelayedScheduler
import dk.stepnetwork.webadview_flutter.core.LazyLoadingConfig
import dk.stepnetwork.webadview_flutter.core.LazyLoadingManager
import dk.stepnetwork.webadview_flutter.core.Rect
import dk.stepnetwork.webadview_flutter.core.RemoteLazyLoadConfig
import dk.stepnetwork.webadview_flutter.core.TargetingScriptBuilder
import dk.stepnetwork.webadview_flutter.core.TemplateUrl
import dk.stepnetwork.webadview_flutter.core.ViewabilityEngine
import dk.stepnetwork.webadview_flutter.core.ViewabilityMode
import dk.stepnetwork.webadview_flutter.core.ViewportClipCalculator
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// JVM ports of Tests/WebAdViewCoreTests/* — same fixtures, same expectations.

private val bounds = Rect(0.0, 0.0, 400.0, 800.0)

/** A 100dp-tall ad whose top edge sits `distance` below the viewport's bottom edge. */
private fun adBelowViewport(distance: Double) = Rect(0.0, bounds.maxY + distance, 320.0, 100.0)

/** Scheduler stub that never fires (clock steps are ≥ 67 ms so the throttle takes the immediate path). */
private val neverScheduler = DelayedScheduler { _, _ -> Cancellable {} }

private class TestClock(var ms: Long = 0) {
    fun advance(seconds: Double) { ms += (seconds * 1000).toLong() }
}

private fun makeManager(unloading: Boolean = false): Pair<LazyLoadingManager, TestClock> {
    val clock = TestClock()
    val manager = LazyLoadingManager(now = { clock.ms }, scheduler = neverScheduler)
    manager.configure(LazyLoadingConfig(unloadingEnabled = unloading))
    manager.updateScrollViewBounds(bounds)
    return manager to clock
}

class ViewabilityEngineTest {
    private val viewport = Rect(0.0, 0.0, 400.0, 800.0)
    private fun ad(visibleFraction: Double) = Rect(0.0, 700.0 + (1 - visibleFraction) * 100, 100.0, 100.0)

    @Test fun `intersection ratio is the visible fraction`() {
        assertEquals(0.75, ViewabilityEngine.intersectionRatio(ad(0.75), viewport), 1e-9)
        assertEquals(0.0, ViewabilityEngine.intersectionRatio(Rect(0.0, 900.0, 100.0, 100.0), viewport))
        assertEquals(0.0, ViewabilityEngine.intersectionRatio(Rect(0.0, 0.0, 0.0, 0.0), viewport))
    }

    @Test fun `50 percent for 1s latches, dips reset`() {
        val e = ViewabilityEngine("ad", ViewabilityMode.DISPLAY)
        assertTrue(e.ingest(ad(0.5), viewport, true, 0.0).isVisible)
        assertFalse(e.ingest(ad(0.5), viewport, true, 0.9).isViewable)
        val u = e.ingest(ad(0.5), viewport, true, 1.0)
        assertTrue(u.isViewable); assertTrue(u.becameViewable)
        assertFalse(e.ingest(ad(0.5), viewport, true, 1.1).becameViewable) // once only

        val e2 = ViewabilityEngine("ad", ViewabilityMode.DISPLAY)
        e2.ingest(ad(1.0), viewport, true, 0.0)
        e2.ingest(ad(0.4), viewport, true, 0.6) // dip → reset
        e2.ingest(ad(1.0), viewport, true, 0.7)
        assertFalse(e2.ingest(ad(1.0), viewport, true, 1.5).isViewable) // only 0.8s continuous
        assertTrue(e2.ingest(ad(1.0), viewport, true, 1.7).isViewable)
    }

    @Test fun `backgrounding resets the timer and video needs 2s`() {
        val e = ViewabilityEngine("ad", ViewabilityMode.VIDEO)
        e.ingest(ad(1.0), viewport, true, 0.0)
        e.ingest(ad(1.0), viewport, false, 0.5) // app inactive → idle
        e.ingest(ad(1.0), viewport, true, 0.6)
        assertFalse(e.ingest(ad(1.0), viewport, true, 2.5).isViewable)
        assertTrue(e.ingest(ad(1.0), viewport, true, 2.6).isViewable)
        e.reset()
        assertFalse(e.ingest(ad(1.0), viewport, true, 2.7).isViewable)
    }
}

class LazyLoadingManagerTest {
    @Test fun `notLoaded to fetched to displayed as the ad approaches`() {
        val (m, clock) = makeManager()
        val states = ArrayList<AdLoadState>()
        m.onStateChange = { _, s -> states += s }
        m.updateAdFrame("ad", adBelowViewport(1000.0))
        assertEquals(null, m.adStates["ad"])
        clock.advance(0.1); m.updateAdFrame("ad", adBelowViewport(500.0))
        assertEquals(AdLoadState.FETCHED, m.adStates["ad"])
        clock.advance(0.1); m.updateAdFrame("ad", adBelowViewport(100.0))
        assertEquals(AdLoadState.DISPLAYED, m.adStates["ad"])
        assertEquals(listOf(AdLoadState.FETCHED, AdLoadState.DISPLAYED), states)
    }

    @Test fun `unloading needs 2s of stability and re-fetches on return`() {
        val (m, clock) = makeManager(unloading = true)
        m.updateAdFrame("ad", adBelowViewport(100.0)); clock.advance(0.1)
        m.updateAdFrame("ad", adBelowViewport(50.0))
        assertEquals(AdLoadState.DISPLAYED, m.adStates["ad"])
        clock.advance(0.1); m.updateAdFrame("ad", adBelowViewport(2000.0)) // candidate
        assertEquals(AdLoadState.DISPLAYED, m.adStates["ad"])
        clock.advance(1.0); m.updateAdFrame("ad", adBelowViewport(2001.0))
        assertEquals(AdLoadState.DISPLAYED, m.adStates["ad"])
        clock.advance(1.1); m.updateAdFrame("ad", adBelowViewport(2002.0))
        assertEquals(AdLoadState.UNLOADED, m.adStates["ad"])
        clock.advance(0.1); m.updateAdFrame("ad", adBelowViewport(500.0))
        assertEquals(AdLoadState.NOT_LOADED, m.adStates["ad"])
        clock.advance(0.1); m.updateAdFrame("ad", adBelowViewport(499.0))
        assertEquals(AdLoadState.FETCHED, m.adStates["ad"])
    }

    @Test fun `remote percentages override local thresholds and unload stays beyond fetch`() {
        val (m, clock) = makeManager(unloading = true)
        assertTrue(m.applyRemote(RemoteLazyLoadConfig(fetch = 150.0, render = 100.0)))
        // fetch distance = 1.5 * 800 = 1200 > local 800
        m.updateAdFrame("ad", adBelowViewport(1100.0))
        assertEquals(AdLoadState.FETCHED, m.adStates["ad"])
        clock.advance(0.1); m.updateAdFrame("ad", adBelowViewport(700.0)) // < 800 render distance
        assertEquals(AdLoadState.DISPLAYED, m.adStates["ad"])
        assertFalse(m.applyRemote(RemoteLazyLoadConfig(fetch = 100.0, render = 150.0)))
    }

    @Test fun `removeAd forgets frame and state`() {
        val (m, _) = makeManager()
        m.updateAdFrame("ad", adBelowViewport(100.0))
        m.removeAd("ad")
        assertNull(m.adStates["ad"]); assertNull(m.adUnitFrames["ad"])
    }
}

class RemoteLazyLoadConfigTest {
    @Test fun `parses a valid object and rejects everything else`() {
        assertEquals(RemoteLazyLoadConfig(150.0, 100.0), RemoteLazyLoadConfig.parse("""{"fetch":150,"render":100}"""))
        for (bad in listOf(null, "", "null", "[]", "not json", """{"fetch":"x","render":100}""", """{"render":100}""")) {
            assertNull(RemoteLazyLoadConfig.parse(bad), "should reject: $bad")
        }
        assertFalse(RemoteLazyLoadConfig(100.0, 150.0).isValid)
        assertFalse(RemoteLazyLoadConfig(9999999.0, 1.0).isValid)
        assertFalse(RemoteLazyLoadConfig(0.0, 0.0).isValid)
        assertTrue(RemoteLazyLoadConfig.parse(RemoteLazyLoadConfig(150.0, 100.0).toJson())!!.isValid)
    }
}

class TargetingScriptBuilderTest {
    @Test fun `values are JSON-encoded, keys sorted, script tags neutralised`() {
        val script = TargetingScriptBuilder.script(mapOf(
            "tags" to listOf("breaking", "a\"b"),
            "section" to listOf("</script><script>alert(1)</script>"),
            "empty" to emptyList(),
        ))!!
        assertTrue(script.indexOf("\"section\"") < script.indexOf("\"tags\""))
        assertTrue(script.contains("""setTargeting("tags", ["breaking","a\"b"])"""))
        assertFalse(script.contains("</script>"))
        assertTrue(script.contains("<\\/script>"))
        assertFalse(script.contains("\"empty\""))
        assertNull(TargetingScriptBuilder.script(emptyMap()))
    }
}

class ViewportClipCalculatorTest {
    @Test fun `full, partial and hidden clips`() {
        val vp = Rect(0.0, 0.0, 400.0, 800.0)
        val full = ViewportClipCalculator.clip(Rect(40.0, 100.0, 320.0, 250.0), vp)
        assertTrue(full.isFullyVisible); assertEquals(Rect(0.0, 0.0, 320.0, 250.0), full.sliceFrame)
        val partial = ViewportClipCalculator.clip(Rect(40.0, 700.0, 320.0, 250.0), vp)
        assertFalse(partial.isFullyVisible); assertFalse(partial.isFullyHidden)
        assertEquals(Rect(0.0, 0.0, 320.0, 100.0), partial.sliceFrame)
        val above = ViewportClipCalculator.clip(Rect(40.0, -100.0, 320.0, 250.0), vp)
        assertEquals(Rect(0.0, 100.0, 320.0, 150.0), above.sliceFrame)
        assertEquals(100.0, above.contentOffsetY)
        assertTrue(ViewportClipCalculator.clip(Rect(40.0, 900.0, 320.0, 250.0), vp).isFullyHidden)
        assertFalse(ViewportClipCalculator.differsSignificantly(partial, ViewportClipCalculator.clip(Rect(40.0, 701.0, 320.0, 250.0), vp)))
        assertTrue(ViewportClipCalculator.differsSignificantly(partial, ViewportClipCalculator.clip(Rect(40.0, 710.0, 320.0, 250.0), vp)))
    }
}

class BridgeMessageTest {
    @Test fun `messages parse defensively`() {
        assertEquals(BridgeMessage.AdSize(320.0, 250.0), BridgeMessage.parse("""{"type":"adSize","width":320,"height":250}"""))
        assertTrue(BridgeMessage.parse("""{"type":"adSize","width":"320","height":"250"}""") is BridgeMessage.Unknown)
        assertTrue(BridgeMessage.parse("""{"type":"adSize","width":320}""") is BridgeMessage.Unknown)
        assertEquals(BridgeMessage.ImpressionViewable("unknown"), BridgeMessage.parse("""{"type":"impressionViewable","slotId":5}"""))
        assertEquals(BridgeMessage.ImpressionViewable("div-1"), BridgeMessage.parse("""{"type":"impressionViewable","slotId":"div-1"}"""))
        assertEquals(BridgeMessage.Console("warn", "hi"), BridgeMessage.parse("""{"type":"console","level":"warn","message":"hi"}"""))
        assertTrue(BridgeMessage.parse("not json") is BridgeMessage.Garbage)
        assertTrue(BridgeMessage.parse("[1,2]") is BridgeMessage.Garbage)
        assertTrue(BridgeMessage.parse("""{"width":1}""") is BridgeMessage.Unknown)
        assertTrue(BridgeMessage.parse(null) is BridgeMessage.Garbage)
    }
}

class InjectedScriptsTest {
    @Test fun `page scale pin clamps the viewport scale to 1 and carries no data`() {
        val s = dk.stepnetwork.webadview_flutter.web.InjectedScripts.PAGE_SCALE_PIN
        assertTrue(s.contains("minimum-scale=1"))
        assertTrue(s.contains("maximum-scale=1"))
        assertTrue(s.contains("user-scalable=no"))
        assertTrue(s.contains("width=device-width")) // keeps the template's layout width
        assertFalse(s.contains("\$"))                  // static script: nothing interpolated
    }
}

class TemplateUrlTest {
    @Test fun `assembles the template URL like iOS`() {
        assertEquals("https://h/t.html?didomi-disable-notice=true&rnd=r", TemplateUrl.assemble("https://h/t.html", false, "r"))
        assertEquals("https://h/t.html?didomi-disable-notice=true&aym_debug=true&rnd=r", TemplateUrl.assemble("https://h/t.html?didomi-disable-notice=true", true, "r"))
        assertEquals("https://adops.stepdev.dk", TemplateUrl.origin("https://adops.stepdev.dk/wp-content/ad-template.html?x=1"))
        assertEquals("https://h:8443", TemplateUrl.origin("https://h:8443/a"))
        assertNull(TemplateUrl.origin("ftp://h/a"))
        assertNotNull(TemplateUrl.host("https://h/a"))
    }
}
