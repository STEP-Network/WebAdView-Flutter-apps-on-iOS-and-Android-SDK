import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SimulatedCmpBridge") {
      SimulatedCmpBridge.register(with: registrar)
    }
  }
}

/// DEMO ONLY — plays the role of the app's own TCF-certified consent platform
/// (consent mode 3). A certified CMP records the user's answer in the IAB TCF
/// standard location, `UserDefaults.standard` keys `IABTCF_TCString` and
/// `IABTCF_gdprApplies`; this bridge writes two fixed, valid TC strings there
/// (accept all / decline all). The ad SDK's `TCFConsentProvider` reads those
/// keys exactly as it would for Cookiebot, OneTrust or Usercentrics. Dart can
/// only choose accept/decline/clear — no string ever crosses the channel.
final class SimulatedCmpBridge: NSObject, FlutterPlugin {
  private static let tcStringKey = "IABTCF_TCString"
  private static let gdprAppliesKey = "IABTCF_gdprApplies"

  // Valid TCF v2.2 strings (same as the native SimulatedCMP demo).
  private static let acceptTCString = "CQn2q4AQn2q4AAHABADACoFsAP_gAELgAAZQLrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCQGEAIACABgACgBIAIAABAAAAABAAQAAAAIAAIAAAAAAEIBAIJCAAAAABAkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAgAAAjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAILrgR9C5cSWlBeTBXYIsAOAQXwFAAIIAgAAAAAgABCBqAIIQCUGEAIACAAAAAABAAIAABAAAIABAAQAABAIAQIBAAAAAAIBAIACAAAAABQkBQAAAAAgAAEAAAgEASAAAAgAAEQNIiQEAAEAAgjAAAIAAAAAAIAAAAAAAAAAEAAAAAgCAAEAAAAAAAAAAAABAIgAAAAAAAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAJCADAAEGVw.ILrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCUGEAIACABgACgBIAIAABAAAIABAAQAABAIAQIBAAAAAEIBAIJCAAAAABQkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAkAAgjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA"
  private static let declineTCString = "CQn2q4AQn2q4AAHABADACoFgAAAAAAAAAAZQAAAGfgAgGfABIQAYAAgyuA.ILrgR9C5cSWlBeTB3YIsAOAQXwFBIIIAgAAAAAgABCBqAIIQCUGEAIACABgACgBIAIAABAAAIABAAQAABAIAQIBAAAAAEIBAIJCAAAAABQkJQCAAAEgAAEAAAgEASAAAAgAAEQdIiQEAAkAAgjAAAIAAAAAAJAAAIAAAAAAEAAAAAgCgAEAAAAAAAAAAAABAIgAAAAAEAAAAAAAABAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "newshub/simulated_cmp", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SimulatedCmpBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let defaults = UserDefaults.standard
    switch call.method {
    case "answer":
      guard let args = call.arguments as? [String: Any], let accept = args["accept"] as? Bool else {
        return result(FlutterError(code: "bad_args", message: "accept (Bool) is required", details: nil))
      }
      defaults.set(accept ? Self.acceptTCString : Self.declineTCString, forKey: Self.tcStringKey)
      defaults.set(1, forKey: Self.gdprAppliesKey)
      result(nil)
    case "clear":
      defaults.removeObject(forKey: Self.tcStringKey)
      defaults.removeObject(forKey: Self.gdprAppliesKey)
      result(nil)
    case "read":
      result(defaults.string(forKey: Self.tcStringKey))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
