import Combine
import Foundation
import WebAdViewSDK

/// One entry per Dart `LazyLoadAdScope`: the SDK scope plus the per-ad
/// subscriptions that forward load states and viewability to Dart.
final class ScopeEntry {
    let scope: WebAdScope
    private var loadStateSubscriptions: [String: AnyCancellable] = [:]
    private var viewabilitySubscriptions: [String: AnyCancellable] = [:]
    private(set) var isDisposed = false

    /// Ad views kept alive after their Flutter widget was disposed (a
    /// `ListView.builder` row scrolled out of the cache extent), oldest
    /// first. A widget for the same ad unit re-attaches the view instead of
    /// creating a new webview and running a new ad request — the same
    /// impression simply continues. Bounded; the oldest is unloaded when
    /// the pool is full, everything is unloaded when the scope goes.
    private var retained: [(adUnitId: String, host: WebAdHostView)] = []
    static let retainedLimit = 4
    /// The host each live platform view shows. Flutter may create the
    /// replacement platform view BEFORE it disposes the old one (same ad
    /// unit, widget rebuilt within a frame): the new view takes the host
    /// over, and the old view's deinit must then leave it alone.
    private var attached: [String: WebAdHostView] = [:]

    init(scope: WebAdScope) {
        self.scope = scope
    }

    /// `onViewability` nil = Dart has no listener for this ad: no channel
    /// traffic for it (the webview bridge and clips are unaffected).
    func registerAd(_ adUnitId: String,
                    onLoadState: @escaping (AdLoadState) -> Void,
                    onViewability: ((ViewabilityUpdate) -> Void)?) {
        scope.register(adUnitId)
        loadStateSubscriptions[adUnitId] = scope.loadStates(for: adUnitId).sink(receiveValue: onLoadState)
        viewabilitySubscriptions.removeValue(forKey: adUnitId)?.cancel()
        if let onViewability {
            viewabilitySubscriptions[adUnitId] = scope.viewabilityUpdates(for: adUnitId).sink(receiveValue: onViewability)
        }
    }

    /// The Dart widget is gone. A loaded ad is only DETACHED (its state and
    /// webview stay, see `retained`); an ad that never loaded is forgotten.
    func unregisterAd(_ adUnitId: String) {
        loadStateSubscriptions.removeValue(forKey: adUnitId)?.cancel()
        viewabilitySubscriptions.removeValue(forKey: adUnitId)?.cancel()
        switch scope.loadState(for: adUnitId) {
        case .fetched, .displayed:
            scope.detach(adUnitId)
        default:
            scope.unregister(adUnitId)
        }
    }

    /// A platform view starts showing `host` for `adUnitId`.
    func attach(_ adUnitId: String, host: WebAdHostView) {
        attached[adUnitId] = host
    }

    /// The platform view that showed `host` was disposed. Keeps the view for
    /// a later widget of the same ad unit (or unloads it when the pool is
    /// full or the scope is gone) — unless a newer platform view has already
    /// taken it over, in which case nothing happens.
    func release(_ adUnitId: String, host: WebAdHostView) {
        guard attached[adUnitId] === host else { return } // superseded: the new view owns it
        attached.removeValue(forKey: adUnitId)
        park(adUnitId, host: host)
    }

    private func park(_ adUnitId: String, host: WebAdHostView) {
        guard !isDisposed else {
            host.unload()
            return
        }
        retained.removeAll { $0.adUnitId == adUnitId } // a stale twin, if any
        retained.append((adUnitId, host))
        while retained.count > Self.retainedLimit {
            let evicted = retained.removeFirst()
            evicted.host.unload()
            scope.unregister(evicted.adUnitId)
            SNLog.log("[SN] [FLUTTER] \(evicted.adUnitId): retained pool full — unloaded (will reload when shown again)")
        }
        SNLog.log("[SN] [FLUTTER] \(adUnitId): widget disposed — webview retained for re-attachment (\(retained.count)/\(Self.retainedLimit))")
    }

    /// A new platform view for `adUnitId`: the retained view if there is
    /// one, else the host a not-yet-disposed platform view still shows.
    func takeRetained(_ adUnitId: String) -> WebAdHostView? {
        if let index = retained.firstIndex(where: { $0.adUnitId == adUnitId }) {
            let host = retained.remove(at: index).host
            host.removeFromSuperview()
            SNLog.log("[SN] [FLUTTER] \(adUnitId): widget is back — re-attached the retained webview (no new ad request)")
            return host
        }
        if let live = attached[adUnitId] {
            live.removeFromSuperview()
            SNLog.log("[SN] [FLUTTER] \(adUnitId): widget rebuilt before Flutter disposed the old view — moved the webview over (no new ad request)")
            return live
        }
        return nil
    }

    func dispose() {
        isDisposed = true
        loadStateSubscriptions.values.forEach { $0.cancel() }
        viewabilitySubscriptions.values.forEach { $0.cancel() }
        loadStateSubscriptions.removeAll()
        viewabilitySubscriptions.removeAll()
        retained.forEach { $0.host.unload() }
        retained.removeAll()
        attached.values.forEach { $0.unload() }
        attached.removeAll()
    }
}

/// Scopes keyed by the Dart-generated scope id. Shared between the method
/// channel handler and the platform-view factory. Main thread only.
final class ScopeRegistry {
    private var entries: [String: ScopeEntry] = [:]

    subscript(scopeId: String) -> ScopeEntry? {
        entries[scopeId]
    }

    func create(_ scopeId: String, config: LazyLoadingConfig) -> ScopeEntry {
        if let existing = entries[scopeId] {
            SNLog.log("[SN] [FLUTTER] createScope: scope \(scopeId) already exists — reusing")
            return existing
        }
        let entry = ScopeEntry(scope: WebAdScope(config: config))
        entries[scopeId] = entry
        return entry
    }

    func dispose(_ scopeId: String) {
        entries.removeValue(forKey: scopeId)?.dispose()
    }

    /// Hot restart: Dart state is gone, the native plugin instance survives.
    func disposeAll() {
        entries.values.forEach { $0.dispose() }
        entries.removeAll()
    }

    var count: Int { entries.count }
}
