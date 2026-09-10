import 'package:flutter/foundation.dart';

import '../logging.dart';
import '../platform/platform_support.dart';
import '../platform/webadview_platform.dart';
import 'webadview_sdk_config.dart';

/// SDK entry point. Call [initialize] once before `runApp` (after
/// `WidgetsFlutterBinding.ensureInitialized()`), before any [WebAdView]
/// exists.
abstract final class WebAdViewSdk {
  static bool _initialized = false;

  /// Whether the native SDK has been configured in this process.
  static bool get isInitialized => _initialized;

  /// Whether the running platform has a native implementation (iOS and
  /// Android). `false` on web and desktop — the widgets then render empty
  /// placeholders and nothing is sent to Google.
  static bool get isSupported => PlatformSupport.isSupported;

  /// Configures the native SDK. Never throws: on unsupported platforms it
  /// logs once and completes. Calling it a second time (or after a hot
  /// restart, when the native side is already configured) is harmless — the
  /// first configuration wins, as in the native SDK.
  static Future<void> initialize(WebAdViewSdkConfig config) async {
    if (!PlatformSupport.isSupported) {
      PlatformSupport.noteUnsupported();
      return;
    }
    if (_initialized) {
      SnLog.log('initialize called more than once — ignoring');
      return;
    }
    final result = await WebAdViewPlatform.instance.initialize(config);
    if (!PlatformSupport.isSupported) return; // plugin turned out missing
    if (result.error != null) {
      // Sanctioned un-gated error: a rejected configuration must never be
      // silent, and the SDK must not pretend to be initialized.
      SnLog.errorOnce('initialize_failed',
          'WebAdViewSdk.initialize was rejected by the native SDK (${result.error}) — ads will not load. See the plugin README (§1, §10).');
      return;
    }
    _initialized = true;
    if (result.alreadyInitialized) {
      SnLog.log('native SDK already initialized (hot restart) — reusing its configuration');
    }
    SnLog.isEnabled = await WebAdViewPlatform.instance.isDebugEnabled();
  }

  /// Opens the consent preferences UI (standard mode). With an app-owned
  /// CMP this is a logged no-op — open that CMP's UI from your app instead
  /// (except `appDidomi`, which opens your Didomi preferences).
  static Future<void> showConsentPreferences() async {
    if (!PlatformSupport.isSupported) return;
    await WebAdViewPlatform.instance.showConsentPreferences();
  }

  /// Runtime debug switch (persisted natively). Enables `[SN]` logging on
  /// both sides, the in-ad debug panel and Yield Manager debug mode. Off by
  /// default, so release builds are clean.
  static Future<void> setDebugEnabled(bool enabled) async {
    SnLog.isEnabled = enabled;
    if (!PlatformSupport.isSupported) return;
    await WebAdViewPlatform.instance.setDebugEnabled(enabled);
  }

  static Future<bool> isDebugEnabled() async {
    if (!PlatformSupport.isSupported) return SnLog.isEnabled;
    final enabled = await WebAdViewPlatform.instance.isDebugEnabled();
    SnLog.isEnabled = enabled;
    return enabled;
  }

  /// TEST AUTOMATION ONLY — grants full consent through the official Didomi
  /// API so automated simulator runs are not held back by the notice. Debug
  /// builds only; a no-op in release. Consent must come from the user in
  /// production.
  static Future<void> acceptAllConsentForTesting() async {
    if (!kDebugMode || !PlatformSupport.isSupported) return;
    await WebAdViewPlatform.instance.acceptAllConsentForTesting();
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
  }
}
