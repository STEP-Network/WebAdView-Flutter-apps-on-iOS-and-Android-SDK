import 'dart:async';

import 'package:didomi_sdk/didomi_sdk.dart';
import 'package:didomi_sdk/parameters/didomi_initialize_parameters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webadview_flutter/webadview_flutter.dart';
import 'package:webadview_flutter_example/config.dart';

import 'consent_test_support.dart';

// Consent mode 2 (app-owned Didomi) end to end on a simulator/device. The
// APP initialises Didomi through Didomi's own Flutter plugin, exactly as a
// publisher would; the ad SDK only asks Didomi whether the user has
// answered. Proves: no ad request while the status is partial, load once
// the user answers, reload when the answer changes.
//
// Own-CMP modes need the own-CMP template (no consent web tag). Serve the
// reference template from the repository and point the test at it:
//
//   (cd Documentation && python3 -m http.server 8787 --bind 127.0.0.1 &)   # repo root
//   adb reverse tcp:8787 tcp:8787                                          # Android only
//   cd Flutter/webadview_flutter/example
//   T=http://127.0.0.1:8787/example-ad-template-own-cmp.html
//   flutter test integration_test/app_didomi_mode_test.dart -d "iPhone 17" --dart-define=SN_AD_TEMPLATE_URL=$T
//   flutter test integration_test/app_didomi_mode_test.dart -d emulator-5554 --dart-define=SN_AD_TEMPLATE_URL=$T

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  requireOwnCmpTemplate();

  testWidgets('app-owned Didomi: ads wait, load on the answer, reload on change',
      (tester) async {
    final ready = Completer<void>();
    DidomiSdk.onReady(() {
      if (!ready.isCompleted) ready.complete();
    });
    await DidomiSdk.initializeWithParameters(
        DidomiInitializeParameters(apiKey: DemoConfig.didomiApiKey));

    await WebAdViewSdk.initialize(
        WebAdViewSdkConfig.appDidomi(adTemplateUrl: Uri.parse(DemoConfig.adTemplateUrl)));
    expect(WebAdViewSdk.isInitialized, isTrue);
    await WebAdViewSdk.setDebugEnabled(true);

    final signals = await pumpAdHarness(tester, section: 'app-didomi-mode-test');

    await waitUntil(tester, () => ready.isCompleted, const Duration(seconds: 30), 'Didomi ready');
    // Forget any stored answer so the status is "partial" — the notice has
    // not been answered — regardless of what an earlier run left behind.
    await DidomiSdk.reset();
    expect(await DidomiSdk.isUserStatusPartial, isTrue);

    // 1. Unanswered notice → the gate stays closed.
    await holdFor(tester, const Duration(seconds: 15));
    expect(signals.hasImpression, isFalse,
        reason: 'no ad may be requested before the user answers the app\'s Didomi notice');

    // 2. The user accepts (through the app's Didomi) → the SDK loads.
    final latchesAtAccept = signals.latchCount; // the placeholder may already have latched
    await DidomiSdk.setUserAgreeToAll();
    await waitUntil(tester, () => signals.hasImpression, const Duration(seconds: 60),
        'Google impression after accept');
    final firstSlot = signals.firstSlot!;
    expect(firstSlot, startsWith('div-gpt-ad-mobile_1'));
    // The load re-armed the native impression: a fresh latch must follow.
    await waitUntil(tester, () => signals.latchCount > latchesAtAccept,
        const Duration(seconds: 10), 'native viewable latch after the load');
    await holdFor(tester, const Duration(seconds: 3)); // let the load settle
    final latchesBefore = signals.latchCount;
    debugPrint('[APP-DIDOMI-TEST] loaded after accept: $firstSlot');

    // 3. The user changes their mind → reload with the new consent.
    await DidomiSdk.setUserDisagreeToAll();
    await waitUntil(tester, () => signals.latchCount > latchesBefore,
        const Duration(seconds: 60), 'reload after the consent change (new native impression)');
    debugPrint('[APP-DIDOMI-TEST] reloaded after decline: latches=${signals.latchCount}, impressions=${signals.impressions.length}');
  });
}
