import 'package:flutter/material.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

import '../data/articles.dart';
import '../widgets/article_row.dart';
import '../widgets/ladybug_action.dart';
import '../config.dart';
import '../widgets/privacy_settings_button.dart';
import '../widgets/simulated_cmp_panel.dart';
import 'article_screen.dart';

/// NewsHub home — the Flutter twin of the SwiftUI demo's HomepageView:
/// four ad placements in a plain scroll column (the equivalent of
/// `ScrollView` + `VStack`: every ad exists from the start, so lazy loading
/// can fetch ahead), wrapped in the REQUIRED [LazyLoadAdScope].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('NewsHub'),
        actions: const <Widget>[LadybugAction()],
      ),
      body: LazyLoadAdScope(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header banner ad: fixed 320pt height, custom targeting,
              // Google's own viewable verdict logged.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: WebAdView(
                  adUnitId: 'div-gpt-ad-mobile_1',
                  initialHeight: 320,
                  minHeight: 320,
                  maxHeight: 320,
                  showAdLabel: true,
                  customTargeting: const <String, List<String>>{
                    'section': <String>['homepage'],
                    'tags': <String>['breaking', 'featured', 'local'],
                  },
                  onActiveViewImpression: (slotId) => debugPrint(
                      '[DEMO] 🟢 GPT ActiveView viewable impression (honest default): $slotId'),
                ),
              ),

              // Featured article
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('BREAKING NEWS',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                ArticleScreen(article: articles[0])),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.photo,
                                size: 64,
                                color: Colors.grey.withValues(alpha: 0.6)),
                          ),
                          const SizedBox(height: 8),
                          Text(articles[0].title,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(articles[0].summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Text('Tech News • ${articles[0].timeAgo}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.blue)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Second ad: the native viewability callback in action.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: WebAdView(
                  adUnitId: 'div-gpt-ad-mobile_2',
                  showAdLabel: true,
                  onViewabilityChange: (update) {
                    if (update.becameViewable) {
                      debugPrint(
                          '[DEMO] ${update.adUnitId} counted as a viewable impression (${update.mode.name})');
                    }
                  },
                  onActiveViewImpression: (slotId) => debugPrint(
                      '[DEMO] 🟢 GPT ActiveView viewable impression (honest default): $slotId'),
                ),
              ),
              const SizedBox(height: 24),

              // Latest news
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text('Latest News',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton(
                            onPressed: () {}, child: const Text('View All')),
                      ],
                    ),
                    ArticleRow(article: articles[1]),
                    ArticleRow(article: articles[2]),

                    // Banner ad between articles
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: WebAdView(
                          adUnitId: 'div-gpt-ad-mobile_3', showAdLabel: true),
                    ),

                    ArticleRow(article: articles[0]),
                    ArticleRow(article: articles[1]),
                    ArticleRow(article: articles[2]),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Footer ad — plain WebAdView: honest measurement by default.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: WebAdView(
                  adUnitId: 'div-gpt-ad-mobile_4',
                  showAdLabel: true,
                  onActiveViewImpression: (slotId) => debugPrint(
                      '[DEMO] 🟢 GPT ActiveView viewable impression (honest default): $slotId'),
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Mode 3 demo: the app's "own" consent platform.
                    if (DemoConfig.consentMode == DemoConsentMode.tcf) ...<Widget>[
                      const SimulatedCmpPanel(),
                      const SizedBox(height: 12),
                    ],
                    const PrivacySettingsButton(),
                    const SizedBox(height: 12),
                    Text('© 2025 News Demo App',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
