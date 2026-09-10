import 'package:didomi_sdk/didomi_sdk.dart';
import 'package:didomi_sdk/parameters/didomi_initialize_parameters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'debug_settings.dart';
import 'simulated_cmp.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mode 2 only (SN_CONSENT_MODE=appDidomi): the APP owns Didomi, exactly as
  // a publisher using Didomi's own Flutter plugin would. It initialises
  // Didomi and shows the notice itself; the ad SDK never touches Didomi's
  // setup, it only asks "has the user answered?".
  if (DemoConfig.consentMode == DemoConsentMode.appDidomi) {
    DidomiSdk.onReady(() {
      DidomiSdk.setupUI();
      if (kDebugMode && DemoConfig.acceptAllConsent) {
        DidomiSdk.setUserAgreeToAll();
      }
    });
    await DidomiSdk.initializeWithParameters(
        DidomiInitializeParameters(apiKey: DemoConfig.didomiApiKey));
  }

  // One call configures the native SDK. The demo key and STEP Network's test
  // template URL are the defaults in config.dart on purpose — real apps
  // inject their own values with --dart-define (see README.md).
  await WebAdViewSdk.initialize(DemoConfig.sdkConfig());

  // Test-automation hook: a fresh install wipes stored consent, so automated
  // simulator runs would hold ads back forever. Debug builds only:
  //   flutter run --dart-define=SN_CONSENT_ACCEPT_ALL=true
  if (kDebugMode && DemoConfig.acceptAllConsent) {
    switch (DemoConfig.consentMode) {
      case DemoConsentMode.didomi:
        await WebAdViewSdk.acceptAllConsentForTesting();
      case DemoConsentMode.tcf:
        await SimulatedCmp.answer(accept: true);
      case DemoConsentMode.appDidomi:
        break; // handled in the onReady callback above
    }
  }

  await DebugSettings.instance.load();
  runApp(const NewsHubApp());
}
