/// STEP Network WebAdView for Flutter.
///
/// Privacy-compliant web ads: Didomi consent gating, scroll-based lazy
/// loading, and native IAB/MRC viewability measurement, rendered by the
/// native WebAdView SDK on iOS and its Kotlin port on Android.
///
/// Integration in three steps (see README.md for the full guide):
///
/// 1. `await WebAdViewSdk.initialize(WebAdViewSdkConfig.didomi(...))` before
///    `runApp`.
/// 2. Wrap the scrollable that holds your ads in a [LazyLoadAdScope]
///    (required — it drives loading and measurement, like `.lazyLoadAd()`
///    in the SwiftUI SDK).
/// 3. Place [WebAdView] widgets in that scrollable.
library;

// Lazy-load states are internal to the SDK; observe them through the
// `[SN] [LLM]` debug log, not through the widget API.
export 'src/model/ad_load_state.dart';
export 'src/model/lazy_load_config.dart';
export 'src/model/viewability.dart';
// Advanced / testing only: the platform seam and the platform-view params.
export 'src/platform/webadview_platform.dart' show WebAdViewPlatform;
export 'src/scope/lazy_load_ad_scope.dart' show LazyLoadAdScope;
export 'src/sdk/webadview_sdk.dart';
export 'src/sdk/webadview_sdk_config.dart';
export 'src/widgets/native_ad_view.dart' show NativeAdViewParams;
export 'src/widgets/web_ad_view.dart' show WebAdView;
