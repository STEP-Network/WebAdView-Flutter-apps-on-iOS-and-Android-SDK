import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webadview_flutter/src/platform/platform_support.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

import 'support/fake_platform.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.tearDown());

  final config = WebAdViewSdkConfig.didomi(
      apiKey: 'k', adTemplateUrl: Uri.parse('https://pub.example/ad.html'));

  test('initialize configures the native SDK once; a second call is ignored', () async {
    expect(WebAdViewSdk.isInitialized, isFalse);
    await WebAdViewSdk.initialize(config);
    expect(WebAdViewSdk.isInitialized, isTrue);
    expect(h.platform.lastConfig, same(config));

    await WebAdViewSdk.initialize(config);
    expect(h.platform.calls.where((c) => c == 'initialize').length, 1);
  });

  test('a native side that is already initialized (hot restart) counts as initialized', () async {
    h.platform.alreadyInitialized = true;
    await WebAdViewSdk.initialize(config);
    expect(WebAdViewSdk.isInitialized, isTrue);
  });

  test('a rejected native configuration leaves the SDK uninitialized and is logged loudly', () async {
    h.platform.initializeError = 'activity_not_fragment: The Didomi consent notice needs a FragmentActivity';
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    try {
      await WebAdViewSdk.initialize(config);
    } finally {
      debugPrint = original;
    }
    expect(WebAdViewSdk.isInitialized, isFalse);
    expect(printed.where((m) => m.contains('[SN] [ERROR]') && m.contains('activity_not_fragment')), hasLength(1));
    // A later, corrected call may still succeed.
    h.platform.initializeError = null;
    await WebAdViewSdk.initialize(config);
    expect(WebAdViewSdk.isInitialized, isTrue);
  });

  test('the debug flag round-trips and mirrors into Dart logging', () async {
    await WebAdViewSdk.setDebugEnabled(true);
    expect(h.platform.debugEnabled, isTrue);
    expect(await WebAdViewSdk.isDebugEnabled(), isTrue);
  });

  test('unsupported platform: every call is a no-op and nothing is sent', () async {
    PlatformSupport.debugPlatformOverride = TargetPlatform.macOS;
    expect(WebAdViewSdk.isSupported, isFalse);
    await WebAdViewSdk.initialize(config);
    await WebAdViewSdk.showConsentPreferences();
    await WebAdViewSdk.acceptAllConsentForTesting();
    expect(WebAdViewSdk.isInitialized, isFalse);
    expect(h.platform.calls, isEmpty);
  });
}
