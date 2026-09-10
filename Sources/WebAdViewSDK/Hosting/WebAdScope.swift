import Foundation
import CoreGraphics
import Combine
import WebAdViewCore

/// UIKit-level equivalent of the `.lazyLoadAd()` SwiftUI modifier: one scope
/// per scroll container, owning that container's lazy-load state machine and
/// viewability measurement.
///
/// Hosts that are not SwiftUI (the Flutter plugin, a UIKit table view) create
/// one scope per scrollable screen, feed it geometry in window coordinates —
/// the container's visible rect plus, per ad, the whole ad frame (label
/// included, drives lazy loading) and the creative-only frame (drives
/// viewability) — and create a `WebAdHostView` per ad once the scope reports
/// `.fetched`. The state machines are the same ones the SwiftUI view uses;
/// only the geometry source differs.
///
/// Main thread only.
public final class WebAdScope {

    let manager: LazyLoadingManager
    let tracker: ViewabilityTracker

    /// - Parameter config: starting lazy-load thresholds. STEP Network's
    ///   remote per-domain values (cached from a previous read-back, or read
    ///   live from the next loaded ad page) always override them.
    public convenience init(config: LazyLoadingConfig = LazyLoadingConfig()) {
        self.init(
            config: config,
            remoteStore: RemoteLazyLoadStore(),
            templateHost: WebAdViewSDK.configuration?.adTemplateURL.host
        )
    }

    /// Internal seam: injectable cache + host for tests.
    init(config: LazyLoadingConfig, remoteStore: RemoteLazyLoadStore, templateHost: String?) {
        manager = LazyLoadingManager(config: config)
        tracker = ViewabilityTracker()
        // Same start-up rule as LazyLoadAdInternalModifier.onAppear: a cached
        // remote config applies before any page has loaded.
        if let host = templateHost, let cached = remoteStore.load(forHost: host) {
            manager.applyRemote(cached)
        }
    }

    // MARK: Geometry input (window coordinates, points)

    /// The scroll container's visible rect. Feeds both state machines.
    public func updateViewport(_ rect: CGRect) {
        manager.updateScrollViewBounds(rect)
        tracker.updateScrollViewBounds(rect)
    }

    /// The whole ad frame (label included) — lazy loading.
    public func updateAdFrame(_ adUnitId: String, frame: CGRect) {
        manager.updateAdFrame(adUnitId, frame: frame)
    }

    /// The creative-only frame (label excluded) — viewability measurement.
    public func updateCreativeFrame(_ adUnitId: String, frame: CGRect) {
        tracker.updateContentFrame(adUnitId, frame: frame)
    }

    // MARK: Registration

    /// Registers an ad unit for measurement (display standard). Ad unit ids
    /// must be unique within a scope.
    public func register(_ adUnitId: String) {
        tracker.register(adUnitId, mode: .display)
    }

    /// Forgets an ad unit in both state machines (the host destroyed its view).
    public func unregister(_ adUnitId: String) {
        manager.removeAd(adUnitId)
        tracker.unregister(adUnitId)
    }

    /// Whether the hosting screen is on top. Pass `false` while another
    /// screen covers this one: ads underneath must not accrue dwell.
    public func setHostVisible(_ visible: Bool) {
        tracker.setHostVisible(visible)
    }

    // MARK: Outputs

    /// Current lazy-load state (`.notLoaded` until the first transition).
    public func loadState(for adUnitId: String) -> AdLoadState {
        manager.adStates[adUnitId] ?? .notLoaded
    }

    /// Lazy-load state stream. Replays the current state on subscribe (once
    /// one exists) and emits only on change.
    public func loadStates(for adUnitId: String) -> AnyPublisher<AdLoadState, Never> {
        manager.adStatesPublisher(for: adUnitId)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Every viewability measurement update for an ad (the UIKit-level
    /// `.onViewabilityChange`).
    public func viewabilityUpdates(for adUnitId: String) -> AnyPublisher<ViewabilityUpdate, Never> {
        tracker.updates(for: adUnitId)
    }
}
