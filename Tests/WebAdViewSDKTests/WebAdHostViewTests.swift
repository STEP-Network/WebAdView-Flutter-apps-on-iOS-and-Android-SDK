import Testing
import CoreGraphics
import Foundation
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - WebAdHostView (UIKit host for one ad's webview)
//
// The host view wraps WebAdViewController exactly like the SwiftUI
// representable does. A stub consent provider is injected through the
// internal seam so WebAdViewSDK.configuration (process-wide) is untouched;
// without a configuration the template URL is empty, which is also the
// "SDK never initialized" path exercised below.

@MainActor
private func makeHost(consent: ConsentProvider? = nil, viewportResizing: Bool = true) -> (WebAdHostView, WebAdScope) {
    let scope = WebAdScope(
        config: LazyLoadingConfig(),
        remoteStore: RemoteLazyLoadStore(defaults: UserDefaults(suiteName: "WebAdHostViewTests")!),
        templateHost: nil
    )
    scope.register("div-gpt-ad-mobile_1")
    let host = WebAdHostView(
        adUnitId: "div-gpt-ad-mobile_1",
        scope: scope,
        customTargeting: ["section": ["homepage"]],
        viewportResizing: viewportResizing,
        debugSettings: DebugSettings(),
        consentProviderOverride: consent
    )
    return (host, scope)
}

@MainActor
@Suite("WebAdHostView")
struct WebAdHostViewTests {

    @Test("Embeds the controller's view full-size and creates the webview")
    func embedsControllerView() {
        let (host, _) = makeHost()
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        host.layoutIfNeeded()

        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === host.controller.view)
        #expect(host.controller.view.frame == host.bounds)
        #expect(host.controller.webView != nil)
        #expect(host.controller.viewportResizingEnabled)
    }

    @Test("Creation without WebAdViewSDK.initialize does not crash and loads nothing")
    func noConfigurationIsSafe() {
        // No configuration → empty template URL → the loud [SN] [ERROR] path
        // in loadAdContent; hasLoadedContent must stay false so a later
        // init/consent can retry.
        let (host, _) = makeHost(consent: StubConsentProvider(determined: true))
        #expect(WebAdViewSDK.configuration == nil || host.controller.hasLoadedContent)
        if WebAdViewSDK.configuration == nil {
            #expect(!host.controller.hasLoadedContent)
        }
    }

    @Test("adSize bridge messages reach onAdSizeChange")
    func adSizeForwarded() {
        let (host, _) = makeHost()
        var received: CGSize?
        host.onAdSizeChange = { received = $0 }

        // NSNumber, as WKScriptMessage actually delivers JS numbers.
        host.controller.handleBridgeMessage([
            "type": "adSize",
            "width": NSNumber(value: 300),
            "height": NSNumber(value: 250),
        ] as [String: Any])
        #expect(received == CGSize(width: 300, height: 250))
    }

    @Test("impressionViewable bridge messages reach onActiveViewImpression")
    func activeViewForwarded() {
        let (host, _) = makeHost()
        var slot: String?
        host.onActiveViewImpression = { slot = $0 }

        host.controller.handleBridgeMessage(["type": "impressionViewable", "slotId": "div-gpt-ad-mobile_1"])
        #expect(slot == "div-gpt-ad-mobile_1")
    }

    @Test("unload tears the webview down")
    func unloadRemovesWebView() {
        let (host, _) = makeHost()
        #expect(host.controller.webView != nil)
        host.unload()
        #expect(host.controller.webView == nil)
    }

    @Test("Undetermined consent holds the template back (fail-closed)")
    func consentGateHoldsBack() {
        let (host, _) = makeHost(consent: StubConsentProvider(determined: false))
        #expect(!host.controller.hasLoadedContent)
    }

    @Test("Scope is held weakly")
    func scopeIsWeak() {
        var scope: WebAdScope? = WebAdScope(
            config: LazyLoadingConfig(),
            remoteStore: RemoteLazyLoadStore(defaults: UserDefaults(suiteName: "WebAdHostViewTests")!),
            templateHost: nil
        )
        let host = WebAdHostView(
            adUnitId: "ad",
            scope: scope!,
            customTargeting: [:],
            viewportResizing: true,
            debugSettings: DebugSettings(),
            consentProviderOverride: nil
        )
        #expect(host.scope != nil)
        scope = nil
        #expect(host.scope == nil)
    }
}
