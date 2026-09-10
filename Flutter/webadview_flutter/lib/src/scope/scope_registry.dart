import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../logging.dart';
import '../model/ad_load_state.dart';
import '../model/viewability.dart';
import '../platform/webadview_platform.dart';
import 'lazy_load_ad_scope.dart';

/// Process-wide registry of live [LazyLoadAdScope]s.
///
/// Owns the ONE persistent frame callback that reports geometry: it runs
/// after every rendered frame (after layout and paint), asks each scope to
/// diff its geometry against what it last sent, and costs nothing while no
/// frames are produced. It also routes native → Dart events to the scope
/// they belong to; events for unknown scopes (stale after a hot restart)
/// are dropped silently.
class ScopeRegistry implements WebAdViewPlatformListener {
  ScopeRegistry._();

  static final ScopeRegistry instance = ScopeRegistry._();

  final Map<String, LazyLoadAdScopeState> _scopes = <String, LazyLoadAdScopeState>{};
  int _nextId = 0;
  bool _frameCallbackInstalled = false;
  WebAdViewPlatform? _listeningTo;

  String nextScopeId() => 'scope-${_nextId++}-${DateTime.now().microsecondsSinceEpoch}';

  void addScope(LazyLoadAdScopeState scope) {
    _scopes[scope.scopeId] = scope;
    _listen();
    _installFrameCallback();
  }

  void removeScope(LazyLoadAdScopeState scope) {
    if (identical(_scopes[scope.scopeId], scope)) {
      _scopes.remove(scope.scopeId);
    }
  }

  LazyLoadAdScopeState? scope(String scopeId) => _scopes[scopeId];

  void _listen() {
    final platform = WebAdViewPlatform.instance;
    if (identical(_listeningTo, platform)) return;
    _listeningTo = platform;
    platform.listener = this;
  }

  void _installFrameCallback() {
    if (_frameCallbackInstalled) return;
    _frameCallbackInstalled = true;
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    if (_scopes.isEmpty) return;
    for (final scope in _scopes.values.toList(growable: false)) {
      try {
        scope.reportIfChanged();
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'webadview_flutter',
          context: ErrorDescription('while reporting ad geometry'),
        ));
      }
    }
  }

  @override
  void onLoadState(String scopeId, String adUnitId, AdLoadState state) {
    final target = _scopes[scopeId]?.client(adUnitId);
    if (target == null) {
      SnLog.log('onLoadState for unknown $scopeId/$adUnitId ignored');
      return;
    }
    target.onLoadState(state);
  }

  @override
  void onViewability(String scopeId, ViewabilityUpdate update) {
    _scopes[scopeId]?.client(update.adUnitId)?.onViewability(update);
  }

  @visibleForTesting
  void resetForTesting() {
    _scopes.clear();
    _listeningTo = null;
  }
}
