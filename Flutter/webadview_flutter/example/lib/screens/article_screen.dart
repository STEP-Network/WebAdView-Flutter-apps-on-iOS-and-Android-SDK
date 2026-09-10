import 'package:flutter/material.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

import '../data/articles.dart';

/// Article page: its own [LazyLoadAdScope] (one scope per screen, like
/// `.lazyLoadAd()` per `ScrollView`), with an ad between every paragraph
/// group. Pushing this route over the home screen also exercises the
/// "covered screen stops measuring" rule.
class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[
      // Header
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: article.categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(article.category,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: article.categoryColor,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(article.timeAgo,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Text(article.title,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(article.byline,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: article.categoryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(article.icon,
                  size: 80, color: article.categoryColor.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    ];

    // Same placements as the SwiftUI demo: article 1 puts its fixed-height
    // header ad (mobile_1) right after the image; the others put mobile_1
    // after the first paragraph group. Then one ad between each group, and
    // article 3 adds a fifth ad at the bottom.
    var nextAd = 1;
    if (article.id == 1) children.add(_ad(nextAd++));
    final sections = article.sections;
    for (var i = 0; i < sections.length; i++) {
      children.add(_section(theme, sections[i]));
      final isLast = i == sections.length - 1;
      if (!isLast || article.extraBottomAd) children.add(_ad(nextAd++));
    }
    children.add(const SizedBox(height: 24));

    return Scaffold(
      appBar: AppBar(title: Text(article.category.split(' ').first)),
      body: LazyLoadAdScope(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _ad(int index) {
    final id = 'div-gpt-ad-mobile_$index';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: index == 1
          ? WebAdView(
              adUnitId: id,
              initialHeight: 320,
              minHeight: 320,
              maxHeight: 320,
              showAdLabel: true,
            )
          : WebAdView(
              adUnitId: id,
              showAdLabel: true,
              adLabelText: 'artikel forsætter efter annonce',
            ),
    );
  }

  Widget _section(ThemeData theme, List<String> paragraphs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < paragraphs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                paragraphs[i],
                style: i == 0 && paragraphs.length > 1 && paragraphs[i].length < 40
                    ? theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)
                    : theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
