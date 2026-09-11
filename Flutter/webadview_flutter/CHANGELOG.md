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
