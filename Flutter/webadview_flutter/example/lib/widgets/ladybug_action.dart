import 'package:flutter/material.dart';

import '../debug_settings.dart';

/// The demo's hidden developer control: toggles the SDK's runtime debug flag
/// (logging, in-ad debug panel, Yield Manager debug mode).
class LadybugAction extends StatelessWidget {
  const LadybugAction({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugSettings.instance.isDebugEnabled,
      builder: (context, enabled, _) => IconButton(
        tooltip: 'Toggle Debug Mode',
        icon: Icon(
          enabled ? Icons.bug_report : Icons.bug_report_outlined,
          color: enabled ? Colors.red : null,
        ),
        onPressed: DebugSettings.instance.toggle,
      ),
    );
  }
}
