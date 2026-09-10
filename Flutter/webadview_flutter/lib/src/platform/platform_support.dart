import 'package:flutter/foundation.dart';

import '../logging.dart';

/// Which platforms have a native implementation (iOS and Android). On web
/// and desktop the widgets render placeholders so a single-codebase app
/// keeps running.
class PlatformSupport {
  PlatformSupport._();

  static const Set<TargetPlatform> _implemented = <TargetPlatform>{
    TargetPlatform.iOS,
    TargetPlatform.android,
  };

  static bool _missingPlugin = false;

  /// Test seam: pretend to run on this platform (widget tests must not
  /// change `debugDefaultTargetPlatformOverride` across frames).
  @visibleForTesting
  static TargetPlatform? debugPlatformOverride;

  static TargetPlatform get _platform =>
      debugPlatformOverride ?? defaultTargetPlatform;

  /// `true` when the running platform has a native implementation and the
  /// plugin was registered by the host app.
  static bool get isSupported =>
      !kIsWeb && !_missingPlugin && _implemented.contains(_platform);

  /// Called when a channel call throws `MissingPluginException`: the native
  /// half is absent (e.g. plugin not registered). Latches [isSupported] off.
  static void markPluginMissing() {
    if (_missingPlugin) return;
    _missingPlugin = true;
    SnLog.errorOnce('missing_plugin',
        'webadview_flutter: native plugin not found on $defaultTargetPlatform — ads will not load.');
  }

  /// Logged once when the API is used on a platform without an
  /// implementation (web, desktop).
  static void noteUnsupported() {
    SnLog.errorOnce('unsupported_platform',
        'webadview_flutter: no native implementation for $defaultTargetPlatform — WebAdView renders empty placeholders.');
  }

  @visibleForTesting
  static void resetForTesting() {
    _missingPlugin = false;
    debugPlatformOverride = null;
  }
}
