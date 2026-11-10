import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/perf_screen.dart';

class NewsHubApp extends StatelessWidget {
  const NewsHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NewsHub',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: DemoConfig.perfMode ? const PerfScreen() : const HomeScreen(),
    );
  }
}
