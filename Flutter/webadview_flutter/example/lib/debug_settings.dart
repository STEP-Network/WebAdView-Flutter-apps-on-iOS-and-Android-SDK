import 'package:flutter/foundation.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

/// Mirrors the SDK's persistent debug flag for the ladybug toggle.
class DebugSettings {
  DebugSettings._();

  static final DebugSettings instance = DebugSettings._();

  final ValueNotifier<bool> isDebugEnabled = ValueNotifier<bool>(false);

  Future<void> load() async {
    isDebugEnabled.value = await WebAdViewSdk.isDebugEnabled();
  }

  Future<void> toggle() async {
    final next = !isDebugEnabled.value;
    isDebugEnabled.value = next;
    await WebAdViewSdk.setDebugEnabled(next);
  }
}
