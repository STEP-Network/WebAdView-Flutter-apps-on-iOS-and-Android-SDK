import 'package:flutter/material.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

/// Reopens the Didomi preferences so users can change their consent.
class PrivacySettingsButton extends StatelessWidget {
  const PrivacySettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: WebAdViewSdk.showConsentPreferences,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.shield_outlined),
              SizedBox(width: 12),
              Text('Privacy Settings'),
              Spacer(),
              Icon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
