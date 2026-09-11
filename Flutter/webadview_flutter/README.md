# webadview_flutter — STEP Network WebAdView for Flutter

Privacy-compliant web ads for Flutter apps: Didomi consent gating,
scroll-based lazy loading, Google Ad Manager delivery through STEP Network's
Yield Manager, and true IAB/MRC viewability measurement — rendered by the
native **WebAdView SDK** underneath one Dart API.

- **iOS:** wraps the WebAdView iOS SDK (this repository). iOS 16+.
- **Android:** a Kotlin port of the same SDK (`android/`), built to
  `Documentation/bridge-contract.md`. minSdk 24; Didomi Android 2.49.1 and
  `androidx.webkit` are pulled automatically.
- **Flutter:** ≥ 3.44, Dart ≥ 3.13. iOS builds use **Swift Package Manager
  only** (Flutter's default since 3.44); CocoaPods is not supported.
- **Web / desktop:** `WebAdView` renders an empty placeholder and logs once.

This guide mirrors the SwiftUI [GUIDE.md](../../GUIDE.md) section by
section, so everything STEP Network has told you about the native SDK
applies unchanged. The ad template, ad unit ids, targeting keys and Didomi
key come from your STEP Network onboarding exactly as before.

## 1. Install

The plugin lives in the `Flutter/webadview_flutter` folder of the SDK
repository (which also carries the Swift SDK the plugin builds from source
on iOS). It is not on pub.dev; depend on it as a Git dependency with the
version STEP Network gives you at onboarding:

```yaml
dependencies:
  webadview_flutter:
    git:
      url: https://github.com/STEP-Network/WebAdView-Flutter-apps-on-iOS-and-Android-SDK.git
      path: Flutter/webadview_flutter
      ref: v0.1.1
```

Or from a local clone of the **whole repository** (the plugin's Swift
package needs the repository root's `Package.swift`):

```bash
git clone https://github.com/STEP-Network/WebAdView-Flutter-apps-on-iOS-and-Android-SDK.git
```

```yaml
dependencies:
  webadview_flutter:
    path: ../WebAdView-Flutter-apps-on-iOS-and-Android-SDK/Flutter/webadview_flutter
```

The plugin's Swift package resolves the WebAdView iOS SDK from the same
checkout automatically (the repository root, four levels above the plugin's
`Package.swift`). If your layout differs, point `WEBADVIEW_SDK_PATH` at the
SDK root when building —
`WEBADVIEW_SDK_PATH=/abs/path/to/the-repo flutter build ios` — it is an
environment variable read by the SwiftPM manifest, so a build started from
the Xcode UI only sees it if you add it to the scheme's environment.

**iOS deployment target: 16.0.** Open `ios/Runner.xcodeproj` and set
*Minimum Deployments* to iOS 16 (the Flutter template defaults to 13; Swift
Package Manager refuses a dependency with a higher minimum). Nothing else
changes in your Xcode project — the plugin registers itself.

**Android: `MainActivity` must extend `FlutterFragmentActivity`.** Didomi's
consent notice and preferences need a `FragmentActivity` host (the same
change Didomi's own Flutter plugin requires):

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

Otherwise, in standard (Didomi) mode, the native side rejects `initialize`
with `activity_not_fragment`: the SDK stays uninitialized
(`WebAdViewSdk.isInitialized` is `false`), prints an un-gated
`[SN] [ERROR] WebAdViewSdk.initialize was rejected by the native SDK
(activity_not_fragment …)` line, and ads never load. minSdk 24; nothing
else changes in your Gradle setup. **Release builds** need nothing extra:
the plugin merges the `INTERNET` permission and ships consumer ProGuard/R8
rules for its WebView bridge.

## 2. Initialize at app launch

Call once, before `runApp`, before any `WebAdView` exists:

```dart
import 'package:flutter/material.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WebAdViewSdk.initialize(WebAdViewSdkConfig.didomi(
    apiKey: const String.fromEnvironment('SN_DIDOMI_API_KEY'),        // required
    adTemplateUrl: Uri.parse('https://your-domain/ad-template.html'), // required — your template page, on your domain
  ));
  runApp(const MyApp());
}
```

- **`apiKey`** — your Didomi API key. Don't commit real keys; inject them
  (`--dart-define`, CI secrets).
- **`adTemplateUrl`** — the page every ad webview loads, hosted on your own
  domain, built to `Documentation/bridge-contract.md`. The SDK appends
  `didomi-disable-notice=true` itself if missing.
- `initialize` never throws. On a platform without a native implementation
  it logs once and does nothing; `WebAdViewSdk.isSupported` tells you.
- Calling it twice (or after a hot restart) is harmless — the first
  configuration wins.

### Your app already has a consent system (CMP)?

```dart
await WebAdViewSdk.initialize(WebAdViewSdkConfig.tcf(          // any TCF-certified CMP
  adTemplateUrl: Uri.parse('https://your-domain/ad-template.html'),
));
```

Use `WebAdViewSdkConfig.appDidomi(...)` if your app runs its own Didomi —
for example through the `didomi_sdk` Flutter plugin, which your app then
adds to its own `pubspec.yaml` and initialises itself. Both plugins resolve
the same Didomi Swift package (and the same Android artifact), so one Didomi
binary is linked (verified with `didomi_sdk` 2.33.x). The rules in GUIDE.md §3b apply unchanged: your CMP shows
the notice, your ad template must contain no consent code of its own, and
the pre-launch check for non-Didomi CMPs is still required.

Both modes are verified end to end on iOS and Android by
`example/integration_test/tcf_mode_test.dart` and
`app_didomi_mode_test.dart` (no ad request without an answer, load on the
answer, reload when the answer changes) — see §9.

## 3. Consent UI (standard mode)

Nothing to add: the plugin presents Didomi's notice from the Flutter view
controller on first launch. Offer a way to reopen preferences:

```dart
TextButton(
  onPressed: WebAdViewSdk.showConsentPreferences,
  child: const Text('Privacy Settings'),
)
```

Until the user has answered the notice, the SDK makes no ad requests — the
ad slots stay empty. Consent changes reload ads automatically.

## 4. Show ads

```dart
LazyLoadAdScope(                       // ← REQUIRED around the scrollable
  child: SingleChildScrollView(
    child: Column(children: [
      const WebAdView(adUnitId: 'div-gpt-ad-mobile_1', showAdLabel: true),
      // …content…
      const WebAdView(adUnitId: 'div-gpt-ad-mobile_2', showAdLabel: true),
    ]),
  ),
)
```

> **`LazyLoadAdScope` is required, not optional** — it is the Flutter
> equivalent of `.lazyLoadAd()` and installs the loading and viewability
> machinery. Without it a `WebAdView` throws in debug builds and stays
> blank in release. One scope per screen, placed inside `Scaffold.body`
> (so the `AppBar` is excluded from the measured viewport).

**⚠️ Ad unit ids, sizes and formats are configured remotely by STEP
Network's Yield Manager.** Local sizes are UI-layout only.

### Sizing (UI-layout only)

```dart
WebAdView(
  adUnitId: 'div-gpt-ad-mobile_3',
  initialWidth: 320, initialHeight: 320,   // placeholder while loading
  maxHeight: 600,                          // constraint (can clip — prefer none)
)
```

The box resizes to the delivered creative (animated, 200 ms). Center it or
stretch it with your own layout widgets, as you would `.frame(maxWidth:
.infinity)`. `minWidth` / `maxWidth` / `minHeight` exist alongside
`maxHeight`.

### The ad label

`showAdLabel: true` draws a small centred label above the creative. Its
text defaults to `'annonce'` (Danish for "ad") — set `adLabelText` to your
own wording and `adLabelStyle` for the typography:

```dart
WebAdView(adUnitId: 'div-gpt-ad-mobile_1', showAdLabel: true, adLabelText: 'Advertisement')
```

### Force a reload

Give the widget a new `key` (`WebAdView(key: ValueKey(adKey), …)`) — the
`.id(adKey)` pattern from the SwiftUI guide.

## 5. Lazy loading

```dart
LazyLoadAdScope(config: const LazyLoadConfig(unloadingEnabled: true), child: …)
LazyLoadAdScope(config: const LazyLoadConfig(fetchThreshold: 1000, displayThreshold: 300), child: …)
```

States per ad: `notLoaded → fetched` (page loads) `→ displayed` (creative
renders); with unloading enabled, far-away ads are torn down after 2 s and
recreated on re-entry. The states are internal — you see them in the
`[SN] [LLM]` debug log, not through the widget API. **STEP Network's remote
per-domain distances override `fetchThreshold` and `displayThreshold`** (as
percentages of the viewport, as in the native SDK); `unloadThreshold` and
`unloadingEnabled` are yours and are never overridden remotely.

### `ListView.builder`, `CustomScrollView` and other builder lists

Builder-based lists only build items about 250 logical pixels ahead of the
viewport, which defeats the fetch-ahead distance. Set

```dart
ListView.builder(
  scrollCacheExtent: LazyLoadAdScope.recommendedCacheExtent(context),
  …
)
```

and note that items the builder disposes are **new impressions and new ad
requests** when they come back — the same behaviour as `List` in the
SwiftUI SDK. `SingleChildScrollView` + `Column` behaves like `ScrollView`:
ads live until unloading. The heuristic cannot see STEP's remote values: if
STEP Network configures a fetch distance above 150 % of the viewport for
your domain, pass a correspondingly larger `scrollCacheExtent`.

If an overlay is drawn *inside* the scope's bounds (a pinned
`SliverAppBar`), exclude it from the measured viewport:

```dart
LazyLoadAdScope(viewportInsets: const EdgeInsets.only(top: 56), child: …)
```

## 6. Custom targeting

```dart
WebAdView(
  adUnitId: 'div-gpt-ad-mobile_1',
  customTargeting: const {
    'section': ['homepage'],
    'tags': ['breaking', 'featured'],
  },
)
```

Keys must be configured by STEP Network in Google Ad Manager first.

## 7. Viewability (IAB/MRC)

```dart
WebAdView(
  adUnitId: 'div-gpt-ad-mobile_1',
  onViewabilityChange: (update) {
    if (update.becameViewable) {
      // fires exactly once per impression: ≥50 % on screen for 1 s continuous
    }
  },
  onActiveViewImpression: (slotId) {
    // Google Active View counted a viewable impression for this slot
  },
)
```

`onViewabilityChange` fires up to once per frame while scrolling and ten
times per second while the in-view timer runs; react to `becameViewable`
rather than calling `setState` per update. Nothing fires before the
creative has rendered — an empty or still-loading slot never counts — and
every page load starts a fresh impression. Viewport resizing (honest
Active View measurement) is on by default; `viewportResizing: false` opts a
single ad out, only in coordination with STEP Network. A screen covered by
another route stops measuring automatically.

## 8. Debug output

```dart
await WebAdViewSdk.setDebugEnabled(true);   // persisted; off by default
```

Then watch the console:

```bash
xcrun simctl launch --console-pty booted <your-bundle-id> | grep --line-buffered '\[SN\]'   # iOS
adb logcat -s SN                                                                          # Android
```

`[SN] [VIEWABILITY]`, `[SN] [LLM]`, `[SN] [CLIP]` and `[SN] [FLUTTER]`
lines show measurement, lazy-load transitions, viewport resizing and the
Flutter bridge. The example app's ladybug button toggles the flag.

## 9. Run the example

```bash
cd Flutter/webadview_flutter/example
flutter run -d "iPhone 17" --dart-define=SN_CONSENT_ACCEPT_ALL=true      # iOS simulator
flutter run -d emulator-5554 --dart-define=SN_CONSENT_ACCEPT_ALL=true    # Android emulator
flutter test integration_test/smoke_test.dart -d <device>                # end-to-end: latch + Active View
```

The `SN_CONSENT_ACCEPT_ALL` define grants consent programmatically in debug
builds so automated runs are not held back by the notice; without it the
Didomi notice appears on first launch. The example runs against STEP
Network's demo Didomi key and test template (`lib/config.dart`) — test
values only, never for a real app.

> The example's `ios/Runner/Info.plist` carries `NSAllowsLocalNetworking`
> so the demo can load a template served from your Mac (below). That plist
> is used by every build configuration — don't copy it into a real app.

### The three consent modes in the example

`SN_CONSENT_MODE` switches the demo between the modes of §2:

```bash
flutter run -d <device> --dart-define=SN_CONSENT_MODE=tcf         # mode 3: own TCF CMP
flutter run -d <device> --dart-define=SN_CONSENT_MODE=appDidomi   # mode 2: app-owned Didomi (didomi_sdk)
```

- **`tcf`** shows a *Simulated consent platform* card at the bottom of the
  home screen. It plays the role of your own TCF CMP: Accept / Decline
  write real TC strings to the standard `IABTCF_*` keys through a tiny
  native channel in the example (`ios/Runner/AppDelegate.swift`,
  `android/.../MainActivity.kt`); the SDK only reads them, exactly as it
  would for Cookiebot, OneTrust or Usercentrics. Watch the ads wait, load
  and reload.
- **`appDidomi`** initialises Didomi in the app through the `didomi_sdk`
  plugin and hands the SDK `WebAdViewSdkConfig.appDidomi(...)`.

**Own-CMP modes need an own-CMP template.** The hosted demo template is the
standard-mode page and loads Didomi's web tag, which would override the
SDK's `__tcfapi` hand-off. For modes 2 and 3 serve the reference own-CMP
template from this repository and point the demo at it (the example allows
plain http to the host: `NSAllowsLocalNetworking` in its Info.plist on iOS,
`usesCleartextTraffic` in the debug manifest on Android). Keep the server
running for the whole session, and re-run `adb reverse` after restarting
the emulator:

```bash
(cd Documentation && python3 -m http.server 8787 --bind 127.0.0.1 &)   # from the repository root
adb reverse tcp:8787 tcp:8787                                          # Android emulator only
T=http://127.0.0.1:8787/example-ad-template-own-cmp.html
flutter run -d <device> --dart-define=SN_CONSENT_MODE=tcf --dart-define=SN_AD_TEMPLATE_URL=$T
```

The matching end-to-end tests run on either device with the same
`SN_AD_TEMPLATE_URL` define (they select the consent mode themselves, so
`SN_CONSENT_MODE` is not needed):

```bash
flutter test integration_test/tcf_mode_test.dart -d <device> --dart-define=SN_AD_TEMPLATE_URL=$T
flutter test integration_test/app_didomi_mode_test.dart -d <device> --dart-define=SN_AD_TEMPLATE_URL=$T
```

## 10. Troubleshooting

| Symptom | Check |
|---|---|
| `WebAdView … has no LazyLoadAdScope ancestor` | Wrap the scrollable in `LazyLoadAdScope` (§4). |
| Ads never load | `initialize` called before `runApp`? Consent answered? Deployment target 16? |
| `[SN] [ERROR] … rejected by the native SDK (activity_not_fragment …)` on Android, `isInitialized` false | `MainActivity` must extend `FlutterFragmentActivity` (§1). |
| Ads never render on Android, `adSize` never arrives | The plugin installs a document-start shim for the template's `window.webkit.messageHandlers.nativeBridge`; with debug on (§8) check `adb logcat -s SN` for `document-start scripts unsupported` (very old WebView). |
| Ads never fetch early in a builder list | `cacheExtent: LazyLoadAdScope.recommendedCacheExtent(context)` (§5). |
| Ads under a pinned header count as visible | `viewportInsets` on the scope (§5). |
| Taps don't open ads | Don't wrap `WebAdView` in a `GestureDetector` that claims taps; vertical drags stay with the list by design. |
| Build error mentioning `WebAdViewSDK` path | The checkout must be the whole repository; otherwise set `WEBADVIEW_SDK_PATH=/absolute/path/to/the-repo` (§1) or reset SwiftPM caches (`rm -rf ~/Library/Caches/org.swift.swiftpm/manifests`). |
| Two Didomi copies warning `[SN] [ERROR]` | Install Didomi through Swift Package Manager only (no CocoaPods CMP plugin). |

## Development (this repository)

```bash
cd Flutter/webadview_flutter
flutter analyze && flutter test                                          # Dart unit + widget tests
cd example && flutter build ios --simulator --debug                      # iOS native build incl. the SDK
flutter build apk --debug                                                # Android native build
(cd example/android && ./gradlew :webadview_flutter:testDebugUnitTest)   # Kotlin JVM tests (ports of the Swift core tests)
```

The native contract (`Documentation/bridge-contract.md`) and the geometry
protocol (Dart sends viewport + ad rects; native runs the state machines)
are shared by the iOS and Android implementations.
