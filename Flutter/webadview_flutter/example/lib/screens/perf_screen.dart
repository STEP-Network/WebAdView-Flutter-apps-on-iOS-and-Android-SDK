import 'dart:async';
import 'dart:io' show pid;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:webadview_flutter/webadview_flutter.dart';

import '../config.dart';
import '../data/articles.dart';
import '../widgets/article_row.dart';

/// Scroll-performance harness (`--dart-define=SN_PERF=true`).
///
/// A 120-row `ListView.builder` with three ads (rows 6, 30 and 60) — or grey
/// boxes of the same size with `SN_PERF_ADS=false`, the control run. After
/// the ads have had time to load it runs a fixed sequence of flings and
/// prints ONE `[PERF]` block with the frame statistics Flutter measured
/// (`SchedulerBinding.addTimingsCallback`): frames, average / p90 / worst
/// frame time, frames over 16.7 ms and over 33 ms. The native SDK prints its
/// own `[SN] [PERF]` counters once per second alongside (evaluations,
/// webview resizes, JavaScript sends, geometry batches, viewability calls).
///
/// Compare runs with ads on and off on the same device; the delta is what
/// the SDK costs during scroll.
class PerfScreen extends StatefulWidget {
  const PerfScreen({super.key});

  @override
  State<PerfScreen> createState() => _PerfScreenState();
}

class _PerfScreenState extends State<PerfScreen> {
  static const int rows = 120;
  static const Map<int, String> adRows = <int, String>{
    6: 'div-gpt-ad-mobile_1',
    30: 'div-gpt-ad-mobile_2',
    60: 'div-gpt-ad-mobile_3',
  };

  final ScrollController _controller = ScrollController();
  final List<FrameTiming> _timings = <FrameTiming>[];
  final Map<String, int> _viewabilityCalls = <String, int>{};
  bool _recording = false;
  bool _running = false;
  String _report = DemoConfig.perfAuto
      ? 'Auto-run starts in 8 s (ads loading)…'
      : 'Tap ▶ to run the fling script.';
  Timer? _autoStart;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    if (DemoConfig.perfAuto) {
      _autoStart = Timer(const Duration(seconds: 8), _run);
    }
  }

  @override
  void dispose() {
    _autoStart?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _controller.dispose();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_recording) _timings.addAll(timings);
  }

  /// Six flings of two to four screens each, up and down, with short rests
  /// (the rests let trailing timers and the lazy-load throttle show up too).
  Future<void> _run() async {
    if (_running) return;
    _running = true;
    _timings.clear();
    _viewabilityCalls.clear();
    setState(() => _report = 'Running…');
    debugPrint('[PERF] run-start pid=$pid');
    final max = _controller.position.maxScrollExtent;
    final targets = <double>[max * 0.35, 0, max * 0.7, max * 0.35, max, 0];
    _recording = true;
    final started = DateTime.now();
    for (final target in targets) {
      await _controller.animateTo(target,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeOutCubic);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    _recording = false;
    final elapsed = DateTime.now().difference(started);
    final report = _summarize(elapsed);
    debugPrint(report);
    if (mounted) setState(() => _report = report);
    _running = false;
  }

  String _summarize(Duration elapsed) {
    final totals = _timings
        .map((t) => t.totalSpan.inMicroseconds / 1000.0)
        .toList()
      ..sort();
    final builds = _timings.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList();
    final rasters = _timings.map((t) => t.rasterDuration.inMicroseconds / 1000.0).toList();
    double avg(List<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    double pct(List<double> sorted, double p) =>
        sorted.isEmpty ? 0 : sorted[math.min(sorted.length - 1, (sorted.length * p).floor())];
    final over16 = totals.where((t) => t > 16.7).length;
    final over33 = totals.where((t) => t > 33.4).length;
    final listened = DemoConfig.perfListen
        ? ' viewabilityCallbacks=${_viewabilityCalls.values.fold<int>(0, (a, b) => a + b)}'
        : '';
    final b = StringBuffer()
      ..writeln('[PERF] ads=${DemoConfig.perfAds} listen=${DemoConfig.perfListen} '
          'cacheExtent=${DemoConfig.perfCacheExtent} '
          'platform=${defaultTargetPlatform.name} elapsed=${elapsed.inMilliseconds} ms')
      ..writeln('[PERF] frames=${totals.length} '
          'avg=${avg(totals).toStringAsFixed(1)} ms '
          'p90=${pct(totals, 0.9).toStringAsFixed(1)} ms '
          'p99=${pct(totals, 0.99).toStringAsFixed(1)} ms '
          'worst=${(totals.isEmpty ? 0 : totals.last).toStringAsFixed(1)} ms')
      ..writeln('[PERF] over16.7ms=$over16 (${totals.isEmpty ? 0 : (100 * over16 / totals.length).toStringAsFixed(1)}%) '
          'over33ms=$over33 '
          'build avg=${avg(builds).toStringAsFixed(2)} ms '
          'raster avg=${avg(rasters).toStringAsFixed(2)} ms$listened');
    return b.toString().trimRight();
  }

  Widget _adOrBox(int row) {
    final id = adRows[row]!;
    if (!DemoConfig.perfAds) {
      return Container(
        height: 266,
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.grey.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: Text('placeholder $id'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: WebAdView(
          adUnitId: id,
          showAdLabel: true,
          onViewabilityChange: DemoConfig.perfListen
              ? (u) => _viewabilityCalls.update(u.adUnitId, (n) => n + 1, ifAbsent: () => 1)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perf harness'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Run the fling script',
            onPressed: _running ? null : _run,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.all(8),
            child: Text(_report,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace')),
          ),
          Expanded(
            child: LazyLoadAdScope(
              child: ListView.builder(
                controller: _controller,
                scrollCacheExtent: DemoConfig.perfCacheExtent > 0
                    ? ScrollCacheExtent.pixels(DemoConfig.perfCacheExtent.toDouble())
                    : null,
                itemCount: rows,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, row) {
                  if (adRows.containsKey(row)) return _adOrBox(row);
                  return ArticleRow(article: articles[row % articles.length]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
