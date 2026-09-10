import Flutter
import UIKit
import WebAdViewSDK

/// iOS half of the `webadview_flutter` plugin: a thin adapter between the
/// Dart API and the WebAdView SDK's UIKit layer (`WebAdScope` /
/// `WebAdHostView`). Dart owns all geometry; native runs the SDK's lazy-load
/// and viewability state machines unchanged.
///
/// Channel `dk.stepnetwork.webadview_flutter` (Dart → native):
///   initialize, showConsentPreferences, setDebugEnabled, isDebugEnabled,
///   createScope, disposeScope, setScopeVisible, registerAd, unregisterAd,
///   updateGeometry, acceptAllConsentForTesting (DEBUG builds only)
/// Native → Dart on the same channel: onLoadState, onViewability.
public final class WebAdViewFlutterPlugin: NSObject, FlutterPlugin {

    static let channelName = "dk.stepnetwork.webadview_flutter"
    static let viewType = "webadview_flutter/ad"

    private let channel: FlutterMethodChannel
    private let scopes = ScopeRegistry()

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = WebAdViewFlutterPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            WebAdPlatformViewFactory(messenger: registrar.messenger(), scopes: instance.scopes),
            withId: viewType
        )
    }

    // MARK: - Dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            initialize(args, result: result)
        case "showConsentPreferences":
            WebAdViewSDK.showConsentPreferences()
            result(nil)
        case "setDebugEnabled":
            DebugSettings.shared.isDebugEnabled = GeometryCodec.bool(args["enabled"], default: false)
            result(nil)
        case "isDebugEnabled":
            result(DebugSettings.shared.isDebugEnabled)
        case "createScope":
            createScope(args, result: result)
        case "disposeScope":
            guard let scopeId = GeometryCodec.string(args["scopeId"]) else { return result(Self.badArgs("scopeId")) }
            scopes.dispose(scopeId)
            result(nil)
        case "setScopeVisible":
            guard let scopeId = GeometryCodec.string(args["scopeId"]) else { return result(Self.badArgs("scopeId")) }
            scopes[scopeId]?.scope.setHostVisible(GeometryCodec.bool(args["visible"], default: true))
            result(nil)
        case "registerAd":
            registerAd(args, result: result)
        case "unregisterAd":
            guard let scopeId = GeometryCodec.string(args["scopeId"]),
                  let adUnitId = GeometryCodec.string(args["adUnitId"]) else { return result(Self.badArgs("scopeId/adUnitId")) }
            scopes[scopeId]?.unregisterAd(adUnitId)
            result(nil)
        case "updateGeometry":
            updateGeometry(args, result: result)
        case "acceptAllConsentForTesting":
            #if DEBUG
            WebAdViewSDK.acceptAllConsentForTesting()
            result(nil)
            #else
            result(FlutterError(code: "debug_only", message: "acceptAllConsentForTesting is compiled out of release builds", details: nil))
            #endif
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func badArgs(_ what: String) -> FlutterError {
        FlutterError(code: "bad_args", message: "Missing or invalid argument: \(what)", details: nil)
    }

    // MARK: - initialize

    private func initialize(_ args: [String: Any], result: @escaping FlutterResult) {
        // Hot restart: Dart state is gone but this instance survives — drop
        // every scope so orphaned engines don't linger.
        scopes.disposeAll()

        if WebAdViewSDK.isInitialized {
            SNLog.log("[SN] [FLUTTER] initialize: native SDK already initialized (hot restart?) — keeping the existing configuration")
            presentConsentUIIfNeeded()
            result(["alreadyInitialized": true])
            return
        }

        guard let templateString = GeometryCodec.string(args["adTemplateUrl"]),
              let templateURL = URL(string: templateString), templateURL.scheme != nil else {
            return result(Self.badArgs("adTemplateUrl"))
        }
        let mode = GeometryCodec.string(args["mode"]) ?? "didomi"
        let config: WebAdViewSDKConfig
        switch mode {
        case "didomi":
            guard let apiKey = GeometryCodec.string(args["didomiApiKey"]), !apiKey.isEmpty else {
                return result(Self.badArgs("didomiApiKey"))
            }
            config = WebAdViewSDKConfig(
                didomiAPIKey: apiKey,
                adTemplateURL: templateURL,
                didomiDisableRemoteConfig: GeometryCodec.bool(args["didomiDisableRemoteConfig"], default: false)
            )
        case "tcf":
            config = WebAdViewSDKConfig(consentProvider: TCFConsentProvider(), adTemplateURL: templateURL)
        case "appDidomi":
            config = WebAdViewSDKConfig(consentProvider: AppDidomiConsentProvider(), adTemplateURL: templateURL)
        default:
            return result(FlutterError(code: "bad_args", message: "Unknown consent mode '\(mode)'", details: nil))
        }

        WebAdViewSDK.initialize(config: config)
        WebAdViewSDK.warnIfDuplicateDidomi()
        presentConsentUIIfNeeded()
        result(["alreadyInitialized": false])
    }

    /// Standard mode only: Didomi presents its notice from the root Flutter
    /// view controller (the SwiftUI `DidomiWrapper` equivalent). The window
    /// may not exist yet when `initialize` runs before `runApp`, so retry a
    /// few times on the main run loop.
    private func presentConsentUIIfNeeded(attempt: Int = 0) {
        guard WebAdViewSDK.configuration?.consentProvider is DidomiConsentProvider else { return }
        if let root = Self.rootViewController() {
            WebAdViewSDK.setupConsentUI(containerController: root)
        } else if attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentConsentUIIfNeeded(attempt: attempt + 1)
            }
        } else {
            SNLog.log("[SN] [FLUTTER] setupConsentUI: no root view controller found — the Didomi notice cannot be presented")
        }
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }

    // MARK: - Scopes

    private func createScope(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let scopeId = GeometryCodec.string(args["scopeId"]) else { return result(Self.badArgs("scopeId")) }
        var config = LazyLoadingConfig()
        if let fetch = GeometryCodec.double(args["fetchThreshold"]) { config.fetchThreshold = CGFloat(fetch) }
        if let display = GeometryCodec.double(args["displayThreshold"]) { config.displayThreshold = CGFloat(display) }
        if let unload = GeometryCodec.double(args["unloadThreshold"]) { config.unloadThreshold = CGFloat(unload) }
        config.unloadingEnabled = GeometryCodec.bool(args["unloadingEnabled"], default: false)
        _ = scopes.create(scopeId, config: config)
        SNLog.log("[SN] [FLUTTER] createScope \(scopeId) (fetch \(Int(config.fetchThreshold)) / display \(Int(config.displayThreshold)) / unload \(Int(config.unloadThreshold)), unloading \(config.unloadingEnabled))")
        result(nil)
    }

    private func registerAd(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let scopeId = GeometryCodec.string(args["scopeId"]),
              let adUnitId = GeometryCodec.string(args["adUnitId"]) else { return result(Self.badArgs("scopeId/adUnitId")) }
        guard let entry = scopes[scopeId] else {
            return result(FlutterError(code: "unknown_scope", message: "No scope \(scopeId) — call createScope first", details: nil))
        }
        let channel = self.channel
        entry.registerAd(
            adUnitId,
            onLoadState: { state in
                channel.invokeMethod("onLoadState", arguments: [
                    "scopeId": scopeId, "adUnitId": adUnitId, "state": state.rawValue,
                ])
            },
            onViewability: { update in
                channel.invokeMethod("onViewability", arguments: Self.encode(update, scopeId: scopeId))
            }
        )
        result(nil)
    }

    private func updateGeometry(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let scopeId = GeometryCodec.string(args["scopeId"]) else { return result(Self.badArgs("scopeId")) }
        guard let entry = scopes[scopeId] else { return result(nil) } // stale after disposeScope — ignore
        guard let viewport = GeometryCodec.rect(from: args["viewport"]) else { return result(Self.badArgs("viewport")) }

        // Ads first, then the viewport: a new ad frame arriving while the
        // manager's bounds are already set triggers an immediate check.
        if let ads = args["ads"] as? [String: Any] {
            for (adUnitId, raw) in ads {
                guard let rects = raw as? [String: Any] else { continue }
                if let frame = GeometryCodec.rect(from: rects["frame"]) {
                    entry.scope.updateAdFrame(adUnitId, frame: frame)
                }
                if let creative = GeometryCodec.rect(from: rects["creative"]) {
                    entry.scope.updateCreativeFrame(adUnitId, frame: creative)
                }
            }
        }
        entry.scope.updateViewport(viewport)
        result(nil)
    }

    private static func encode(_ update: ViewabilityUpdate, scopeId: String) -> [String: Any] {
        [
            "scopeId": scopeId,
            "adUnitId": update.adUnitId,
            "ratio": Double(update.ratio),
            "isVisible": update.isVisible,
            "dwell": update.dwell,
            "isViewable": update.isViewable,
            "becameViewable": update.becameViewable,
            "isAppActive": update.isAppActive,
            "timestamp": update.timestamp,
            "mode": update.mode.rawValue,
        ]
    }
}
