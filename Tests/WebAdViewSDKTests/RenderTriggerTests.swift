import Testing
import Foundation
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - Manual render trigger (exactly once per loaded page)
//
// The ad template renders only on the SDK's manual render event
// (Yield Manager manual mode). Two failure modes are guarded here:
// - `.displayed` observed BEFORE the page is ready (late webview creation
//   in Flutter, consent holdback) → the event must still fire, after
//   didFinish. Previously it silently never fired.
// - the manager's `$adStates` re-emits an ad's unchanged `.displayed` state
//   whenever ANY other ad transitions → the event must NOT fire again for
//   the same page (a duplicate event is a duplicate ad request).
// `renderTriggerCount` counts scheduled events; `handlePageFinished()` is the
// didFinish seam (no live page in tests).

@MainActor
private func makeController(consent: StubConsentProvider = StubConsentProvider(determined: true)) -> (WebAdViewController, LazyLoadingManager) {
    let controller = WebAdViewController(
        baseURL: "https://example.invalid/ad-template.html",
        adUnitId: "ad",
        debugSettings: DebugSettings()
    )
    controller.consentProviderOverride = consent
    let manager = LazyLoadingManager()
    return (controller, manager)
}

@MainActor
@Suite("Render trigger — once per page load")
struct RenderTriggerTests {

    @Test("displayed before the page is ready fires exactly once after didFinish")
    func displayedBeforeLoadFiresAfterFinish() {
        let (controller, manager) = makeController()
        manager.adStates["ad"] = .displayed          // already displayed when the webview is created
        controller.setupLazyLoadingObserver(manager: manager) // replays .displayed
        #expect(controller.renderTriggerCount == 0)

        controller.loadViewIfNeeded()                 // consent OK → template load starts
        #expect(controller.hasLoadedContent)
        #expect(controller.renderTriggerCount == 0)   // page not ready yet

        controller.handlePageFinished()
        #expect(controller.renderTriggerCount == 1)

        // Neighbour transitions re-publish the dictionary: no second event.
        manager.adStates["other"] = .fetched
        manager.adStates["other"] = .displayed
        controller.handlePageFinished()               // a spurious second didFinish must not re-fire either
        #expect(controller.renderTriggerCount == 1)
    }

    @Test("displayed after the page is ready fires exactly once")
    func displayedAfterLoadFiresOnce() {
        let (controller, manager) = makeController()
        controller.setupLazyLoadingObserver(manager: manager)
        controller.loadViewIfNeeded()
        controller.handlePageFinished()
        #expect(controller.renderTriggerCount == 0)

        manager.adStates["ad"] = .fetched
        #expect(controller.renderTriggerCount == 0)
        manager.adStates["ad"] = .displayed
        #expect(controller.renderTriggerCount == 1)

        manager.adStates["other"] = .displayed        // re-emits "ad": .displayed
        #expect(controller.renderTriggerCount == 1)
    }

    @Test("A consent-driven reload of a displayed ad re-fires once for the new page")
    func consentReloadRefires() {
        let stub = StubConsentProvider(determined: true)
        stub.consentJS = "// consent v1"
        let (controller, manager) = makeController(consent: stub)
        controller.setupLazyLoadingObserver(manager: manager)
        controller.loadViewIfNeeded()
        controller.handlePageFinished()
        manager.adStates["ad"] = .displayed
        #expect(controller.renderTriggerCount == 1)

        // The user changes their answer → the page reloads with new consent.
        stub.consentJS = "// consent v2"
        NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)
        #expect(controller.hasLoadedContent)
        #expect(controller.renderTriggerCount == 1)   // fresh page not ready yet

        controller.handlePageFinished()
        #expect(controller.renderTriggerCount == 2)
        controller.handlePageFinished()
        #expect(controller.renderTriggerCount == 2)
    }

    @Test("Consent holdback: displayed while held back renders after the consent-driven load")
    func consentHoldbackRenders() {
        let stub = StubConsentProvider(determined: false)
        let (controller, manager) = makeController(consent: stub)
        controller.setupLazyLoadingObserver(manager: manager)
        controller.loadViewIfNeeded()
        #expect(!controller.hasLoadedContent)

        manager.adStates["ad"] = .displayed           // scrolled into view before the notice was answered
        #expect(controller.renderTriggerCount == 0)

        stub.isConsentDetermined = true
        NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)
        #expect(controller.hasLoadedContent)
        controller.handlePageFinished()
        #expect(controller.renderTriggerCount == 1)
    }
}
