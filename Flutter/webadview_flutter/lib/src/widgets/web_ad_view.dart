import 'package:flutter/widgets.dart';

import '../logging.dart';
import '../model/ad_load_state.dart';
import '../model/viewability.dart';
import '../platform/ad_view_channel.dart';
import '../platform/platform_support.dart';
import '../scope/lazy_load_ad_scope.dart';
import 'geometry_marker.dart';
import 'native_ad_view.dart';

/// One ad placement (mirrors the SwiftUI SDK's `WebAdView`).
///
/// Must sit below a [LazyLoadAdScope]. The widget renders an empty box of
/// [initialWidth] × [initialHeight] until lazy loading fetches the ad, then
/// the native ad view, resized to the creative the ad server delivers
/// (clamped by the optional min/max constraints — UI layout only; sizes and
/// formats are controlled remotely by STEP Network's Yield Manager).
///
/// Give the widget a new [key] to force a fresh ad (the `.id(adKey)`
/// pattern from the SwiftUI guide).
class WebAdView extends StatefulWidget {
  const WebAdView({
    super.key,
    required this.adUnitId,
    this.showAdLabel = false,
    this.adLabelText = 'annonce',
    this.adLabelStyle,
    this.initialWidth = 320,
    this.initialHeight = 320,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.customTargeting = const <String, List<String>>{},
    this.viewportResizing = true,
    this.onViewabilityChange,
    this.onActiveViewImpression,
  });

  /// The ad unit id from your STEP Network onboarding. Unique per scope.
  final String adUnitId;

  /// Shows a small label above the creative (excluded from measurement).
  final bool showAdLabel;
  final String adLabelText;
  final TextStyle? adLabelStyle;

  /// Container size while loading (and when unloaded).
  final double initialWidth;
  final double initialHeight;

  /// Optional constraints on the delivered size. Restrictive values can
  /// crop ads — prefer leaving them unset.
  final double? minWidth;
  final double? maxWidth;
  final double? minHeight;
  final double? maxHeight;

  /// Google Ad Manager key/values (JSON-encoded into the page; keys must be
  /// configured by STEP Network before they affect delivery).
  final Map<String, List<String>> customTargeting;

  /// Honest GPT Active View measurement (the native webview is resized to
  /// the visible slice). ON by default; opt a single ad out only when STEP
  /// Network asks you to.
  final bool viewportResizing;

  /// Every native viewability measurement (up to once per frame while
  /// scrolling, 10 Hz while the in-view timer runs). Check
  /// [ViewabilityUpdate.becameViewable] for the moment the impression
  /// latches; avoid calling `setState` per update.
  final void Function(ViewabilityUpdate update)? onViewabilityChange;

  /// GPT Active View's own `impressionViewable` verdict, with the slot id.
  final void Function(String slotId)? onActiveViewImpression;

  @override
  State<WebAdView> createState() => _WebAdViewState();
}

class _WebAdViewState extends State<WebAdView> implements AdScopeClient {
  LazyLoadAdScopeState? _scope;
  AdLoadState _loadState = AdLoadState.notLoaded;
  late Size _adSize = _initialSize;
  AdViewChannel? _channel;
  int _impression = 0;
  bool _warnedNoScope = false;

  @override
  final BoxHandle frameHandle = BoxHandle();
  @override
  final BoxHandle creativeHandle = BoxHandle();

  @override
  String get adUnitId => widget.adUnitId;

  Size get _initialSize => Size(widget.initialWidth, widget.initialHeight);

  bool get _showsNativeView =>
      PlatformSupport.isSupported &&
      (_loadState == AdLoadState.fetched || _loadState == AdLoadState.displayed);

  // ---- scope registration -------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = LazyLoadAdScope.maybeOf(context);
    if (scope == null) {
      assert(() {
        throw FlutterError(
          'WebAdView("${widget.adUnitId}") has no LazyLoadAdScope ancestor.\n'
          'Wrap the scrollable that holds your ads in a LazyLoadAdScope — it '
          'is required (like .lazyLoadAd() in the SwiftUI SDK); without it '
          'ads never load.',
        );
      }());
      if (!_warnedNoScope) {
        _warnedNoScope = true;
        SnLog.errorOnce('no_scope_${widget.adUnitId}',
            'WebAdView("${widget.adUnitId}") has no LazyLoadAdScope ancestor — the ad will not load.');
      }
      return;
    }
    if (!identical(scope, _scope)) {
      _scope?.unregisterAd(this);
      _scope = scope;
      scope.registerAd(this);
    }
  }

  @override
  void didUpdateWidget(WebAdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adUnitId != widget.adUnitId) {
      // A different placement: start over as a new ad.
      final scope = _scope;
      if (scope != null) {
        scope.unregisterAd(_ClientProxy(oldWidget.adUnitId, this));
        _resetImpression();
        scope.registerAd(this);
      }
    } else if (oldWidget.initialWidth != widget.initialWidth ||
        oldWidget.initialHeight != widget.initialHeight ||
        oldWidget.showAdLabel != widget.showAdLabel) {
      _scope?.markNeedsReport();
    }
  }

  @override
  void dispose() {
    _channel?.dispose();
    _channel = null;
    _scope?.unregisterAd(this);
    super.dispose();
  }

  void _resetImpression() {
    _channel?.dispose();
    _channel = null;
    _loadState = AdLoadState.notLoaded;
    _adSize = _initialSize;
    _impression++;
  }

  // ---- native events ------------------------------------------------------

  @override
  void onLoadState(AdLoadState state) {
    if (state == _loadState || !mounted) return;
    final wasShowing = _showsNativeView;
    setState(() {
      _loadState = state;
      if (wasShowing && !_showsNativeView) {
        // unloaded / notLoaded: the platform view leaves the tree. Whatever
        // comes back is a new impression with a new native view.
        _channel?.dispose();
        _channel = null;
        _adSize = _initialSize;
        _impression++;
      }
    });
    _scope?.markNeedsReport();
  }

  @override
  void onViewability(ViewabilityUpdate update) {
    widget.onViewabilityChange?.call(update);
  }

  void _onPlatformViewCreated(int viewId) {
    _channel?.dispose();
    _channel = AdViewChannel(
      viewId,
      onAdSize: _onAdSize,
      onActiveViewImpression: (slotId) =>
          widget.onActiveViewImpression?.call(slotId),
      onRenderProcessGone: _recreateNativeView,
    );
  }

  /// Android: the WebView renderer crashed. A new platform view (and thus a
  /// new impression) replaces it; the load state is unchanged.
  void _recreateNativeView() {
    if (!mounted) return;
    setState(() {
      _channel?.dispose();
      _channel = null;
      _adSize = _initialSize;
      _impression++;
    });
    _scope?.markNeedsReport();
  }

  /// Same clamping as the SwiftUI view.
  void _onAdSize(Size size) {
    if (!mounted) return;
    final width = _clamp(size.width, widget.minWidth, widget.maxWidth);
    final height = _clamp(size.height, widget.minHeight, widget.maxHeight);
    final next = Size(width, height);
    if (next == _adSize) return;
    setState(() => _adSize = next);
    _scope?.markNeedsReport();
  }

  static double _clamp(double value, double? min, double? max) {
    var v = value;
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    return v;
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final showsView = scope != null && _showsNativeView;
    final size = showsView ? _adSize : _initialSize;

    Widget creative = SizedBox(
      width: size.width,
      height: size.height,
      child: showsView
          ? NativeAdView(
              key: ValueKey<int>(_impression),
              params: NativeAdViewParams(
                scopeId: scope.scopeId,
                adUnitId: widget.adUnitId,
                customTargeting: _sanitizedTargeting(),
                viewportResizing: widget.viewportResizing,
              ),
              onCreated: _onPlatformViewCreated,
            )
          : const SizedBox.shrink(),
    );
    creative = GeometryMarker(
      handle: creativeHandle,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: creative,
      ),
    );

    return GeometryMarker(
      handle: frameHandle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.showAdLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                widget.adLabelText,
                textAlign: TextAlign.center,
                style: widget.adLabelStyle ?? _defaultLabelStyle(context),
              ),
            ),
          creative,
        ],
      ),
    );
  }

  Map<String, List<String>> _sanitizedTargeting() {
    final result = <String, List<String>>{};
    widget.customTargeting.forEach((key, values) {
      if (values.isEmpty) {
        SnLog.log('customTargeting: empty list for key "$key" ignored');
        return;
      }
      result[key] = List<String>.unmodifiable(values);
    });
    return result;
  }

  static TextStyle _defaultLabelStyle(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final color = base.color ?? const Color(0xFF000000);
    return base.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.bold,
      color: color.withValues(alpha: 0.6),
    );
  }
}

/// Lets the state unregister its *previous* ad unit id after a widget
/// update changed it (the scope compares identity of the client it stored).
class _ClientProxy implements AdScopeClient {
  _ClientProxy(this.adUnitId, this._state);

  @override
  final String adUnitId;
  final _WebAdViewState _state;

  @override
  BoxHandle get frameHandle => _state.frameHandle;
  @override
  BoxHandle get creativeHandle => _state.creativeHandle;
  @override
  void onLoadState(AdLoadState state) {}
  @override
  void onViewability(ViewabilityUpdate update) {}
}
