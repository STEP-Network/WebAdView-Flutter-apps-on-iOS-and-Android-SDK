import 'package:flutter/services.dart';

/// DEMO ONLY — plays the role of the app's own TCF-certified consent
/// platform (consent mode 3, `SN_CONSENT_MODE=tcf`).
///
/// A certified CMP records the user's answer in the IAB TCF standard
/// location: `IABTCF_TCString` / `IABTCF_gdprApplies` in `UserDefaults`
/// (iOS) or the default `SharedPreferences` (Android). This bridge writes
/// two fixed, valid TC strings there — one "accept all", one "decline all"
/// — through a tiny native channel in the example app (AppDelegate.swift /
/// MainActivity.kt). From the SDK's point of view it is indistinguishable
/// from Cookiebot, OneTrust, Usercentrics or any other TCF CMP: the SDK's
/// `TCFConsentProvider` reads the keys and reacts to changes exactly as it
/// would for a real one. Nothing here talks to the SDK directly.
abstract final class SimulatedCmp {
  static const MethodChannel _channel = MethodChannel('newshub/simulated_cmp');

  /// Records an answer — `accept: true` writes the accept-all TC string,
  /// `accept: false` the decline-all string (both with gdprApplies = 1).
  static Future<void> answer({required bool accept}) =>
      _channel.invokeMethod<void>('answer', <String, Object>{'accept': accept});

  /// Removes the answer, as an uninstalled/reset CMP would leave it.
  static Future<void> clear() => _channel.invokeMethod<void>('clear');

  /// The stored TC string, or null when there is no answer.
  static Future<String?> read() => _channel.invokeMethod<String>('read');
}
