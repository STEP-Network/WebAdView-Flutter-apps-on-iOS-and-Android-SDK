package dk.stepnetwork.webadview_flutter.web

import org.json.JSONObject

/**
 * The JavaScript the SDK injects into every ad page. Sources are the iOS
 * scripts verbatim where possible (single source of truth for the bridge
 * contract), plus the Android-only bridge shim.
 */
object InjectedScripts {

    /**
     * Android-only: the STEP ad template (and the iOS-authored listeners
     * below) call `window.webkit.messageHandlers.nativeBridge.postMessage(obj)`.
     * This shim defines that object and forwards `JSON.stringify(obj)` to the
     * real Android bridge (`window.nativeBridge.postMessage(string)`,
     * bridge-contract §2). Never overrides a real WebKit handler.
     */
    const val BRIDGE_SHIM = """
    (function () {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge) { return; }
        window.webkit = window.webkit || {};
        window.webkit.messageHandlers = window.webkit.messageHandlers || {};
        window.webkit.messageHandlers.nativeBridge = {
            postMessage: function (message) {
                try {
                    if (window.nativeBridge && typeof window.nativeBridge.postMessage === 'function') {
                        window.nativeBridge.postMessage(JSON.stringify(message));
                    }
                } catch (e) {}
            }
        };
    })();
    """

    /**
     * Android-only: pins the page scale (bridge-contract §8, finding 3).
     * Chromium keeps the visible CSS width constant when the WebView's width
     * changes, which compounds into a zoomed, cropped creative across ad
     * refreshes that alternate widths (300 ↔ 320). A viewport meta with
     * `minimum-scale=1, maximum-scale=1` clamps every scale adjustment to 1.
     * Appended AFTER the template's own meta so it wins; static, no data.
     */
    const val PAGE_SCALE_PIN = """
    (function () {
        function pin() {
            var head = document.head || document.getElementsByTagName('head')[0];
            if (!head) { return; }
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no';
            head.appendChild(meta);
        }
        if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', pin); } else { pin(); }
    })();
    """

    /** Viewability bridge shim (bridge-contract §4.1) — iOS source verbatim. */
    const val VIEWABILITY_SHIM = """
    window.stepnetwork = window.stepnetwork || {};
    (function () {
        if (window.stepnetwork._onViewability) { return; }
        var listeners = [];
        window.stepnetwork.viewability = {
            ratio: 0, visible: false, viewable: false,
            dwellMs: 0, thresholdMs: 0, mode: 'display', appActive: true
        };
        window.stepnetwork.onViewability = function (cb) {
            if (typeof cb === 'function') { listeners.push(cb); }
        };
        window.stepnetwork._onViewability = function (p) {
            window.stepnetwork.viewability = p;
            try {
                window.dispatchEvent(new CustomEvent('snviewability', { detail: p }));
            } catch (e) {}
            for (var i = 0; i < listeners.length; i++) {
                try { listeners[i](p); } catch (e) {}
            }
        };
    })();
    """

    /** GPT Active View verdict → native (bridge-contract §2.3) — iOS source verbatim. */
    const val IMPRESSION_VIEWABLE_LISTENER = """
    (function () {
        window.googletag = window.googletag || {};
        googletag.cmd = googletag.cmd || [];
        googletag.cmd.push(function () {
            googletag.pubads().addEventListener('impressionViewable', function (event) {
                try {
                    window.webkit.messageHandlers.nativeBridge.postMessage({
                        type: 'impressionViewable',
                        slotId: event.slot.getSlotElementId(),
                        ts: Date.now()
                    });
                } catch (e) {}
            });
        });
    })();
    """

    /** Ad unit id injection — JSON-quoted (iOS interpolates raw; do not copy that). */
    fun adUnitId(adUnitId: String): String {
        val quoted = JSONObject.quote(adUnitId).replace("</", "<\\/")
        return """
        window.stepnetwork = window.stepnetwork || {}; window.stepnetwork.adUnitId = $quoted;
        console.log('Injected adUnitId to JS, value: ' + window.stepnetwork.adUnitId);
        """.trimIndent()
    }

    /** Lazy-load manual render trigger (bridge-contract §3.1) — iOS source, id JSON-quoted. */
    fun triggerAdRendering(adUnitId: String): String {
        val quoted = JSONObject.quote(adUnitId).replace("</", "<\\/")
        return """
        if (typeof window.triggerManualAdEvent === 'function') {
            window.triggerManualAdEvent();
        } else {
            window.ayManagerEnv = window.ayManagerEnv || { cmd: [] };
            window.ayManagerEnv.cmd.push(function() {
                if (window.ayManagerEnv && typeof ayManagerEnv.dispatchManualEvent === 'function') {
                    ayManagerEnv.dispatchManualEvent();
                    console.log('[LLM] Triggered manual ad render event (fallback) for unit: ' + $quoted);
                } else {
                    console.log('[LLM] ayManagerEnv.dispatchManualEvent not available (fallback) for unit: ' + $quoted);
                }
            });
        }
        """.trimIndent()
    }

    /** Remote lazy-load read-back (bridge-contract §3.2) — constant, nothing interpolated. */
    const val REMOTE_LAZY_LOAD_POLL = """
    (function () {
        var c = window.stepnetwork && window.stepnetwork.lazyLoad;
        return c ? JSON.stringify(c) : null;
    })()
    """

    /** Debug only: console bridge, debug panel, viewport probe, GPT visibility diagnostics. */
    const val DEBUG_BUNDLE = """
    (function () {
        function run() {
            var debugInfo = document.createElement('div');
            debugInfo.id = 'debugInfo';
            debugInfo.className = 'debug-info';
            var adUnitDiv = document.createElement('div');
            adUnitDiv.id = 'adUnitInfo';
            adUnitDiv.textContent = 'Ad unit: ' + (window.stepnetwork && window.stepnetwork.adUnitId ? window.stepnetwork.adUnitId : '(not set)');
            debugInfo.appendChild(adUnitDiv);
            var adSizeDiv = document.createElement('div');
            adSizeDiv.id = 'adSizeInfo';
            adSizeDiv.textContent = 'Size: (not sent)';
            debugInfo.appendChild(adSizeDiv);
            var googleButton = document.createElement('div');
            googleButton.id = 'GoogleButton';
            var button = document.createElement('a');
            button.href = '#';
            button.id = 'bookmarklet-button';
            button.textContent = 'Console';
            button.addEventListener('click', function (event) {
                event.preventDefault();
                if (window.googletag && typeof googletag.openConsole === 'function') {
                    googletag.openConsole();
                } else {
                    console.log('Google Publisher Console is not available.');
                }
            });
            googleButton.appendChild(button);
            debugInfo.appendChild(googleButton);
            if (document.body) { document.body.appendChild(debugInfo); }
            var origSendAdSizeToNative = window.sendAdSizeToNative;
            window.sendAdSizeToNative = function (width, height) {
                adSizeDiv.textContent = 'Size: ' + width + ' x ' + height;
                if (typeof origSendAdSizeToNative === 'function') { origSendAdSizeToNative(width, height); }
            };
        }
        if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', run); } else { run(); }
    })();

    (function () {
        var methods = ['log', 'info', 'warn', 'error', 'debug'];
        methods.forEach(function (level) {
            var original = console[level];
            console[level] = function () {
                var args = Array.prototype.slice.call(arguments);
                if (typeof args[0] === 'string' && args[0].includes('%c')) {
                    args[0] = args[0].replace(/%c/g, '').trim();
                    args.splice(1, 1);
                }
                var message = args.map(function (arg) {
                    if (typeof arg === 'object' && arg !== null) {
                        try { return JSON.stringify(arg, null, 2); } catch (e) { return '[Object]'; }
                    }
                    return String(arg);
                }).join(' - ');
                try {
                    window.webkit.messageHandlers.nativeBridge.postMessage({ type: 'console', level: level, message: message });
                } catch (e) {}
                if (original) original.apply(console, arguments);
            };
        });
    })();

    window.googletag = window.googletag || {};
    googletag.cmd = googletag.cmd || [];
    googletag.cmd.push(function () {
        googletag.pubads().setTargeting('yb_target', 'alwayson-standard');
    });

    (function () {
        var snClipProbeTimer;
        window.addEventListener('resize', function () {
            clearTimeout(snClipProbeTimer);
            snClipProbeTimer = setTimeout(function () {
                console.log('[CLIP] DOM viewport now ' + window.innerWidth + 'x' + window.innerHeight);
            }, 150);
        });
    })();

    (function () {
        window.googletag = window.googletag || {};
        googletag.cmd = googletag.cmd || [];
        googletag.cmd.push(function () {
            var lastPercent = -1;
            googletag.pubads().addEventListener('slotVisibilityChanged', function (event) {
                if (event.inViewPercentage === lastPercent) { return; }
                lastPercent = event.inViewPercentage;
                try {
                    window.webkit.messageHandlers.nativeBridge.postMessage({
                        type: 'slotVisibilityChanged',
                        slotId: event.slot.getSlotElementId(),
                        visiblePercent: event.inViewPercentage,
                        ts: Date.now()
                    });
                } catch (e) {}
            });
        });
    })();
    """
}
