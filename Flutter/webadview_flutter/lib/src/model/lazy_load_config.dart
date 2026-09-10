import 'package:flutter/foundation.dart';

/// Starting values for scroll-based lazy loading (mirrors the SDK's
/// `LazyLoadingConfig`). Distances are logical pixels from the scroll
/// viewport's edges.
///
/// **STEP Network's remote per-domain values override [fetchThreshold] and
/// [displayThreshold]** once the SDK has read them from a loaded ad page
/// (cached between launches), exactly as in the native SDK — those two are
/// only starting values. [unloadThreshold] and [unloadingEnabled] are the
/// app's own decision and are never overridden remotely.
@immutable
class LazyLoadConfig {
  const LazyLoadConfig({
    this.fetchThreshold = 800,
    this.displayThreshold = 200,
    this.unloadThreshold = 1600,
    this.unloadingEnabled = false,
  });

  /// Distance at which an ad starts fetching its page. Default 800.
  final double fetchThreshold;

  /// Distance at which the creative is asked to render. Default 200.
  final double displayThreshold;

  /// Distance beyond which an ad may be torn down (with [unloadingEnabled]).
  /// Default 1600 (hysteresis against [fetchThreshold]).
  final double unloadThreshold;

  /// Whether far-away ads are unloaded to save memory. Default `false`
  /// (UX over memory; each re-entry would be a new ad request).
  final bool unloadingEnabled;

  Map<String, Object?> toChannelMap() => <String, Object?>{
        'fetchThreshold': fetchThreshold,
        'displayThreshold': displayThreshold,
        'unloadThreshold': unloadThreshold,
        'unloadingEnabled': unloadingEnabled,
      };

  @override
  bool operator ==(Object other) =>
      other is LazyLoadConfig &&
      other.fetchThreshold == fetchThreshold &&
      other.displayThreshold == displayThreshold &&
      other.unloadThreshold == unloadThreshold &&
      other.unloadingEnabled == unloadingEnabled;

  @override
  int get hashCode => Object.hash(
      fetchThreshold, displayThreshold, unloadThreshold, unloadingEnabled);
}
