import Foundation

/// `ConsentProvider` for apps that already run their own TCF-certified CMP
/// (Didomi, Cookiebot, OneTrust, Usercentrics, …). The SDK does not show any
/// consent UI in this mode — it reads the user's answer from the IAB TCF
/// standard location (`UserDefaults`, the `IABTCF_*` keys every certified
/// CMP is required to maintain) and hands it to the ad page through a
/// standard in-app-webview `__tcfapi` stub, so GPT/Yield Manager can read
/// consent in-page.
///
/// Requirements (see GUIDE.md "Bringing your own CMP"):
/// - The app's CMP must be TCF-registered (it writes `IABTCF_TCString`).
/// - The ad template page must NOT load a CMP web tag of its own —
///   coordinate the template with STEP Network.
public final class TCFConsentProvider: NSObject, ConsentProvider {

    private static let tcStringKey = "IABTCF_TCString"
    private static let gdprAppliesKey = "IABTCF_gdprApplies"

    private let defaults: UserDefaults
    private var onChange: (() -> Void)?
    private var isObserving = false

    /// - Parameter defaults: injectable for tests; TCF-certified CMPs write
    ///   to `UserDefaults.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    deinit {
        if isObserving {
            defaults.removeObserver(self, forKeyPath: Self.tcStringKey)
            defaults.removeObserver(self, forKeyPath: Self.gdprAppliesKey)
        }
    }

    /// True once the app's CMP has recorded an answer: a TC string exists,
    /// or the CMP determined GDPR does not apply (`IABTCF_gdprApplies == 0`,
    /// distinguished from the key being absent).
    public var isConsentDetermined: Bool {
        if let tcString = defaults.string(forKey: Self.tcStringKey), !tcString.isEmpty {
            return true
        }
        return (defaults.object(forKey: Self.gdprAppliesKey) as? Int) == 0
    }

    public func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        defaults.addObserver(self, forKeyPath: Self.tcStringKey, options: [], context: nil)
        defaults.addObserver(self, forKeyPath: Self.gdprAppliesKey, options: [], context: nil)
        isObserving = true
        // Consent may already be stored from a previous launch — open the
        // gate immediately instead of waiting for the next CMP write.
        onChange()
    }

    // swiftlint:disable:next block_based_kvo
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        debugPrint("[SN] [NATIVE] TCFConsentProvider: \(keyPath ?? "IABTCF") changed")
        onChange?()
    }

    /// The TC string crosses into JavaScript — encoded via JSONEncoder and
    /// spliced only as a JSON object literal (never raw interpolation), so a
    /// corrupt/hostile UserDefaults value stays a JS string value.
    public func javaScriptForWebView() -> String {
        struct Payload: Encodable {
            let tcString: String
            let gdprApplies: Bool?
        }
        let gdprApplies = (defaults.object(forKey: Self.gdprAppliesKey) as? Int).map { $0 != 0 }
        let payload = Payload(
            tcString: defaults.string(forKey: Self.tcStringKey) ?? "",
            gdprApplies: gdprApplies
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        // IAB-standard __tcfapi stub for in-app webviews. The TCData it hands
        // out carries the DECODED purpose/vendor maps (the STEP template reads
        // tcData.purpose.consents / .legitimateInterests). Keep this JavaScript
        // byte-identical to TcfApiStub.kt in the Flutter plugin's Android port.
        return """
        (function () {
            var tc = \(json);
            var nextListenerId = 1;
            // Decodes the TC string's core segment (IAB TCF v2.x) into the maps a
            // real CMP exposes on TCData. Defensive: anything malformed yields null,
            // which becomes empty maps below — the page must never see an exception.
            function decodeCore(tcString) {
                var seg = String(tcString || '').split('.')[0];
                var A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
                var bits = '';
                for (var i = 0; i < seg.length; i++) {
                    var v = A.indexOf(seg.charAt(i));
                    if (v < 0) { return null; }
                    bits += ('00000' + v.toString(2)).slice(-6);
                }
                if (bits.length < 213) { return null; }
                var p = 0;
                function int(n) { var v = parseInt(bits.substr(p, n) || '0', 2); p += n; return v; }
                function flags(n) { var out = {}; for (var i = 1; i <= n; i++) { out[i] = bits.charAt(p + i - 1) === '1'; } p += n; return out; }
                function letters(n) { var s = ''; for (var i = 0; i < n; i++) { s += String.fromCharCode(65 + int(6)); } return s; }
                function vendors() {
                    var out = {}; var max = int(16); var range = int(1) === 1;
                    if (!range) {
                        for (var i = 1; i <= max; i++) { if (bits.charAt(p + i - 1) === '1') { out[i] = true; } }
                        p += max;
                    } else {
                        var n = int(12);
                        for (var j = 0; j < n; j++) {
                            var isRange = int(1) === 1; var start = int(16); var end = isRange ? int(16) : start;
                            if (end < start || end - start > 65535) { break; }
                            for (var id = start; id <= end; id++) { out[id] = true; }
                        }
                    }
                    return out;
                }
                var d = {};
                d.version = int(6); p += 72; // created + lastUpdated
                d.cmpId = int(12); d.cmpVersion = int(12); p += 6; // consentScreen
                d.consentLanguage = letters(2); d.vendorListVersion = int(12); d.tcfPolicyVersion = int(6);
                d.isServiceSpecific = int(1) === 1; d.useNonStandardTexts = int(1) === 1;
                d.specialFeatureOptins = flags(12);
                d.purposeConsents = flags(24); d.purposeLegitimateInterests = flags(24);
                d.purposeOneTreatment = int(1) === 1; d.publisherCC = letters(2);
                d.vendorConsents = vendors(); d.vendorLegitimateInterests = vendors();
                return d;
            }
            var decoded = null;
            try { decoded = decodeCore(tc.tcString); } catch (e) { decoded = null; }
            var d = decoded || {};
            // Consent is final at injection time, so every command answers from the
            // same snapshot with eventStatus 'tcloaded'.
            function tcData(listenerId) {
                return {
                    tcString: tc.tcString,
                    gdprApplies: tc.gdprApplies,
                    tcfPolicyVersion: d.tcfPolicyVersion || 2,
                    cmpId: d.cmpId || 0,
                    cmpVersion: d.cmpVersion || 0,
                    cmpStatus: 'loaded',
                    eventStatus: 'tcloaded',
                    listenerId: listenerId === undefined ? null : listenerId,
                    isServiceSpecific: !!d.isServiceSpecific,
                    useNonStandardTexts: !!d.useNonStandardTexts,
                    useNonStandardStacks: !!d.useNonStandardTexts,
                    publisherCC: d.publisherCC || '',
                    purposeOneTreatment: !!d.purposeOneTreatment,
                    outOfBand: { allowedVendors: {}, disclosedVendors: {} },
                    purpose: { consents: d.purposeConsents || {}, legitimateInterests: d.purposeLegitimateInterests || {} },
                    vendor: { consents: d.vendorConsents || {}, legitimateInterests: d.vendorLegitimateInterests || {} },
                    specialFeatureOptins: d.specialFeatureOptins || {},
                    publisher: { consents: {}, legitimateInterests: {}, customPurpose: { consents: {}, legitimateInterests: {} }, restrictions: {} }
                };
            }
            window.__tcfapi = function (command, version, callback, parameter) {
                if (typeof callback !== 'function') { return; }
                if (command === 'ping') {
                    callback({
                        gdprApplies: tc.gdprApplies,
                        cmpLoaded: true,
                        cmpStatus: 'loaded',
                        displayStatus: 'disabled',
                        apiVersion: '2.2',
                        cmpId: d.cmpId || 0,
                        cmpVersion: d.cmpVersion || 0,
                        gvlVersion: d.vendorListVersion || 0,
                        tcfPolicyVersion: d.tcfPolicyVersion || 2
                    });
                } else if (command === 'getTCData') {
                    callback(tcData(), true);
                } else if (command === 'addEventListener') {
                    callback(tcData(nextListenerId++), true);
                } else if (command === 'removeEventListener') {
                    callback(true);
                } else {
                    callback(null, false);
                }
            };
        })();
        """
    }

    public func showPreferences() {
        debugPrint("""
        [SN] [NATIVE] TCFConsentProvider: showPreferences() is a no-op — \
        this app owns its CMP; open that CMP's preferences UI from the app.
        """)
    }
}
