import 'package:flutter/material.dart';

import '../simulated_cmp.dart';

/// Demo control for consent mode 3: lets you play the user's answer in the
/// app's "own" consent platform and watch the ads react (wait → load →
/// reload). Shown only when the demo runs with `SN_CONSENT_MODE=tcf`.
class SimulatedCmpPanel extends StatefulWidget {
  const SimulatedCmpPanel({super.key});

  @override
  State<SimulatedCmpPanel> createState() => _SimulatedCmpPanelState();
}

class _SimulatedCmpPanelState extends State<SimulatedCmpPanel> {
  String _status = '…';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final tc = await SimulatedCmp.read();
    if (!mounted) return;
    setState(() {
      _status = tc == null || tc.isEmpty
          ? 'no answer stored — ads are waiting'
          : 'TC string stored (${tc.length} chars): ${tc.substring(0, 16)}…';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Simulated consent platform (demo)',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Plays the role of your own TCF CMP: writes a real TC string to '
              'the standard IABTCF keys. The ad SDK only reads them.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(_status, style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: () => _run(() => SimulatedCmp.answer(accept: true)),
                  child: const Text('Accept all'),
                ),
                OutlinedButton(
                  onPressed: () => _run(() => SimulatedCmp.answer(accept: false)),
                  child: const Text('Decline all'),
                ),
                TextButton(
                  onPressed: () => _run(SimulatedCmp.clear),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
