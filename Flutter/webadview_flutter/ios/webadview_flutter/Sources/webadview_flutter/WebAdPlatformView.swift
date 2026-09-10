import Flutter
import UIKit
import WebAdViewSDK

/// Creates one `WebAdPlatformView` per Dart platform view (`UiKitView`).
final class WebAdPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let scopes: ScopeRegistry

    init(messenger: FlutterBinaryMessenger, scopes: ScopeRegistry) {
        self.messenger = messenger
        self.scopes = scopes
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        WebAdPlatformView(frame: frame, viewId: viewId, arguments: args, messenger: messenger, scopes: scopes)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    /// WKWebView inside a scrolling Flutter list: deliver touches only once
    /// the Flutter gesture arena has settled (what webview_flutter uses).
    /// `eager` is the documented source of WebKit gesture-state bugs.
    func gestureRecognizersBlockingPolicy() -> FlutterPlatformViewGestureRecognizersBlockingPolicy {
        // C enum: Swift imports the cases as global constants.
        FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded
    }
}

/// Hosts one ad's `WebAdHostView` and forwards its per-ad events to Dart on
/// the view's own channel (`dk.stepnetwork.webadview_flutter/ad/<viewId>`).
final class WebAdPlatformView: NSObject, FlutterPlatformView {
    private let container: UIView
    private var hostView: WebAdHostView?
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger, scopes: ScopeRegistry) {
        channel = FlutterMethodChannel(
            name: "\(WebAdViewFlutterPlugin.channelName)/ad/\(viewId)",
            binaryMessenger: messenger
        )
        container = UIView(frame: frame)
        container.backgroundColor = .clear
        super.init()

        let params = arguments as? [String: Any] ?? [:]
        guard let scopeId = GeometryCodec.string(params["scopeId"]),
              let adUnitId = GeometryCodec.string(params["adUnitId"]) else {
            SNLog.log("[SN] [FLUTTER] platform view \(viewId): missing scopeId/adUnitId — empty view")
            return
        }
        guard let entry = scopes[scopeId] else {
            // Race after disposeScope (route popped while the view was being
            // created): show nothing rather than an orphaned ad.
            SNLog.log("[SN] [FLUTTER] platform view \(viewId): unknown scope \(scopeId) — empty view")
            return
        }

        let host = WebAdHostView(
            adUnitId: adUnitId,
            scope: entry.scope,
            customTargeting: GeometryCodec.targeting(from: params["customTargeting"]),
            viewportResizing: GeometryCodec.bool(params["viewportResizing"], default: true)
        )
        host.frame = container.bounds
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(host)
        hostView = host

        let channel = self.channel
        host.onAdSizeChange = { size in
            channel.invokeMethod("onAdSize", arguments: ["width": Double(size.width), "height": Double(size.height)])
        }
        host.onActiveViewImpression = { slotId in
            channel.invokeMethod("onActiveViewImpression", arguments: ["slotId": slotId])
        }
        SNLog.log("[SN] [FLUTTER] platform view \(viewId): hosting \(adUnitId) in scope \(scopeId)")
    }

    func view() -> UIView {
        container
    }

    deinit {
        // The engine drops its only strong reference on Dart-side dispose.
        hostView?.unload()
        channel.setMethodCallHandler(nil)
    }
}
