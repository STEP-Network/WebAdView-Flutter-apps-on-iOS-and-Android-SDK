import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Creation parameters for one native ad view.
@immutable
class NativeAdViewParams {
  const NativeAdViewParams({
    required this.scopeId,
    required this.adUnitId,
    required this.customTargeting,
    required this.viewportResizing,
  });

  final String scopeId;
  final String adUnitId;
  final Map<String, List<String>> customTargeting;
  final bool viewportResizing;

  Map<String, Object?> toMap() => <String, Object?>{
        'scopeId': scopeId,
        'adUnitId': adUnitId,
        'customTargeting': customTargeting,
        'viewportResizing': viewportResizing,
      };
}

typedef NativeAdViewBuilder = Widget Function(
    NativeAdViewParams params, void Function(int viewId) onCreated);

/// Android platform-view composition mode. The port uses the texture layer
/// (`surface`) with Flutter's automatic hybrid-composition fallback; the
/// Kotlin side is identical in every mode.
enum _AndroidComposition {
  /// Texture layer, with automatic hybrid-composition fallback.
  surface,

  /// Always hybrid composition.
  expensive,
}

const _AndroidComposition _androidComposition = _AndroidComposition.surface;

/// The single place that knows how a native ad view is embedded per
/// platform. Everything above it only deals with [NativeAdViewParams].
///
/// Gestures: no recognizers are claimed, so vertical drags stay with the
/// enclosing scrollable and taps reach the web view once the Flutter
/// gesture arena has settled (the recipe `webview_flutter` uses for
/// tap-to-open inside lists).
class NativeAdView extends StatelessWidget {
  const NativeAdView({super.key, required this.params, required this.onCreated});

  static const String viewType = 'webadview_flutter/ad';

  final NativeAdViewParams params;
  final void Function(int viewId) onCreated;

  /// Test seam: replaces the platform view in widget tests.
  @visibleForTesting
  static NativeAdViewBuilder? debugBuilder;

  @override
  Widget build(BuildContext context) {
    final override = debugBuilder;
    if (override != null) return override(params, onCreated);

    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: viewType,
          layoutDirection: direction,
          creationParams: params.toMap(),
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          onPlatformViewCreated: onCreated,
        );
      case TargetPlatform.android:
        return PlatformViewLink(
          viewType: viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          ),
          onCreatePlatformView: (PlatformViewCreationParams p) {
            final AndroidViewController controller;
            switch (_androidComposition) {
              case _AndroidComposition.surface:
                controller = PlatformViewsService.initSurfaceAndroidView(
                  id: p.id,
                  viewType: viewType,
                  layoutDirection: direction,
                  creationParams: params.toMap(),
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () => p.onFocusChanged(true),
                );
              case _AndroidComposition.expensive:
                controller = PlatformViewsService.initExpensiveAndroidView(
                  id: p.id,
                  viewType: viewType,
                  layoutDirection: direction,
                  creationParams: params.toMap(),
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () => p.onFocusChanged(true),
                );
            }
            controller
              ..addOnPlatformViewCreatedListener(p.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(onCreated)
              ..create();
            return controller;
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
