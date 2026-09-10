import 'package:flutter/foundation.dart';

/// Where the user's consent answer comes from (mirrors the SDK's
/// `ConsentProvider` choices).
enum ConsentMode {
  /// Standard mode: the SDK owns Didomi — initialization, the consent
  /// notice on first launch, and the consent hand-off to the ad page.
  didomi,

  /// Bring-your-own-CMP: your app already runs a TCF-certified CMP
  /// (Cookiebot, OneTrust, Usercentrics, …). The SDK shows no consent UI and
  /// reads the answer from the standard `IABTCF_*` storage.
  tcf,

  /// Your app runs its own Didomi (for example through the `didomi_sdk`
  /// Flutter plugin). The SDK asks Didomi directly whether the user has
  /// answered, and hands consent to the page via the `__tcfapi` stub.
  appDidomi;

  String get wireName => name;
}

/// App-level configuration for [WebAdViewSdk.initialize] (mirrors the SDK's
/// `WebAdViewSDKConfig`). Both values come from your STEP Network
/// onboarding. Do not commit real keys — inject them with `--dart-define`.
@immutable
class WebAdViewSdkConfig {
  const WebAdViewSdkConfig._({
    required this.mode,
    required this.adTemplateUrl,
    this.didomiApiKey,
    this.didomiDisableRemoteConfig = false,
  });

  /// Standard mode (SDK-owned Didomi).
  const WebAdViewSdkConfig.didomi({
    required String apiKey,
    required Uri adTemplateUrl,
    bool disableRemoteConfig = false,
  }) : this._(
          mode: ConsentMode.didomi,
          adTemplateUrl: adTemplateUrl,
          didomiApiKey: apiKey,
          didomiDisableRemoteConfig: disableRemoteConfig,
        );

  /// Bring-your-own TCF CMP.
  const WebAdViewSdkConfig.tcf({required Uri adTemplateUrl})
      : this._(mode: ConsentMode.tcf, adTemplateUrl: adTemplateUrl);

  /// App-owned Didomi.
  const WebAdViewSdkConfig.appDidomi({required Uri adTemplateUrl})
      : this._(mode: ConsentMode.appDidomi, adTemplateUrl: adTemplateUrl);

  final ConsentMode mode;

  /// The ad template page every ad webview loads — hosted on your own
  /// domain, built to `Documentation/bridge-contract.md`.
  final Uri adTemplateUrl;

  /// Didomi API key (standard mode only).
  final String? didomiApiKey;

  /// Advanced: leave `false` unless STEP Network says otherwise.
  final bool didomiDisableRemoteConfig;

  Map<String, Object?> toChannelMap() => <String, Object?>{
        'mode': mode.wireName,
        'adTemplateUrl': adTemplateUrl.toString(),
        if (didomiApiKey != null) 'didomiApiKey': didomiApiKey,
        'didomiDisableRemoteConfig': didomiDisableRemoteConfig,
      };
}
