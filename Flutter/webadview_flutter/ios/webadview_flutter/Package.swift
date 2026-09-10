// swift-tools-version: 5.9
import PackageDescription
import Foundation

// The WebAdView iOS SDK is resolved from the LOCAL checkout only (no git URL):
// this manifest lives at <repo>/Flutter/webadview_flutter/ios/webadview_flutter,
// so the SDK package root is four levels up. Flutter builds the plugin through
// a symlink (…/ios/Flutter/ephemeral/Packages/.packages/<plugin>), so the
// symlink is resolved first — a plain relative `path:` would resolve against
// the symlink's location. `WEBADVIEW_SDK_PATH` (absolute path) overrides the
// lookup for unusual layouts.
let manifestDirectory = URL(fileURLWithPath: #filePath)
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
let sdkPath = ProcessInfo.processInfo.environment["WEBADVIEW_SDK_PATH"].flatMap { $0.isEmpty ? nil : $0 }
    ?? manifestDirectory.appendingPathComponent("../../../..").standardized.path

let package = Package(
    name: "webadview_flutter",
    platforms: [
        // The SDK (and Didomi) require iOS 16; the host app must match.
        .iOS(.v16)
    ],
    products: [
        .library(name: "webadview-flutter", targets: ["webadview_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "WebAdViewSDK", path: sdkPath),
    ],
    targets: [
        .target(
            name: "webadview_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "WebAdViewSDK", package: "WebAdViewSDK"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
