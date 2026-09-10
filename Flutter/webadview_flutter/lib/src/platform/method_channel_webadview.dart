
import 'package:flutter/services.dart';

import '../logging.dart';
import '../model/ad_load_state.dart';
import '../model/lazy_load_config.dart';
import '../model/viewability.dart';
import '../sdk/webadview_sdk_config.dart';
import 'platform_support.dart';
import 'webadview_platform.dart';

/// Method-channel implementation of [WebAdViewPlatform].
///
/// Channel `dk.stepnetwork.webadview_flutter`. Rectangles travel as
/// `[x, y, width, height]` lists of doubles (logical pixels, global
/// coordinates relative to the Flutter view).
class MethodChannelWebAdView extends WebAdViewPlatform {
  MethodChannelWebAdView({MethodChannel? channel})
      : channel = channel ?? const MethodChannel(channelName) {
    this.channel.setMethodCallHandler(_onNativeCall);
  }

  static const String channelName = 'dk.stepnetwork.webadview_flutter';

  final MethodChannel channel;

  // ---- Dart → native ------------------------------------------------------

  /// Every outgoing call funnels through here: a missing native half latches
  /// [PlatformSupport.isSupported] off; platform errors are logged, never
  /// thrown into build/layout paths.
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      PlatformSupport.markPluginMissing();
      return null;
    } on PlatformException catch (e) {
      SnLog.log('$method failed: ${e.code} ${e.message ?? ''}');
      return null;
    }
  }

  @override
  Future<InitializeResult> initialize(WebAdViewSdkConfig config) async {
    // Unlike the other calls, a rejected configuration must surface: the
    // SDK stays uninitialized and WebAdViewSdk reports it loudly.
    try {
      final result = await channel.invokeMethod<Map<Object?, Object?>>(
          'initialize', config.toChannelMap());
      return InitializeResult(
          alreadyInitialized: result?['alreadyInitialized'] == true);
    } on MissingPluginException {
      PlatformSupport.markPluginMissing();
      return const InitializeResult(alreadyInitialized: false);
    } on PlatformException catch (e) {
      return InitializeResult(
          alreadyInitialized: false,
          error: '${e.code}${e.message == null ? '' : ': ${e.message}'}');
    }
  }

  @override
  Future<void> showConsentPreferences() =>
      _invoke<void>('showConsentPreferences');

  @override
  Future<void> setDebugEnabled(bool enabled) =>
      _invoke<void>('setDebugEnabled', <String, Object?>{'enabled': enabled});

  @override
  Future<bool> isDebugEnabled() async =>
      await _invoke<bool>('isDebugEnabled') ?? false;

  @override
  Future<void> acceptAllConsentForTesting() =>
      _invoke<void>('acceptAllConsentForTesting');

  @override
  Future<void> createScope(String scopeId, LazyLoadConfig config) =>
      _invoke<void>('createScope', <String, Object?>{
        'scopeId': scopeId,
        ...config.toChannelMap(),
      });

  @override
  Future<void> disposeScope(String scopeId) =>
      _invoke<void>('disposeScope', <String, Object?>{'scopeId': scopeId});

  @override
  Future<void> setScopeVisible(String scopeId, bool visible) =>
      _invoke<void>('setScopeVisible',
          <String, Object?>{'scopeId': scopeId, 'visible': visible});

  @override
  Future<void> registerAd(String scopeId, String adUnitId) =>
      _invoke<void>('registerAd',
          <String, Object?>{'scopeId': scopeId, 'adUnitId': adUnitId});

  @override
  Future<void> unregisterAd(String scopeId, String adUnitId) =>
      _invoke<void>('unregisterAd',
          <String, Object?>{'scopeId': scopeId, 'adUnitId': adUnitId});

  @override
  Future<void> updateGeometry(
      String scopeId, Rect viewport, Map<String, AdGeometry> ads) {
    return _invoke<void>('updateGeometry', <String, Object?>{
      'scopeId': scopeId,
      'viewport': encodeRect(viewport),
      'ads': <String, Object?>{
        for (final entry in ads.entries)
          entry.key: <String, Object?>{
            'frame': encodeRect(entry.value.frame),
            'creative': encodeRect(entry.value.creative),
          },
      },
    });
  }

  static List<double> encodeRect(Rect r) =>
      <double>[r.left, r.top, r.width, r.height];

  // ---- native → Dart ------------------------------------------------------

  Future<Object?> _onNativeCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map<Object?, Object?>) {
      SnLog.log('ignored ${call.method}: malformed arguments');
      return null;
    }
    final scopeId = args['scopeId'];
    final adUnitId = args['adUnitId'];
    if (scopeId is! String || adUnitId is! String) {
      SnLog.log('ignored ${call.method}: missing scopeId/adUnitId');
      return null;
    }
    final target = listener;
    if (target == null) return null;

    switch (call.method) {
      case 'onLoadState':
        final state = AdLoadState.tryParse(args['state']);
        if (state == null) {
          SnLog.log('ignored onLoadState: unknown state ${args['state']}');
          return null;
        }
        target.onLoadState(scopeId, adUnitId, state);
      case 'onViewability':
        final update = ViewabilityUpdate.tryDecode(args);
        if (update == null) {
          SnLog.log('ignored onViewability: malformed payload');
          return null;
        }
        target.onViewability(scopeId, update);
      default:
        SnLog.log('ignored unknown native call ${call.method}');
    }
    return null;
  }
}
