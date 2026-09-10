import Testing
import Foundation
import JavaScriptCore
@testable import WebAdViewSDK

// MARK: - TCFConsentProvider (bring-your-own CMP)
//
// Every TCF-certified CMP writes the user's answer to the standardized
// IABTCF_* UserDefaults keys; the provider must gate ads on those keys and
// hand consent to the page as data, never as executable code.

@Suite("TCFConsentProvider")
struct TCFConsentProviderTests {

    /// Fresh isolated defaults per test.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "tcf-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func undeterminedWhenNoKeysExist() {
        let provider = TCFConsentProvider(defaults: makeDefaults())
        #expect(provider.isConsentDetermined == false)
    }

    @Test func determinedWhenTCStringPresent() {
        let defaults = makeDefaults()
        defaults.set("CPz1234consent", forKey: "IABTCF_TCString")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == true)
    }

    @Test func emptyTCStringIsNotAnAnswer() {
        let defaults = makeDefaults()
        defaults.set("", forKey: "IABTCF_TCString")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == false)
    }

    @Test func determinedWhenGDPRDoesNotApply() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "IABTCF_gdprApplies")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == true)
    }

    @Test func gdprAppliesWithoutTCStringIsStillUndetermined() {
        let defaults = makeDefaults()
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == false)
    }

    @Test func startFiresImmediatelyAndOnEveryKeyChange() {
        let defaults = makeDefaults()
        let provider = TCFConsentProvider(defaults: defaults)
        var fires = 0
        provider.start { fires += 1 }
        #expect(fires == 1)  // stored consent must open the gate at once

        defaults.set("CPzNewConsent", forKey: "IABTCF_TCString")
        #expect(fires == 2)  // KVO on the TC string

        defaults.set(0, forKey: "IABTCF_gdprApplies")
        #expect(fires == 3)  // KVO on gdprApplies
    }

    @Test func webViewJSDefinesTCFAPIWithTheStoredString() {
        let defaults = makeDefaults()
        defaults.set("CPzABCDtcstring", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let js = TCFConsentProvider(defaults: defaults).javaScriptForWebView()
        #expect(js.contains("window.__tcfapi"))
        #expect(js.contains("\"CPzABCDtcstring\""))
        #expect(js.contains("'tcloaded'"))
    }

    @Test func hostileTCStringStaysJSONEscapedData() {
        let defaults = makeDefaults()
        defaults.set(#"evil"quote\back"#, forKey: "IABTCF_TCString")
        let js = TCFConsentProvider(defaults: defaults).javaScriptForWebView()
        // The raw quote/backslash must not survive unescaped — JSONEncoder
        // turns them into string data inside the object literal.
        #expect(!js.contains(#"evil"quote"#))
        #expect(js.contains(#"evil\"quote\\back"#))
    }

    // MARK: TCData shape — what the STEP template's consent listener reads

    /// Runs the stub in a real JS engine and returns the TCData object that
    /// `__tcfapi('getTCData')` hands to the page.
    private func tcData(for tcString: String?, gdprApplies: Int?) -> [String: Any] {
        let defaults = makeDefaults()
        if let tcString { defaults.set(tcString, forKey: "IABTCF_TCString") }
        if let gdprApplies { defaults.set(gdprApplies, forKey: "IABTCF_gdprApplies") }
        let js = TCFConsentProvider(defaults: defaults).javaScriptForWebView()
        let context = JSContext()!
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript("var window = this;")
        context.evaluateScript(js)
        context.evaluateScript("var out = null; window.__tcfapi('getTCData', 2, function (d, ok) { out = ok ? d : null; });")
        #expect(exception == nil, "stub must never throw: \(exception ?? "")")
        return context.objectForKeyedSubscript("out")?.toDictionary() as? [String: Any] ?? [:]
    }

    /// Didomi "accept all" string (TCF 2.2, 11 purposes, cmpId 7, DA/DK).
    private static let acceptAll = "CQn2q4AQn2q4AAHABADACoFsAP_gAELgAAZQLrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCQGEAIACABgACgBIAIAABAAAAABAAQAAAAIAAIAAAAAAEIBAIJCAAAAABAkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAgAAAjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAILrgR9C5cSWlBeTBXYIsAOAQXwFAAIIAgAAAAAgABCBqAIIQCUGEAIACAAAAAABAAIAABAAAIABAAQAABAIAQIBAAAAAAIBAIACAAAAABQkBQAAAAAgAAEAAAgEASAAAAgAAEQNIiQEAAEAAgjAAAIAAAAAAIAAAAAAAAAAEAAAAAgCAAEAAAAAAAAAAAABAIgAAAAAAAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAJCADAAEGVw.ILrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCUGEAIACABgACgBIAIAABAAAIABAAQAABAIAQIBAAAAAEIBAIJCAAAAABQkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAkAAgjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA"
    /// The matching "decline all" string.
    private static let declineAll = "CQn2q4AQn2q4AAHABADACoFgAAAAAAAAAAZQAAAGfgAgGfABIQAYAAgyuA.ILrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCUGEAIACABgACgBIAIAABAAAIABAAQAABAIAQIBAAAAAEIBAIJCAAAAABQkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAkAAgjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA"

    private func trueKeys(_ map: Any?) -> Set<Int> {
        Set((map as? [String: Any] ?? [:]).compactMap { key, value in
            (value as? Bool) == true ? Int(key) : nil
        })
    }

    @Test func tcDataCarriesDecodedPurposeMapsForAcceptAll() {
        let data = tcData(for: Self.acceptAll, gdprApplies: 1)
        #expect(data["tcString"] as? String == Self.acceptAll)
        #expect(data["gdprApplies"] as? Bool == true)
        #expect(data["eventStatus"] as? String == "tcloaded")
        #expect(data["cmpId"] as? Int == 7)            // Didomi
        #expect(data["tcfPolicyVersion"] as? Int == 5) // TCF 2.2
        #expect(data["publisherCC"] as? String == "DK")
        let purpose = data["purpose"] as? [String: Any]
        #expect(trueKeys(purpose?["consents"]) == Set(1...11))
        #expect(trueKeys(purpose?["legitimateInterests"]) == [2, 7, 9, 10, 11])
        #expect(trueKeys(data["specialFeatureOptins"]) == [1, 2])
        let vendor = data["vendor"] as? [String: Any]
        let vendorConsents = trueKeys(vendor?["consents"])
        let vendorLI = trueKeys(vendor?["legitimateInterests"])
        #expect(vendorConsents.count == 141)
        #expect(vendorLI.count == 129)
    }

    @Test func tcDataCarriesEmptyPurposeMapsForDeclineAll() {
        let data = tcData(for: Self.declineAll, gdprApplies: 1)
        let purpose = data["purpose"] as? [String: Any]
        let consents = trueKeys(purpose?["consents"])
        let li = trueKeys(purpose?["legitimateInterests"])
        let vendorConsents = trueKeys((data["vendor"] as? [String: Any])?["consents"])
        #expect(consents.isEmpty)
        #expect(li.isEmpty)
        // Every purpose key is still present (false), as a CMP reports it.
        #expect((purpose?["consents"] as? [String: Any])?.count == 24)
        #expect(vendorConsents.isEmpty)
    }

    @Test func tcDataStaysWellFormedForGarbageOrMissingStrings() {
        for (string, gdpr) in [("not-a-tc-string!!", 1), ("", 1), (nil, 0), ("CPz", 1)] as [(String?, Int?)] {
            let data = tcData(for: string, gdprApplies: gdpr)
            let purpose = data["purpose"] as? [String: Any]
            #expect(purpose?["consents"] is [String: Any])
            #expect(purpose?["legitimateInterests"] is [String: Any])
            let consents = trueKeys(purpose?["consents"])
            #expect(consents.isEmpty)
            #expect(data["eventStatus"] as? String == "tcloaded")
        }
    }

    @Test @MainActor func modeTwoConfigCarriesTheProvider() {
        let provider = TCFConsentProvider(defaults: makeDefaults())
        let config = WebAdViewSDKConfig(
            consentProvider: provider,
            adTemplateURL: URL(string: "https://publisher.dk/template.html")!
        )
        #expect(config.consentProvider === provider)
        #expect(config.consentProvider.isConsentDetermined == false)
        // App-owned CMP: preferences is a safe no-op
        config.consentProvider.showPreferences()
    }
}
