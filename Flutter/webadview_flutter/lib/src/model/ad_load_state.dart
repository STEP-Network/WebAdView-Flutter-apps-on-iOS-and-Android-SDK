/// Lazy-loading lifecycle state of an ad unit (mirrors the SDK's
/// `AdLoadState`).
///
/// `notLoaded → fetched` (the ad page loads) `→ displayed` (the creative
/// renders) `→ unloaded` (far away for 2 s, only with unloading enabled)
/// `→ notLoaded` on re-entry.
enum AdLoadState {
  notLoaded,
  fetched,
  displayed,
  unloaded;

  /// Wire name on the method channel (equals the Swift raw value).
  String get wireName => name;

  /// Parses a wire name; `null` for unknown values (never throws — the
  /// value comes from the platform side).
  static AdLoadState? tryParse(Object? value) {
    if (value is! String) return null;
    for (final state in values) {
      if (state.name == value) return state;
    }
    return null;
  }
}
