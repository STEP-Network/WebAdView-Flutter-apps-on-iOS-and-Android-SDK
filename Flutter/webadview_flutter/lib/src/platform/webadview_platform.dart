import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../model/ad_load_state.dart';
import '../model/lazy_load_config.dart';
import '../model/viewability.dart';
import '../sdk/webadview_sdk_config.dart';
import 'method_channel_webadview.dart';

/// Geometry for one ad: the whole ad frame (label included, drives lazy
/// loading) and the creative-only frame (drives viewability). Global
/// coordinates in logical pixels.
@immutable
class AdGeometry {
  const AdGeometry({required this.frame, required this.creative});
  final Rect frame;
  final Rect creative;

  @override
  bool operator ==(Object other) =>
      other is AdGeometry && other.frame == frame && other.creative == creative;

  @override
  int get hashCode => Object.hash(frame, creative);
}

/// Result of `initialize`.
@immutable
class InitializeResult {
  const InitializeResult({required this.alreadyInitialized, this.error});
  final bool alreadyInitialized;

  /// Set when the native side rejected the configuration (for example
  /// `activity_not_fragment` on Android); the SDK is then NOT initialized.
  final String? error;
}

/// The platform contract. One implementation per platform channel; tests
/// inject a fake through [instance]. Kept as an abstract class so the
/// package can later split into a `platform_interface` without changing the
/// app-facing API.
abstract class WebAdViewPlatform {
  static WebAdViewPlatform _instance = MethodChannelWebAdView();

  static WebAdViewPlatform get instance => _instance;

  @visibleForTesting
  static set instance(WebAdViewPlatform value) {
    _instance = value;
  }

  /// Receives native → Dart events. Set by the scope registry.
  WebAdViewPlatformListener? listener;

  Future<InitializeResult> initialize(WebAdViewSdkConfig config);
  Future<void> showConsentPreferences();
  Future<void> setDebugEnabled(bool enabled);
  Future<bool> isDebugEnabled();
  Future<void> acceptAllConsentForTesting();

  Future<void> createScope(String scopeId, LazyLoadConfig config);
  Future<void> disposeScope(String scopeId);
  Future<void> setScopeVisible(String scopeId, bool visible);
  Future<void> registerAd(String scopeId, String adUnitId);
  Future<void> unregisterAd(String scopeId, String adUnitId);
  Future<void> updateGeometry(
      String scopeId, Rect viewport, Map<String, AdGeometry> ads);
}

/// Native → Dart events, routed by the scope registry to the right widget.
abstract class WebAdViewPlatformListener {
  void onLoadState(String scopeId, String adUnitId, AdLoadState state);
  void onViewability(String scopeId, ViewabilityUpdate update);
}
