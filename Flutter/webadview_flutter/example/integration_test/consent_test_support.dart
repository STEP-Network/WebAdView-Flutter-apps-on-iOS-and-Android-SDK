import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webadview_flutter/webadview_flutter.dart';
import 'package:webadview_flutter_example/config.dart';

/// Shared harness for the consent-mode integration tests: one ad in a
/// scrollable, fully on screen, with every signal the Dart API exposes
/// captured. The definitive "an ad was requested, rendered and seen" signal
/// is Google's own Active View verdict ([WebAdView.onActiveViewImpression]);
/// the native latch is a second, independent signal (it only counts once the
/// creative has rendered).
///
/// A RELOAD is proven by a second native viewable latch: the SDK re-arms
/// the impression only when it (re)loads the ad page — never on a timed
/// GPT refresh inside the page — and the harness keeps the ad fully on
/// screen, so a new latch can only follow a new page load.
class AdSignals {
  final List<String> impressions = <String>[];
  final List<ViewabilityUpdate> latches = <ViewabilityUpdate>[];

  String? get firstSlot => impressions.isEmpty ? null : impressions.first;

  bool get hasImpression => impressions.isNotEmpty;

  int get latchCount => latches.length;
}

Future<AdSignals> pumpAdHarness(WidgetTester tester, {required String section}) async {
  final signals = AdSignals();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: Text('consent · $section')),
      body: LazyLoadAdScope(
        child: SingleChildScrollView(
          // Stretch, as a real screen does: a column of fixed-width children
          // would shrink-wrap to 320 and sit at the left of the Scaffold body.
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            WebAdView(
              adUnitId: 'div-gpt-ad-mobile_1',
              showAdLabel: true,
              customTargeting: <String, List<String>>{
                'section': <String>[section],
              },
              onViewabilityChange: (u) {
                if (u.becameViewable) signals.latches.add(u);
              },
              onActiveViewImpression: signals.impressions.add,
            ),
            const SizedBox(height: 2000),
          ]),
        ),
      ),
    ),
  ));
  return signals;
}

/// Lets real time pass while keeping the widget tree pumped. Everything
/// under test (native tickers, page loads, Google's Active View) runs on
/// wall-clock time.
Future<void> holdFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump();
  }
}

Future<void> waitUntil(
  WidgetTester tester,
  bool Function() condition,
  Duration timeout,
  String what,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump();
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $what');
}

/// The own-CMP tests are meaningless against the hosted standard-mode
/// template: it loads Didomi's web tag, which overrides the SDK's `__tcfapi`
/// hand-off. Fail fast with the fix instead of timing out 60 s later.
void requireOwnCmpTemplate() {
  final url = DemoConfig.adTemplateUrl;
  if (!url.contains('own-cmp')) {
    throw StateError(
      'Own-CMP consent tests need the own-CMP ad template. Run with '
      '--dart-define=SN_AD_TEMPLATE_URL=http://127.0.0.1:8787/example-ad-template-own-cmp.html '
      '(serve Documentation/ with `python3 -m http.server 8787`; on Android also '
      '`adb reverse tcp:8787 tcp:8787`). Current template: $url',
    );
  }
}
