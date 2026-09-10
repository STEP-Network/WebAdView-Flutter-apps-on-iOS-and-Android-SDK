import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../logging.dart';
import '../model/ad_load_state.dart';
import '../model/lazy_load_config.dart';
import '../model/viewability.dart';
import '../platform/platform_support.dart';
import '../platform/webadview_platform.dart';
import '../widgets/geometry_marker.dart';
import 'geometry.dart';
import 'scope_registry.dart';

/// What a [LazyLoadAdScope] needs from each ad inside it (implemented by the
/// `WebAdView` state).
abstract class AdScopeClient {
  String get adUnitId;

  /// Whole ad, label included — drives lazy loading.
  BoxHandle get frameHandle;

  /// Creative only — drives viewability.
  BoxHandle get creativeHandle;

  void onLoadState(AdLoadState state);
  void onViewability(ViewabilityUpdate update);
}

/// Installs lazy loading and viewability measurement for every `WebAdView`
/// below it — the Flutter equivalent of the SwiftUI SDK's `.lazyLoadAd()`
/// modifier, and just as **required**: without a scope, ads stay blank.
///
/// Wrap the scrollable that holds your ads:
///
/// ```dart
/// LazyLoadAdScope(
///   child: SingleChildScrollView(
///     child: Column(children: [
///       WebAdView(adUnitId: 'div-gpt-ad-mobile_1', showAdLabel: true),
///       // …content…
///     ]),
///   ),
/// )
/// ```
///
/// The scope's own bounds are the viewport ads are measured against (as
/// with `.lazyLoadAd()` on a `ScrollView`), intersected with the OS safe
/// area. Put it *inside* `Scaffold.body` so an `AppBar` is excluded; use
/// [viewportInsets] for overlays inside the scope (a pinned `SliverAppBar`).
///
/// One scope per screen. Ad unit ids must be unique within a scope.
///
/// `ListView.builder` only builds items about 250 px ahead of the viewport,
/// which defeats the fetch-ahead distance — set
/// `cacheExtent: LazyLoadAdScope.recommendedCacheExtent(context)` on
/// builder-based lists, and note that items disposed by the builder are new
/// impressions when they come back (same as `List` in the SwiftUI SDK).
class LazyLoadAdScope extends StatefulWidget {
  const LazyLoadAdScope({
    super.key,
    required this.child,
    this.config,
    this.viewportInsets = EdgeInsets.zero,
  });

  final Widget child;

  /// Starting thresholds; STEP Network's remote values override the fetch
  /// and display distances (unloading stays as configured here).
  final LazyLoadConfig? config;

  /// Extra insets applied to the viewport, for overlays drawn inside the
  /// scope's bounds (e.g. a pinned `SliverAppBar` height at the top).
  final EdgeInsets viewportInsets;

  /// A `cacheExtent` for builder-based lists that lets ads exist early
  /// enough for the fetch zone. Heuristic: the local fetch threshold or 1.5
  /// screen heights, whichever is larger (STEP's remote percentages are
  /// not visible to Dart).
  static double recommendedCacheExtent(BuildContext context,
      {LazyLoadConfig? config}) {
    final fetch = (config ?? const LazyLoadConfig()).fetchThreshold;
    return math.max(fetch, 1.5 * MediaQuery.sizeOf(context).height);
  }

  /// The nearest scope, registering a dependency. `null` when there is none.
  static LazyLoadAdScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScopeMarker>()?.state;

  @override
  State<LazyLoadAdScope> createState() => LazyLoadAdScopeState();
}

class LazyLoadAdScopeState extends State<LazyLoadAdScope> {
  late final String scopeId;
  final BoxHandle _viewportHandle = BoxHandle();
  final Map<String, AdScopeClient> _clients = <String, AdScopeClient>{};

  GeometrySnapshot? _lastSent;
  bool _forceNext = true;
  bool _visible = true;
  EdgeInsets _safePadding = EdgeInsets.zero;

  bool get _supported => PlatformSupport.isSupported;

  WebAdViewPlatform get _platform => WebAdViewPlatform.instance;

  @override
  void initState() {
    super.initState();
    scopeId = ScopeRegistry.instance.nextScopeId();
    ScopeRegistry.instance.addScope(this);
    if (_supported) {
      // Channel messages are delivered in order: registrations that follow
      // never overtake this call.
      _platform.createScope(scopeId, widget.config ?? const LazyLoadConfig());
      SnLog.log('scope $scopeId created');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _safePadding = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _visible) {
      _visible = visible;
      if (_supported) _platform.setScopeVisible(scopeId, visible);
      if (visible) _forceNext = true;
    }
  }

  @override
  void didUpdateWidget(LazyLoadAdScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportInsets != widget.viewportInsets) _forceNext = true;
  }

  @override
  void dispose() {
    ScopeRegistry.instance.removeScope(this);
    if (_supported) _platform.disposeScope(scopeId);
    super.dispose();
  }

  // ---- ads ----------------------------------------------------------------

  AdScopeClient? client(String adUnitId) => _clients[adUnitId];

  void registerAd(AdScopeClient client) {
    final id = client.adUnitId;
    final previous = _clients[id];
    if (previous != null && !identical(previous, client)) {
      // Either a key change (the new state registers before the old one is
      // disposed — the native ad simply continues under the new widget) or
      // a genuine duplicate id, which the SwiftUI SDK also resolves as
      // "last one wins". The replaced client's later unregister is ignored.
      SnLog.log('adUnitId "$id" registered again in scope $scopeId — the newest WebAdView wins');
    }
    _clients[id] = client;
    _forceNext = true;
    if (_supported) _platform.registerAd(scopeId, id);
    // Make sure a frame runs so the first geometry report goes out.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void unregisterAd(AdScopeClient client) {
    final id = client.adUnitId;
    if (!identical(_clients[id], client)) return;
    _clients.remove(id);
    _forceNext = true;
    if (_supported) _platform.unregisterAd(scopeId, id);
  }

  /// Request a report on the next frame even if nothing moved.
  void markNeedsReport() {
    _forceNext = true;
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  // ---- per-frame report ---------------------------------------------------

  /// Called by [ScopeRegistry] after every rendered frame.
  void reportIfChanged() {
    if (!_supported || !_visible) return;
    final snapshot = _snapshot();
    if (snapshot == null) return;
    if (!_forceNext && snapshot.approxEquals(_lastSent)) return;
    _forceNext = false;
    _lastSent = snapshot;
    _platform.updateGeometry(scopeId, snapshot.viewport, snapshot.ads);
  }

  GeometrySnapshot? _snapshot() {
    final box = _viewportHandle.box;
    var viewport = globalRectOf(box);
    if (box == null || viewport == null) return null;

    // Clip to the OS safe area (status bar, home indicator): the native SDK
    // does the same for SwiftUI containers.
    final viewSize = rootViewSizeOf(box);
    if (viewSize != null) {
      final safe = _safePadding.deflateRect(Offset.zero & viewSize);
      viewport = viewport.intersect(safe);
    }
    viewport = widget.viewportInsets.deflateRect(viewport);
    if (viewport.width <= 0 || viewport.height <= 0) {
      viewport = Rect.fromLTWH(viewport.left, viewport.top, 0, 0);
    }

    final ads = <String, AdGeometry>{};
    for (final client in _clients.values) {
      final frame = globalRectOf(client.frameHandle.box);
      if (frame == null) continue; // not laid out (sliver not built yet)
      final creative = globalRectOf(client.creativeHandle.box) ?? frame;
      ads[client.adUnitId] = AdGeometry(frame: frame, creative: creative);
    }
    return GeometrySnapshot(viewport, ads);
  }

  @visibleForTesting
  GeometrySnapshot? get lastSentForTesting => _lastSent;

  @override
  Widget build(BuildContext context) {
    return _ScopeMarker(
      state: this,
      child: GeometryMarker(handle: _viewportHandle, child: widget.child),
    );
  }
}

class _ScopeMarker extends InheritedWidget {
  const _ScopeMarker({required this.state, required super.child});

  final LazyLoadAdScopeState state;

  @override
  bool updateShouldNotify(_ScopeMarker oldWidget) => false;
}
