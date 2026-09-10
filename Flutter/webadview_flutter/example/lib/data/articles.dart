import 'package:flutter/material.dart';

/// Demo content (same articles as the SwiftUI demo app).
class Article {
  const Article({
    required this.id,
    required this.category,
    required this.categoryColor,
    required this.title,
    required this.summary,
    required this.byline,
    required this.timeAgo,
    required this.icon,
    required this.sections,
    this.extraBottomAd = false,
  });

  final int id;
  final String category;
  final Color categoryColor;
  final String title;
  final String summary;
  final String byline;
  final String timeAgo;
  final IconData icon;

  /// Paragraph groups; an ad is placed between consecutive groups.
  final List<List<String>> sections;

  /// Article 3 has a fifth ad at the very bottom.
  final bool extraBottomAd;
}

const List<Article> articles = <Article>[
  Article(
    id: 1,
    category: 'TECH NEWS',
    categoryColor: Colors.blue,
    title:
        'Major Tech Breakthrough Changes Everything We Know About Mobile Advertising',
    summary:
        'Industry experts are calling this the most significant advancement in digital advertising technology in over a decade. The implications could reshape how we interact with mobile content...',
    byline: 'By Sarah Johnson • Tech Reporter',
    timeAgo: '2 hours ago',
    icon: Icons.smartphone,
    sections: <List<String>>[
      <String>[
        'In a groundbreaking development that promises to reshape the mobile advertising landscape, researchers at leading technology companies have unveiled revolutionary techniques that could transform how users interact with digital content on their devices.',
        'The new approach, which has been in development for over three years, addresses longstanding concerns about user experience while maintaining the economic viability of free, ad-supported mobile applications and websites.',
        'The breakthrough emerged from a collaboration between Silicon Valley giants, European privacy advocates, and academic institutions worldwide. Dr. Rebecca Thomson, lead researcher at the Digital Advertising Research Consortium, explained that the project began in 2021 when user complaints about intrusive advertising reached an all-time high.',
        '"We realized that the traditional model of advertising was fundamentally broken," Dr. Thomson said. "Users were becoming increasingly frustrated with ads that felt invasive, while advertisers were struggling to reach their intended audiences effectively. We needed a complete paradigm shift."',
      ],
      <String>[
        'Industry Impact',
        'Leading technology executives are praising the innovation, with many predicting widespread adoption across the industry within the next 18 months. The breakthrough addresses critical challenges that have plagued mobile advertising for years.',
        'The technology\'s development required overcoming significant technical hurdles. Traditional advertising systems rely heavily on third-party cookies and cross-site tracking, which have become increasingly problematic due to privacy regulations like GDPR and CCPA. The new approach eliminates these dependencies entirely.',
        'Early testing has shown remarkable improvements across all key performance indicators. Ad load times have decreased by an average of 67%, while click-through rates have increased by 43%. Perhaps most importantly, user satisfaction scores have improved by 89% in test environments.',
      ],
      <String>[
        'Market Implications',
        'Financial analysts predict the technology could reshape the entire digital advertising ecosystem, which currently represents a \$500 billion global market. Companies that adopt the new approach early are expected to gain significant competitive advantages.',
        'The technology is expected to begin rolling out to select partners in the coming months, with broader availability anticipated by the end of the year. Industry analysts suggest this could mark a turning point in how mobile content is monetized and consumed.',
        'For developers, implementing the new technology requires minimal changes to existing codebases. The system is designed to work as a drop-in replacement for current advertising SDKs, with comprehensive documentation and migration tools already available.',
      ],
      <String>[
        'Looking Forward',
        'As the advertising industry prepares for this significant shift, attention is turning to the long-term implications for digital content creation and consumption. Publishers are already reporting increased user engagement and longer session times in test environments.',
        'Industry experts agree that this breakthrough represents just the beginning of a new era in digital advertising – one that prioritizes user experience without sacrificing the economic models that support free content on the internet.',
      ],
    ],
  ),
  Article(
    id: 2,
    category: 'ENVIRONMENT',
    categoryColor: Colors.green,
    title: 'Climate Summit Reaches Historic Agreement on Carbon Emissions',
    summary:
        'World leaders unite on ambitious new targets that could transform global energy policies...',
    byline: 'By Michael Chen • Environmental Correspondent',
    timeAgo: '4 hours ago',
    icon: Icons.eco,
    sections: <List<String>>[
      <String>[
        'World leaders have reached a unprecedented consensus on ambitious carbon emission reduction targets at this year\'s Global Climate Summit, marking what many consider the most significant environmental agreement since the Paris Climate Accord.',
        'The agreement, signed by representatives from 195 countries, establishes binding commitments to reduce global carbon emissions by 60% by 2035, with interim targets of 30% by 2030.',
        'The negotiations, which lasted 72 hours straight in the final phase, were described by veteran diplomats as the most intense environmental discussions in decades.',
      ],
      <String>[
        'Summit Highlights',
        'Renewable Energy Transition — commitment to 80% renewable energy by 2040.',
        'Carbon Pricing Mechanism — global carbon tax framework implementation.',
        'Technology Sharing Initiative — open access to clean technology patents.',
      ],
      <String>[
        'Scientific Foundation',
        'The agreement is built upon the latest climate science, including alarming new data from the Intergovernmental Panel on Climate Change showing that global temperatures could rise by 2.8°C by 2100 without immediate action.',
        '"The window for limiting warming to 1.5°C is rapidly closing," Dr. Sharma explained during the summit. "Without the commitments made here today, we would be looking at catastrophic climate impacts within our children\'s lifetimes."',
        'The climate agreement is expected to trigger the largest economic transformation since the Industrial Revolution. Economists estimate that implementing the targets will require global investments of \$4.2 trillion annually through 2035.',
      ],
      <String>[
        'Industry Response',
        'Major corporations have begun announcing massive clean energy investments within hours of the agreement\'s signing.',
        'Implementation begins immediately, with the first major milestone set for 2027. Industry leaders are already announcing substantial investments in clean technology and renewable energy infrastructure in response to the new framework.',
      ],
    ],
  ),
  Article(
    id: 3,
    category: 'SCIENCE',
    categoryColor: Colors.purple,
    title: 'Space Mission Discovers Potentially Habitable Exoplanet',
    summary:
        'Scientists celebrate groundbreaking discovery that could change our understanding of life beyond Earth...',
    byline: 'By Dr. Amanda Foster • Space Science Editor',
    timeAgo: '6 hours ago',
    icon: Icons.public,
    extraBottomAd: true,
    sections: <List<String>>[
      <String>[
        'In a discovery that could fundamentally change our understanding of life beyond Earth, the Kepler Space Observatory has identified an exoplanet with conditions remarkably similar to our own planet, located just 22 light-years away in the constellation Lyra.',
        'The planet, designated Kepler-442c, orbits within the habitable zone of its host star and shows strong indicators of having liquid water on its surface—a key requirement for life as we know it.',
        'The team spent eight months verifying their findings through independent observations and peer review.',
      ],
      <String>[
        'Discovery Details',
        'Planet size: 1.34 × Earth. Surface temperature: 15°C average. Orbital period: 267 Earth days. Distance: 22.1 light-years.',
      ],
      <String>[
        'Atmospheric Analysis',
        'What makes Kepler-442c particularly extraordinary is its atmospheric composition. Advanced spectroscopic analysis has revealed the presence of water vapor, oxygen, methane, and phosphine – a combination that, on Earth, is almost exclusively associated with biological processes.',
        '"This discovery represents one of the most Earth-like planets we\'ve ever found," said Dr. James Wilson, lead researcher on the Kepler mission team.',
      ],
      <String>[
        'Geological Indicators',
        'Thermal imaging has revealed large bodies of liquid on the planet\'s surface, with temperatures and reflectivity patterns consistent with water oceans. These oceans appear to cover approximately 68% of the planet\'s surface.',
        'The James Webb Space Telescope will now turn its attention to Kepler-442c for more detailed observations.',
      ],
      <String>[
        'Technological Implications',
        'The discovery has prompted renewed interest in interstellar travel concepts. While 22 light-years remains an enormous distance by current technological standards, it\'s relatively close in astronomical terms.',
        '"Kepler-442c represents hope," concluded Dr. Wilson. "Hope that life is not unique to Earth, hope that we might one day find kindred spirits among the stars."',
      ],
    ],
  ),
];
