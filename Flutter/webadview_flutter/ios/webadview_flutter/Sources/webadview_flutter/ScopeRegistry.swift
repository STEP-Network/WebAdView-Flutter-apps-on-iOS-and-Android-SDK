import Combine
import Foundation
import WebAdViewSDK

/// One entry per Dart `LazyLoadAdScope`: the SDK scope plus the per-ad
/// subscriptions that forward load states and viewability to Dart.
final class ScopeEntry {
    let scope: WebAdScope
    private var loadStateSubscriptions: [String: AnyCancellable] = [:]
    private var viewabilitySubscriptions: [String: AnyCancellable] = [:]

    init(scope: WebAdScope) {
        self.scope = scope
    }

    func registerAd(_ adUnitId: String,
                    onLoadState: @escaping (AdLoadState) -> Void,
                    onViewability: @escaping (ViewabilityUpdate) -> Void) {
        scope.register(adUnitId)
        loadStateSubscriptions[adUnitId] = scope.loadStates(for: adUnitId).sink(receiveValue: onLoadState)
        viewabilitySubscriptions[adUnitId] = scope.viewabilityUpdates(for: adUnitId).sink(receiveValue: onViewability)
    }

    func unregisterAd(_ adUnitId: String) {
        loadStateSubscriptions.removeValue(forKey: adUnitId)?.cancel()
        viewabilitySubscriptions.removeValue(forKey: adUnitId)?.cancel()
        scope.unregister(adUnitId)
    }

    func dispose() {
        loadStateSubscriptions.values.forEach { $0.cancel() }
        viewabilitySubscriptions.values.forEach { $0.cancel() }
        loadStateSubscriptions.removeAll()
        viewabilitySubscriptions.removeAll()
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
