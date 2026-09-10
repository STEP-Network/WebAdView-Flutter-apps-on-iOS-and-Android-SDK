import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webadview_flutter/src/logging.dart';
import 'package:webadview_flutter/src/platform/platform_support.dart';
import 'package:webadview_flutter/src/platform/webadview_platform.dart';
import 'package:webadview_flutter/src/scope/scope_registry.dart';
import 'package:webadview_flutter/src/widgets/native_ad_view.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

/// Records every Dart → native call and lets tests emit native → Dart events.
class FakeWebAdViewPlatform extends WebAdViewPlatform {
  final List<String> calls = <String>[];
  final List<({String scopeId, Rect viewport, Map<String, AdGeometry> ads})>
      geometry = <({String scopeId, Rect viewport, Map<String, AdGeometry> ads})>[];
  final Set<String> scopes = <String>{};
  final Map<String, Set<String>> ads = <String, Set<String>>{};
  final Map<String, bool> scopeVisible = <String, bool>{};
  bool alreadyInitialized = false;
  String? initializeError;
  WebAdViewSdkConfig? lastConfig;
  bool debugEnabled = false;

  String? get singleScopeId => scopes.length == 1 ? scopes.single : null;

  @override
  Future<InitializeResult> initialize(WebAdViewSdkConfig config) async {
    calls.add('initialize');
    lastConfig = config;
    return InitializeResult(alreadyInitialized: alreadyInitialized, error: initializeError);
  }

  @override
  Future<void> showConsentPreferences() async => calls.add('showConsentPreferences');

  @override
  Future<void> setDebugEnabled(bool enabled) async {
    calls.add('setDebugEnabled:$enabled');
    debugEnabled = enabled;
  }

  @override
  Future<bool> isDebugEnabled() async => debugEnabled;

  @override
  Future<void> acceptAllConsentForTesting() async => calls.add('acceptAll');

  @override
  Future<void> createScope(String scopeId, LazyLoadConfig config) async {
    calls.add('createScope');
    scopes.add(scopeId);
    ads[scopeId] = <String>{};
  }

  @override
  Future<void> disposeScope(String scopeId) async {
    calls.add('disposeScope');
    scopes.remove(scopeId);
    ads.remove(scopeId);
  }

  @override
  Future<void> setScopeVisible(String scopeId, bool visible) async {
    calls.add('setScopeVisible:$visible');
    scopeVisible[scopeId] = visible;
  }

  @override
  Future<void> registerAd(String scopeId, String adUnitId) async {
    calls.add('registerAd:$adUnitId');
    ads[scopeId]?.add(adUnitId);
  }

  @override
  Future<void> unregisterAd(String scopeId, String adUnitId) async {
    calls.add('unregisterAd:$adUnitId');
    ads[scopeId]?.remove(adUnitId);
  }

  @override
  Future<void> updateGeometry(
      String scopeId, Rect viewport, Map<String, AdGeometry> ads) async {
    calls.add('updateGeometry');
    geometry.add((scopeId: scopeId, viewport: viewport, ads: ads));
  }

  // ---- native → Dart -------------------------------------------------------

  void emitLoadState(String scopeId, String adUnitId, AdLoadState state) {
    listener?.onLoadState(scopeId, adUnitId, state);
  }

  void emitViewability(String scopeId, ViewabilityUpdate update) {
    listener?.onViewability(scopeId, update);
  }
}

/// Fake native ad view + the per-view channel hooks the widget attaches.
class FakeNativeAdViews {
  final List<NativeAdViewParams> created = <NativeAdViewParams>[];
  int _nextViewId = 100;
  final Map<int, NativeAdViewParams> byViewId = <int, NativeAdViewParams>{};

  Widget build(NativeAdViewParams params, void Function(int viewId) onCreated) {
    return _FakeNativeView(

      onMounted: () {
        final id = _nextViewId++;
        created.add(params);
        byViewId[id] = params;
        onCreated(id);
      },
    );
  }
}

class _FakeNativeView extends StatefulWidget {
  const _FakeNativeView({required this.onMounted});
  final VoidCallback onMounted;

  @override
  State<_FakeNativeView> createState() => _FakeNativeViewState();
}

class _FakeNativeViewState extends State<_FakeNativeView> {
  @override
  void initState() {
    super.initState();
    widget.onMounted();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('fake-native-ad'), color: Color(0xFF00FF00));
}

/// Standard per-test setup: iOS platform, fake channel, fake native views.
class TestHarness {
  TestHarness() {
    PlatformSupport.resetForTesting();
    PlatformSupport.debugPlatformOverride = TargetPlatform.iOS;
    ScopeRegistry.instance.resetForTesting();
    SnLog.resetForTesting();
    WebAdViewSdk.resetForTesting();
    platform = FakeWebAdViewPlatform();
    WebAdViewPlatform.instance = platform;
    nativeViews = FakeNativeAdViews();
    NativeAdView.debugBuilder = nativeViews.build;
  }

  late final FakeWebAdViewPlatform platform;
  late final FakeNativeAdViews nativeViews;

  void tearDown() {
    NativeAdView.debugBuilder = null;
    PlatformSupport.resetForTesting();
  }
}

ViewabilityUpdate sampleUpdate(String adUnitId, {bool becameViewable = false}) {
  return ViewabilityUpdate(
    adUnitId: adUnitId,
    ratio: 1,
    isVisible: true,
    dwell: 1.1,
    mode: ViewabilityMode.display,
    isViewable: becameViewable,
    becameViewable: becameViewable,
    isAppActive: true,
    timestamp: 1000,
  );
}

extension WidgetTesterX on WidgetTester {
  Future<void> pumpApp(Widget child, {Size size = const Size(400, 800)}) async {
    view.physicalSize = size;
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
    await pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: child,
      ),
    ));
  }
}
