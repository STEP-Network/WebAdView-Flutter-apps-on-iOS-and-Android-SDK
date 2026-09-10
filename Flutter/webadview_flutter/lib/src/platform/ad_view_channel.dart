
import 'package:flutter/services.dart';

import '../logging.dart';
import 'method_channel_webadview.dart';

/// Per-platform-view channel (`…/ad/<viewId>`) carrying the events that
/// belong to one ad's webview: the rendered creative size and GPT Active
/// View's viewable verdict.
class AdViewChannel {
  AdViewChannel(this.viewId,
      {required this.onAdSize,
      required this.onActiveViewImpression,
      this.onRenderProcessGone})
      : _channel = MethodChannel(
            '${MethodChannelWebAdView.channelName}/ad/$viewId') {
    _channel.setMethodCallHandler(_onCall);
  }

  final int viewId;
  final void Function(Size size) onAdSize;
  final void Function(String slotId) onActiveViewImpression;

  /// Android only: the WebView's renderer died; the widget recreates the view.
  final void Function()? onRenderProcessGone;
  final MethodChannel _channel;

  Future<Object?> _onCall(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'onAdSize':
        if (args is Map<Object?, Object?>) {
          final w = args['width'];
          final h = args['height'];
          if (w is num && h is num && w > 0 && h > 0) {
            onAdSize(Size(w.toDouble(), h.toDouble()));
            return null;
          }
        }
        SnLog.log('ignored onAdSize for view $viewId: malformed payload');
      case 'onActiveViewImpression':
        final slotId =
            args is Map<Object?, Object?> ? args['slotId'] : null;
        onActiveViewImpression(slotId is String ? slotId : 'unknown');
      case 'onRenderProcessGone':
        SnLog.log('view $viewId: render process gone — recreating the native view');
        onRenderProcessGone?.call();
      default:
        SnLog.log('ignored unknown view call ${call.method}');
    }
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
