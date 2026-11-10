## 0.1.2 — 2026-11-10

Scroll performance in long lists (a publisher reported heavy jank on an
iPhone 16e and some on a Samsung S26 Ultra with ads in a long list).

- **Ads survive widget disposal.** A `WebAdView` that a builder list
  (`ListView.builder`, slivers) disposes when it scrolls out of the cache
  extent keeps its native webview, load state and impression (up to four
  per `LazyLoadAdScope`, oldest unloaded first). When the row comes back the
  same ad re-attaches: no new webview, no page load, no new ad request.
  Before, every return created a webview on the main thread mid-scroll and
  ran a full ad auction — measured 11 webview creations and page loads for
  3 ads in one scroll script, now 3. Everything is released when the scope
  goes away (route popped) or when lazy-load unloading tears an ad down.
- **One native evaluation per frame** instead of one per ad: the geometry
  batch Dart sends every frame now runs each state machine exactly once.
- **No native → Dart viewability traffic unless you listen.** Without an
  `onViewabilityChange` callback nothing is sent; with one, updates are
  rate-limited to at most 15 per second per ad (the first update, every
  transition and `becameViewable` arrive immediately, ratio/dwell-only
  changes are coalesced). Before, every evaluation of every rendered ad was
  sent synchronously — up to 9 channel calls per frame with three ads.
- **Viewport resizing is paced**: at most 10 webview resizes per second per
  ad while scrolling (regime changes full/partial/hidden still apply
  immediately, the exact final slice lands within 100 ms of the scroll
  settling) instead of one per frame while an ad crosses the screen edge.
- iOS: one shared `WKProcessPool` for all ad webviews; the key window is
  cached instead of walked per evaluation. Android: no per-evaluation list
  copies.
- Debug-only `[SN] [PERF]` counters (one line per second while the debug
  flag is on: evaluations, resizes, JS sends, geometry batches with handler
  time, viewability calls, webview creations) and a scroll-performance
  harness in the example app (`--dart-define=SN_PERF=true`, README §8).
- Swift SDK 1.1.2 carries the native half (batch geometry entry point
  `WebAdScope.updateGeometry`, `detach`, `WebAdHostView.lastAdSize`, the
  rate-limited `viewabilityUpdates(for:)` host stream, clip cadence, shared
  process pool, `PerfCounters`).

## 0.1.1 — 2026-09-11

- Native viewability only starts counting once the creative has rendered
  (the page's `adSize` message). Before, the slot could latch a "viewable"
  against the empty box while the page was still loading, so
  `onViewabilityChange` could report `becameViewable` before any ad existed
  and again after the load. Google Active View was never affected. Both
  platforms; the Swift SDK ships the same fix as 1.1.1.

## 0.1.0 — 2026-09-10

Initial release of `webadview_flutter`: STEP Network web ads for Flutter
apps on iOS 16+ and Android 7+ (API 24), Flutter 3.44+ / Dart 3.13+.

- Dart API mirroring the SwiftUI SDK: `WebAdViewSdk.initialize` with the
  three consent modes (`WebAdViewSdkConfig.didomi` / `.tcf` / `.appDidomi`),
  `LazyLoadAdScope` (required around each scrollable; `viewportInsets`,
  `recommendedCacheExtent` for builder lists, `LazyLoadConfig` starting
  thresholds and unloading), `WebAdView` with custom targeting, ad label,
  size constraints, `viewportResizing` (honest Active View, on by default),
  `onViewabilityChange` and `onActiveViewImpression`, and the persisted
  debug switch (`setDebugEnabled`).
- iOS: platform views hosting the WebAdView Swift SDK (built from the same
  repository); Dart-driven geometry feeds the SDK's unchanged lazy-load and
  viewability engines. Swift Package Manager only.
- Android: Kotlin port of the SDK — document-start bridge shim for the STEP
  template, origin-restricted `nativeBridge`, Didomi Android, TCF
  SharedPreferences, viewport resizing with the page scale pinned to 1,
  consumer ProGuard rules. `MainActivity` must extend
  `FlutterFragmentActivity`.
- Own-CMP modes hand the page a standard `__tcfapi` object with the decoded
  TCData purpose/vendor maps (byte-identical JavaScript on both platforms).
- A rejected native configuration (for example `activity_not_fragment`)
  leaves the SDK uninitialized and prints an un-gated `[SN] [ERROR]`.
- Example app (NewsHub) with `SN_CONSENT_MODE=didomi|tcf|appDidomi`, a
  simulated TCF consent platform for mode 3, and end-to-end integration
  tests for all three modes on iOS and Android.
