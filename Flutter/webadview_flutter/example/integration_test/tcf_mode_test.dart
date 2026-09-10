import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webadview_flutter/webadview_flutter.dart';
import 'package:webadview_flutter_example/config.dart';
import 'package:webadview_flutter_example/simulated_cmp.dart';

import 'consent_test_support.dart';

// Consent mode 3 (bring-your-own TCF CMP) end to end on a simulator/device.
// The example's simulated CMP writes real TC strings to the IABTCF keys, the
// SDK's TCFConsentProvider reads them — indistinguishable from Cookiebot,
// OneTrust or Usercentrics. Proves: no ad request without an answer, load on
// the answer, reload when the answer changes.
//
// Own-CMP modes need the own-CMP template (no consent web tag). Serve the
// reference template from the repository and point the test at it:
//
//   (cd Documentation && python3 -m http.server 8787 --bind 127.0.0.1 &)   # repo root
//   adb reverse tcp:8787 tcp:8787                                          # Android only
//   cd Flutter/webadview_flutter/example
//   T=http://127.0.0.1:8787/example-ad-template-own-cmp.html
//   flutter test integration_test/tcf_mode_test.dart -d "iPhone 17" --dart-define=SN_AD_TEMPLATE_URL=$T
//   flutter test integration_test/tcf_mode_test.dart -d emulator-5554 --dart-define=SN_AD_TEMPLATE_URL=$T

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  requireOwnCmpTemplate();

  testWidgets('own TCF CMP: ads wait, load on the answer, reload on change',
      (tester) async {
    // A fresh install has no answer; make sure of it either way.
    await SimulatedCmp.clear();
    expect(await SimulatedCmp.read(), isNull);

    await WebAdViewSdk.initialize(
        WebAdViewSdkConfig.tcf(adTemplateUrl: Uri.parse(DemoConfig.adTemplateUrl)));
    expect(WebAdViewSdk.isInitialized, isTrue);
    await WebAdViewSdk.setDebugEnabled(true);

    final signals = await pumpAdHarness(tester, section: 'tcf-mode-test');

    // 1. No answer → the gate stays closed: nothing may be requested. In mode 1
    //    Google's verdict arrives within ~5 s of consent, so 15 s of silence is
    //    a meaningful negative.
    await holdFor(tester, const Duration(seconds: 15));
    expect(signals.hasImpression, isFalse,
        reason: 'no ad may be requested before the CMP has an answer');

    // 2. The user accepts in the (simulated) CMP → the SDK sees the TC string
    //    and loads; the creative renders and Google counts it.
    final latchesAtAccept = signals.latchCount; // the placeholder may already have latched
    await SimulatedCmp.answer(accept: true);
    await waitUntil(tester, () => signals.hasImpression, const Duration(seconds: 60),
        'Google impression after accept');
    final firstSlot = signals.firstSlot!;
    expect(firstSlot, startsWith('div-gpt-ad-mobile_1'));
    // The load re-armed the native impression: a fresh latch must follow.
    await waitUntil(tester, () => signals.latchCount > latchesAtAccept,
        const Duration(seconds: 10), 'native viewable latch after the load');
    await holdFor(tester, const Duration(seconds: 3)); // let the load settle
    final latchesBefore = signals.latchCount;
    debugPrint('[TCF-TEST] loaded after accept: $firstSlot');

    // 3. The user changes their mind → the SDK reloads the ad page with the
    //    new consent (new Yield Manager slot instance id).
    await SimulatedCmp.answer(accept: false);
    await waitUntil(tester, () => signals.latchCount > latchesBefore,
        const Duration(seconds: 60), 'reload after the consent change (new native impression)');
    debugPrint('[TCF-TEST] reloaded after decline: latches=${signals.latchCount}, impressions=${signals.impressions.length}');
  });
}
