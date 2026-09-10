import 'package:flutter/foundation.dart';

/// Dart-side logging, gated on the same debug flag as the native SDK
/// (`WebAdViewSdk.setDebugEnabled`). Tag `[SN] [FLUTTER]` so a console
/// grep for `[SN]` shows both halves.
class SnLog {
  SnLog._();

  /// Mirror of the native flag; kept in sync by `WebAdViewSdk`.
  static bool isEnabled = false;

  static void log(String message) {
    if (!isEnabled) return;
    debugPrint('[SN] [FLUTTER] $message');
  }

  static final Set<String> _once = <String>{};

  /// Un-gated, once per process: mis-integration must never be silent
  /// (the same rule the native SDK follows for its two loud errors).
  static void errorOnce(String key, String message) {
    if (!_once.add(key)) return;
    debugPrint('[SN] [ERROR] $message');
  }

  @visibleForTesting
  static void resetForTesting() {
    _once.clear();
    isEnabled = false;
  }
}
