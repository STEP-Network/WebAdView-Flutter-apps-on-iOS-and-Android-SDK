# NewsHub — the webadview_flutter example

A small news-feed app that integrates the plugin exactly as a publisher
would: `WebAdViewSdk.initialize` in `main.dart`, a `LazyLoadAdScope` around
each scrollable screen, and a `WebAdView` per ad placement (four on the
home screen, one inside each article). The ladybug button in the app bar
toggles the SDK's debug logging; "Privacy Settings" reopens the consent
choices.

It runs against STEP Network's demo Didomi key and test template
(`lib/config.dart`) — test values only.

```bash
flutter run -d "iPhone 17" --dart-define=SN_CONSENT_ACCEPT_ALL=true      # iOS simulator
flutter run -d emulator-5554 --dart-define=SN_CONSENT_ACCEPT_ALL=true    # Android emulator
flutter test integration_test/smoke_test.dart -d <device>                # end-to-end
```

Consent modes 2 and 3 (`--dart-define=SN_CONSENT_MODE=appDidomi|tcf`) need
the own-CMP template served locally; the commands, the simulated consent
platform card and the matching integration tests are described in the
plugin README, section 9: [../README.md](../README.md#9-run-the-example).

Platform notes: iOS deployment target 16.0; `MainActivity` extends
`FlutterFragmentActivity`; `ios/Runner/Info.plist` allows local networking
and the debug manifest allows cleartext http **for the local template
only** — do not copy those into a real app.
