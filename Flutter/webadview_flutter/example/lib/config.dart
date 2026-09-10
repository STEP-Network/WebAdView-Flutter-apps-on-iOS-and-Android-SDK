import 'package:webadview_flutter/webadview_flutter.dart';

/// Demo configuration, overridable with `--dart-define`:
///
/// ```
/// flutter run --dart-define=SN_DIDOMI_API_KEY=… \
///             --dart-define=SN_AD_TEMPLATE_URL=https://your-domain/ad-template.html \
///             --dart-define=SN_CONSENT_MODE=didomi|tcf|appDidomi \
///             --dart-define=SN_CONSENT_ACCEPT_ALL=true
/// ```
///
/// The defaults are STEP Network's demo key and test template (the same
/// values as the SwiftUI demo app). Never ship them in a real app.
abstract final class DemoConfig {
  static const String didomiApiKey = String.fromEnvironment(
    'SN_DIDOMI_API_KEY',
    defaultValue: 'd0661bea-d696-4069-b308-11057215c4c4',
  );

  static const String adTemplateUrl = String.fromEnvironment(
    'SN_AD_TEMPLATE_URL',
    defaultValue:
        'https://adops.stepdev.dk/wp-content/ad-template.html?didomi-disable-notice=true',
  );

  static const bool acceptAllConsent =
      bool.fromEnvironment('SN_CONSENT_ACCEPT_ALL', defaultValue: false);

  /// Which of the SDK's three consent modes the demo runs in:
  ///
  /// - `didomi` (default): the SDK owns Didomi and shows the notice.
  /// - `tcf`: the app "owns" a TCF CMP — played here by the demo's
  ///   simulated CMP, which writes real TC strings to the IABTCF keys.
  /// - `appDidomi`: the app owns Didomi through the `didomi_sdk` plugin.
  static const String _consentModeName =
      String.fromEnvironment('SN_CONSENT_MODE', defaultValue: 'didomi');

  static DemoConsentMode get consentMode => switch (_consentModeName) {
        'tcf' => DemoConsentMode.tcf,
        'appDidomi' => DemoConsentMode.appDidomi,
        _ => DemoConsentMode.didomi,
      };

  /// The SDK configuration for [consentMode]. Only mode 1 needs the key.
  static WebAdViewSdkConfig sdkConfig() {
    final template = Uri.parse(adTemplateUrl);
    return switch (consentMode) {
      DemoConsentMode.didomi =>
        WebAdViewSdkConfig.didomi(apiKey: didomiApiKey, adTemplateUrl: template),
      DemoConsentMode.tcf => WebAdViewSdkConfig.tcf(adTemplateUrl: template),
      DemoConsentMode.appDidomi =>
        WebAdViewSdkConfig.appDidomi(adTemplateUrl: template),
    };
  }
}

enum DemoConsentMode { didomi, tcf, appDidomi }
