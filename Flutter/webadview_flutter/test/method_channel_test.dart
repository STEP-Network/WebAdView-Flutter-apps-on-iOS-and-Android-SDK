import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webadview_flutter/src/model/ad_load_state.dart';
import 'package:webadview_flutter/src/model/lazy_load_config.dart';
import 'package:webadview_flutter/src/model/viewability.dart';
import 'package:webadview_flutter/src/platform/method_channel_webadview.dart';
import 'package:webadview_flutter/src/platform/platform_support.dart';
import 'package:webadview_flutter/src/platform/webadview_platform.dart';
import 'package:webadview_flutter/src/sdk/webadview_sdk_config.dart';

// The wire contract both native halves implement. Payload shapes are
// asserted exactly: a drift here breaks iOS and Android alike.

class RecordingListener implements WebAdViewPlatformListener {
  final List<String> events = <String>[];
  ViewabilityUpdate? lastUpdate;

  @override
  void onLoadState(String scopeId, String adUnitId, AdLoadState state) {
    events.add('$scopeId/$adUnitId=${state.name}');
  }

  @override
  void onViewability(String scopeId, ViewabilityUpdate update) {
    events.add('$scopeId/${update.adUnitId}:viewability');
    lastUpdate = update;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dk.stepnetwork.webadview_flutter');
  late List<MethodCall> sent;
  late MethodChannelWebAdView platform;
  late RecordingListener listener;

  setUp(() {
    PlatformSupport.resetForTesting();
    sent = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      if (call.method == 'initialize') return <String, Object?>{'alreadyInitialized': true};
      if (call.method == 'isDebugEnabled') return true;
      return null;
    });
    platform = MethodChannelWebAdView(channel: channel);
    listener = RecordingListener();
    platform.listener = listener;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> receive(String method, Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  group('Dart → native encoding', () {
    test('initialize (didomi) sends mode, key, template URL and returns the flag', () async {
      final result = await platform.initialize(WebAdViewSdkConfig.didomi(
        apiKey: 'key-123',
        adTemplateUrl: Uri.parse('https://pub.example/ad.html'),
      ));
      expect(result.alreadyInitialized, isTrue);
      expect(sent.single.method, 'initialize');
      expect(sent.single.arguments, <String, Object?>{
        'mode': 'didomi',
        'adTemplateUrl': 'https://pub.example/ad.html',
        'didomiApiKey': 'key-123',
        'didomiDisableRemoteConfig': false,
      });
    });

    test('initialize surfaces a native rejection instead of swallowing it', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'activity_not_fragment', message: 'needs a FragmentActivity');
      });
      final result = await platform.initialize(WebAdViewSdkConfig.didomi(
          apiKey: 'k', adTemplateUrl: Uri.parse('https://pub.example/ad.html')));
      expect(result.alreadyInitialized, isFalse);
      expect(result.error, 'activity_not_fragment: needs a FragmentActivity');
      expect(PlatformSupport.isSupported, isTrue); // a rejection is not a missing plugin
    });

    test('initialize (tcf) omits the Didomi key', () async {
      await platform.initialize(WebAdViewSdkConfig.tcf(
          adTemplateUrl: Uri.parse('https://pub.example/ad.html')));
      final args = sent.single.arguments as Map<Object?, Object?>;
      expect(args['mode'], 'tcf');
      expect(args.containsKey('didomiApiKey'), isFalse);
    });

    test('createScope flattens the config', () async {
      await platform.createScope('s1', const LazyLoadConfig(fetchThreshold: 1000, unloadingEnabled: true));
      expect(sent.single.arguments, <String, Object?>{
        'scopeId': 's1',
        'fetchThreshold': 1000.0,
        'displayThreshold': 200.0,
        'unloadThreshold': 1600.0,
        'unloadingEnabled': true,
      });
    });

    test('register/unregister/setScopeVisible/dispose carry ids', () async {
      await platform.registerAd('s1', 'ad-a');
      await platform.setScopeVisible('s1', false);
      await platform.unregisterAd('s1', 'ad-a');
      await platform.disposeScope('s1');
      expect(sent.map((c) => c.method).toList(),
          <String>['registerAd', 'setScopeVisible', 'unregisterAd', 'disposeScope']);
      expect(sent[0].arguments, <String, Object?>{'scopeId': 's1', 'adUnitId': 'ad-a'});
      expect(sent[1].arguments, <String, Object?>{'scopeId': 's1', 'visible': false});
      expect(sent[3].arguments, <String, Object?>{'scopeId': 's1'});
    });

    test('updateGeometry encodes rects as [x, y, w, h]', () async {
      await platform.updateGeometry(
        's1',
        const Rect.fromLTWH(0, 44, 400, 700),
        <String, AdGeometry>{
          'ad-a': const AdGeometry(
            frame: Rect.fromLTWH(16, 100, 368, 345),
            creative: Rect.fromLTWH(16, 125, 368, 320),
          ),
        },
      );
      expect(sent.single.arguments, <String, Object?>{
        'scopeId': 's1',
        'viewport': <double>[0, 44, 400, 700],
        'ads': <String, Object?>{
          'ad-a': <String, Object?>{
            'frame': <double>[16, 100, 368, 345],
            'creative': <double>[16, 125, 368, 320],
          },
        },
      });
    });

    test('isDebugEnabled reads the native flag', () async {
      expect(await platform.isDebugEnabled(), isTrue);
    });

    test('a missing native plugin latches the platform as unsupported', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null); // → MissingPluginException
      await platform.registerAd('s1', 'ad-a');
      expect(PlatformSupport.isSupported, isFalse);
    });
  });

  group('native → Dart demux', () {
    test('onLoadState is routed with a parsed state', () async {
      await receive('onLoadState', <String, Object?>{'scopeId': 's1', 'adUnitId': 'ad-a', 'state': 'fetched'});
      expect(listener.events, <String>['s1/ad-a=fetched']);
    });

    test('onViewability decodes the full payload (num → double)', () async {
      await receive('onViewability', <String, Object?>{
        'scopeId': 's1',
        'adUnitId': 'ad-a',
        'ratio': 1,
        'isVisible': true,
        'dwell': 1,
        'isViewable': true,
        'becameViewable': true,
        'isAppActive': true,
        'timestamp': 12345,
        'mode': 'display',
      });
      final u = listener.lastUpdate!;
      expect(u.ratio, 1.0);
      expect(u.dwell, 1.0);
      expect(u.becameViewable, isTrue);
      expect(u.mode, ViewabilityMode.display);
    });

    test('malformed payloads and unknown methods are ignored without throwing', () async {
      await receive('onLoadState', <String, Object?>{'scopeId': 's1', 'adUnitId': 'ad-a', 'state': 'bogus'});
      await receive('onLoadState', 'not a map');
      await receive('onViewability', <String, Object?>{'scopeId': 's1', 'adUnitId': 'ad-a', 'ratio': 'x'});
      await receive('somethingElse', <String, Object?>{'scopeId': 's1', 'adUnitId': 'ad-a'});
      expect(listener.events, isEmpty);
    });
  });
}
