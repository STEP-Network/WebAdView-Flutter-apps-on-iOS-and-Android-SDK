package dk.stepnetwork.webadview_flutter.core

/**
 * Lazy-loading lifecycle state of an ad unit (port of AdLoadState).
 * notLoaded → fetched (fetch zone) → displayed (display zone) → unloaded
 * (outside the unload zone for the stability delay, only with unloading
 * enabled) → notLoaded on re-entry. [wireName] is the Dart contract string.
 */
enum class AdLoadState(val wireName: String) {
    NOT_LOADED("notLoaded"),
    FETCHED("fetched"),
    DISPLAYED("displayed"),
    UNLOADED("unloaded"),
}

/** Tuning values for lazy loading (port of LazyLoadingConfig). Distances in dp. */
data class LazyLoadingConfig(
    val fetchThreshold: Double = 800.0,
    val displayThreshold: Double = 200.0,
    val unloadThreshold: Double = 1600.0,
    val unloadingEnabled: Boolean = false,
)
