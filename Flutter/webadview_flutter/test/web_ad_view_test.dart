import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webadview_flutter/src/platform/platform_support.dart';
import 'package:webadview_flutter/src/platform/ad_view_channel.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

import 'support/fake_platform.dart';

// Widget-level behaviour of LazyLoadAdScope + WebAdView against a fake
// platform: geometry reporting, load-state gating of the native view, size
// clamping, callbacks, route covering, and integration errors.

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.tearDown());

  Widget twoAds({ScrollController? controller, bool label = false}) {
    return LazyLoadAdScope(
      child: SingleChildScrollView(
        controller: controller,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 100),
            WebAdView(adUnitId: 'ad-a', showAdLabel: label),
            const SizedBox(height: 900),
            const WebAdView(adUnitId: 'ad-b'),
            const SizedBox(height: 900),
          ],
        ),
      ),
    );
  }

  group('scope lifecycle', () {
    testWidgets('creates the native scope, registers ads, and tears both down', (tester) async {
      await tester.pumpApp(twoAds());
      expect(h.platform.calls.first, 'createScope');
      expect(h.platform.calls, containsAll(<String>['registerAd:ad-a', 'registerAd:ad-b']));
      final scopeId = h.platform.singleScopeId!;
      expect(h.platform.ads[scopeId], <String>{'ad-a', 'ad-b'});

      await tester.pumpWidget(const SizedBox());
      final calls = h.platform.calls;
      expect(calls.indexOf('unregisterAd:ad-a'), lessThan(calls.indexOf('disposeScope')));
      expect(h.platform.scopes, isEmpty);
    });
  });

  group('geometry reporting', () {
    testWidgets('first frame reports the viewport and both ads; scrolling reports once per change', (tester) async {
      final controller = ScrollController();
      await tester.pumpApp(twoAds(controller: controller));

      expect(h.platform.geometry, hasLength(1));
      final first = h.platform.geometry.single;
      expect(first.viewport, const Rect.fromLTWH(0, 0, 400, 800));
      expect(first.ads['ad-a']!.frame, const Rect.fromLTWH(40, 100, 320, 320));
      expect(first.ads['ad-b']!.frame, const Rect.fromLTWH(40, 1320, 320, 320));
      expect(first.ads['ad-a']!.creative, first.ads['ad-a']!.frame);

      // An idle frame sends nothing.
      await tester.pump();
      expect(h.platform.geometry, hasLength(1));

      controller.jumpTo(300);
      await tester.pump();
      expect(h.platform.geometry, hasLength(2));
      expect(h.platform.geometry.last.ads['ad-a']!.frame.top, -200);
      expect(h.platform.geometry.last.ads['ad-b']!.frame.top, 1020);
    });

    testWidgets('the ad label is part of the frame but not of the creative', (tester) async {
      await tester.pumpApp(twoAds(label: true));
      final geo = h.platform.geometry.single.ads['ad-a']!;
      expect(geo.frame.top, 100);
      expect(geo.creative.top, greaterThan(geo.frame.top));
      expect(geo.creative.height, 320);
      expect(geo.frame.height, greaterThan(320));
    });

    testWidgets('the viewport excludes the safe area', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 50, bottom: 30)),
          child: LazyLoadAdScope(
            child: SingleChildScrollView(
              child: Column(children: const <Widget>[WebAdView(adUnitId: 'ad-a')]),
            ),
          ),
        ),
      ));
      expect(h.platform.geometry.single.viewport, const Rect.fromLTWH(0, 50, 400, 720));
    });

    testWidgets('ads inside ListView.builder beyond cacheExtent are not registered until built', (tester) async {
      await tester.pumpApp(LazyLoadAdScope(
        child: ListView.builder(
          itemCount: 20,
          itemBuilder: (context, i) => i == 15
              ? const WebAdView(adUnitId: 'far')
              : const SizedBox(height: 400),
        ),
      ));
      expect(h.platform.calls, isNot(contains('registerAd:far')));

      await tester.drag(find.byType(ListView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(h.platform.calls, contains('registerAd:far'));
      expect(h.platform.geometry.last.ads.keys, contains('far'));

      await tester.drag(find.byType(ListView), const Offset(0, 6000));
      await tester.pumpAndSettle();
      expect(h.platform.calls, contains('unregisterAd:far'));
    });
  });

  group('load-state gating', () {
    testWidgets('native view appears on fetched, disappears on unloaded, and is a new instance on re-fetch', (tester) async {
      await tester.pumpApp(twoAds());
      final scopeId = h.platform.singleScopeId!;
      expect(find.byKey(const Key('fake-native-ad')), findsNothing);
      expect(tester.getSize(find.byType(WebAdView).first), const Size(320, 320));

      h.platform.emitLoadState(scopeId, 'ad-a', AdLoadState.fetched);
      await tester.pump();
      expect(find.byKey(const Key('fake-native-ad')), findsOneWidget);
      expect(h.nativeViews.created, hasLength(1));
      expect(h.nativeViews.created.single.adUnitId, 'ad-a');
      expect(h.nativeViews.created.single.viewportResizing, isTrue);

      h.platform.emitLoadState(scopeId, 'ad-a', AdLoadState.displayed);
      await tester.pump();
      expect(h.nativeViews.created, hasLength(1)); // same view

      h.platform.emitLoadState(scopeId, 'ad-a', AdLoadState.unloaded);
      await tester.pump();
      expect(find.byKey(const Key('fake-native-ad')), findsNothing);

      h.platform.emitLoadState(scopeId, 'ad-a', AdLoadState.notLoaded);
      h.platform.emitLoadState(scopeId, 'ad-a', AdLoadState.fetched);
      await tester.pump();
      expect(h.nativeViews.created, hasLength(2)); // new impression = new view
    });

    testWidgets('unknown scope / ad events are ignored', (tester) async {
      await tester.pumpApp(twoAds());
      h.platform.emitLoadState('stale-scope', 'ad-a', AdLoadState.fetched);
      h.platform.emitLoadState(h.platform.singleScopeId!, 'nope', AdLoadState.fetched);
      await tester.pump();
      expect(find.byKey(const Key('fake-native-ad')), findsNothing);
    });
  });

  group('ad size and callbacks', () {
    Future<int> fetchAndGetViewId(WidgetTester tester, Widget app) async {
      await tester.pumpApp(app);
      h.platform.emitLoadState(h.platform.singleScopeId!, 'ad-a', AdLoadState.fetched);
      await tester.pump();
      return h.nativeViews.byViewId.keys.single;
    }

    Future<void> sendViewEvent(int viewId, String method, Object? args) async {
      final channel = MethodChannel('dk.stepnetwork.webadview_flutter/ad/$viewId');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    }

    testWidgets('onAdSize resizes the box with the SwiftUI clamping rule and re-reports geometry', (tester) async {
      final viewId = await fetchAndGetViewId(
        tester,
        LazyLoadAdScope(
          child: SingleChildScrollView(
            child: Column(children: const <Widget>[
              WebAdView(adUnitId: 'ad-a', maxWidth: 320, minHeight: 300),
            ]),
          ),
        ),
      );
      final reportsBefore = h.platform.geometry.length;
      await sendViewEvent(viewId, 'onAdSize', <String, Object?>{'width': 970, 'height': 250});
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(WebAdView)), const Size(320, 300));
      expect(h.platform.geometry.length, greaterThan(reportsBefore));
      expect(h.platform.geometry.last.ads['ad-a']!.creative.height, 300);
    });

    testWidgets('onActiveViewImpression and onViewabilityChange reach the widget callbacks', (tester) async {
      String? slot;
      ViewabilityUpdate? update;
      final viewId = await fetchAndGetViewId(
        tester,
        LazyLoadAdScope(
          child: SingleChildScrollView(
            child: Column(children: <Widget>[
              WebAdView(
                adUnitId: 'ad-a',
                onActiveViewImpression: (s) => slot = s,
                onViewabilityChange: (u) => update = u,
              ),
            ]),
          ),
        ),
      );
      await sendViewEvent(viewId, 'onActiveViewImpression', <String, Object?>{'slotId': 'ad-a'});
      h.platform.emitViewability(h.platform.singleScopeId!, sampleUpdate('ad-a', becameViewable: true));
      expect(slot, 'ad-a');
      expect(update?.becameViewable, isTrue);
    });

    test('AdViewChannel drops malformed sizes', () async {
      Size? size;
      final ch = AdViewChannel(7, onAdSize: (s) => size = s, onActiveViewImpression: (_) {});
      addTearDown(ch.dispose);
      final channel = const MethodChannel('dk.stepnetwork.webadview_flutter/ad/7');
      for (final args in <Object?>[null, <String, Object?>{'width': 0, 'height': 250}, <String, Object?>{'width': 'x'}]) {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(channel.name,
                channel.codec.encodeMethodCall(MethodCall('onAdSize', args)), (_) {});
      }
      expect(size, isNull);
    });
  });

  group('routes and keys', () {
    testWidgets('a covering opaque route hides the scope; popping shows it again', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpApp(Navigator(
        key: navigator,
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => twoAds(),
        ),
      ));
      expect(h.platform.calls, isNot(contains('setScopeVisible:false')));

      navigator.currentState!.push(PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SizedBox.expand(),
        transitionDuration: const Duration(milliseconds: 100),
      ));
      await tester.pumpAndSettle();
      expect(h.platform.calls, contains('setScopeVisible:false'));

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(h.platform.calls.last, isNot('setScopeVisible:false'));
      expect(h.platform.calls, contains('setScopeVisible:true'));
    });

    testWidgets('changing the key forces a new registration (the .id(adKey) reload)', (tester) async {
      Widget app(Key key) => LazyLoadAdScope(
            child: SingleChildScrollView(
              child: Column(children: <Widget>[WebAdView(key: key, adUnitId: 'ad-a')]),
            ),
          );
      await tester.pumpApp(app(const ValueKey<int>(1)));
      await tester.pumpApp(app(const ValueKey<int>(2)));
      // The new state registers before the old one is disposed; the old
      // state's unregister is ignored so the native ad stays registered.
      expect(h.platform.calls.where((c) => c == 'registerAd:ad-a').length, 2);
      expect(h.platform.calls, isNot(contains('unregisterAd:ad-a')));
      expect(h.platform.ads[h.platform.singleScopeId!], <String>{'ad-a'});
    });
  });

  group('integration errors', () {
    testWidgets('a WebAdView without a LazyLoadAdScope throws a descriptive error in debug', (tester) async {
      await tester.pumpApp(const WebAdView(adUnitId: 'ad-a'));
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('LazyLoadAdScope'));
    });

    testWidgets('unsupported platform renders the placeholder and never touches the channel', (tester) async {
      PlatformSupport.debugPlatformOverride = TargetPlatform.macOS;
      await tester.pumpApp(twoAds());
      expect(tester.getSize(find.byType(WebAdView).first), const Size(320, 320));
      expect(h.platform.calls, isEmpty);
    });
  });
}
