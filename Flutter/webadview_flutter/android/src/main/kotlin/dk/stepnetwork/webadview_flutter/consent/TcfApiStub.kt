package dk.stepnetwork.webadview_flutter.consent

import org.json.JSONObject

/**
 * The minimal in-app-webview `__tcfapi` stub (port of
 * TCFConsentProvider.javaScriptForWebView). The TC string crosses into
 * JavaScript only as a JSON-encoded literal, so a corrupt or hostile stored
 * value stays a JS string value. Consent is final at injection time, so every
 * command answers from the same snapshot with eventStatus 'tcloaded'.
 */
object TcfApiStub {
    fun script(tcString: String, gdprApplies: Boolean?): String {
        val tc = JSONObject()
            .put("tcString", tcString)
            .put("gdprApplies", gdprApplies ?: JSONObject.NULL)
            .toString()
            .replace("</", "<\\/")
        // Keep this JavaScript byte-identical to TCFConsentProvider.swift (iOS SDK).
        return """
        (function () {
            var tc = $tc;
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
        """.trimIndent()
    }
}
