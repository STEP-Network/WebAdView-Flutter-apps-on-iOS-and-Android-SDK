import 'package:flutter/foundation.dart';

/// IAB/MRC threshold profile an impression is measured against. Every ad
/// the SDK measures uses [display] (≥50 % of pixels for 1 s continuous);
/// [video] (2 s) is reserved and only ever observed via
/// [ViewabilityUpdate.mode].
enum ViewabilityMode {
  display,
  video;

  /// Fraction of the ad's pixels that must be on screen (IAB/MRC: 50 %).
  double get requiredRatio => 0.5;

  /// Continuous seconds in view required for a viewable impression.
  double get requiredDuration => this == video ? 2.0 : 1.0;

  static ViewabilityMode? tryParse(Object? value) {
    if (value is! String) return null;
    for (final mode in values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}

/// Snapshot of an ad's native viewability measurement (mirrors the SDK's
/// `ViewabilityUpdate`). Delivered on every measurement pass: up to once
/// per frame while scrolling and 10 times per second while the continuous
/// in-view timer runs. React to [becameViewable]; avoid `setState` per
/// update.
@immutable
class ViewabilityUpdate {
  const ViewabilityUpdate({
    required this.adUnitId,
    required this.ratio,
    required this.isVisible,
    required this.dwell,
    required this.mode,
    required this.isViewable,
    required this.becameViewable,
    required this.isAppActive,
    required this.timestamp,
  });

  final String adUnitId;

  /// Fraction of the creative's pixels currently within the viewport (0–1).
  final double ratio;

  /// `ratio >= 0.5` and the app is active and this screen is on top.
  final bool isVisible;

  /// Continuous seconds in view. Resets on any dip below 50 %, app
  /// backgrounding, or the screen being covered.
  final double dwell;

  final ViewabilityMode mode;

  /// Latched verdict: once counted, stays `true` until a new impression.
  final bool isViewable;

  /// `true` on exactly one update per impression: the sample that latched.
  final bool becameViewable;

  final bool isAppActive;

  /// Platform-monotonic seconds (not epoch time).
  final double timestamp;

  /// Decodes a channel payload. Returns `null` for malformed input.
  static ViewabilityUpdate? tryDecode(Map<Object?, Object?> map) {
    final adUnitId = map['adUnitId'];
    final mode = ViewabilityMode.tryParse(map['mode']);
    if (adUnitId is! String || mode == null) return null;
    double? num_(Object? v) => v is num ? v.toDouble() : null;
    bool? bool_(Object? v) => v is bool ? v : null;
    final ratio = num_(map['ratio']);
    final dwell = num_(map['dwell']);
    final timestamp = num_(map['timestamp']);
    final isVisible = bool_(map['isVisible']);
    final isViewable = bool_(map['isViewable']);
    final becameViewable = bool_(map['becameViewable']);
    final isAppActive = bool_(map['isAppActive']);
    if (ratio == null ||
        dwell == null ||
        timestamp == null ||
        isVisible == null ||
        isViewable == null ||
        becameViewable == null ||
        isAppActive == null) {
      return null;
    }
    return ViewabilityUpdate(
      adUnitId: adUnitId,
      ratio: ratio,
      isVisible: isVisible,
      dwell: dwell,
      mode: mode,
      isViewable: isViewable,
      becameViewable: becameViewable,
      isAppActive: isAppActive,
      timestamp: timestamp,
    );
  }

  @override
  String toString() =>
      'ViewabilityUpdate($adUnitId ratio=${ratio.toStringAsFixed(2)} '
      'visible=$isVisible dwell=${dwell.toStringAsFixed(2)}s '
      'viewable=$isViewable became=$becameViewable active=$isAppActive)';
}
