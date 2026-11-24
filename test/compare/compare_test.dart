import 'dart:convert';

import 'package:fluttr_scope/src/compare/compare.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/frame_budget.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/multi_run.dart';
import 'package:fluttr_scope/src/runtime/widget_frame_impact.dart';
import 'package:test/test.dart';

/// A valid run whose slowest frame took [slowestMs], with [rebuilds] per
/// file (file -> count).
RunAnalysis _run(int index, {required double slowestMs, Map<String, int> rebuilds = const {}}) {
  final slowest = FrameMetrics(
    frameNumber: 1,
    build: Duration(microseconds: (slowestMs * 1000).round()),
    raster: Duration.zero,
    elapsed: Duration(microseconds: (slowestMs * 1000).round()),
    startTimeMicros: 0,
  );
  final steady = FrameBudgetSummary(
    budget: defaultFrameBudget,
    totalFrames: 100,
    framesOverBudget: 10,
    slowestFrame: slowest,
    jankClusters: const [],
    minClusterSize: 4,
  );
  return RunAnalysis(
    runIndex: index,
    steadyState: steady,
    startup: FrameBudgetSummary(
      budget: defaultFrameBudget,
      totalFrames: 0,
      framesOverBudget: 0,
      slowestFrame: null,
      jankClusters: const [],
      minClusterSize: 4,
    ),
    widgetFrameImpacts: [
      for (final MapEntry(key: file, value: count) in rebuilds.entries)
        WidgetFrameImpact(
          location: SourceLocation(file: file, line: 1, column: 1, length: 1),
          rebuildCount: count,
          framesRebuiltIn: const {1},
          overBudgetFramesRebuiltIn: const {},
          frameBuildStatsMs: null,
        ),
    ],
  );
}

/// What `measure --runs N --format json` writes for [runs], decoded.
Map<String, Object?> _measured(List<RunAnalysis> runs, {String? flow = 'integration_test/f_test.dart'}) {
  final summary = summarizeRuns(
    requestedRuns: runs.length,
    warmup: Duration.zero,
    captureDuration: const Duration(seconds: 60),
    validRuns: runs,
    invalidRuns: const [],
    flow: flow,
  );
  return jsonDecode(jsonEncode(summary.toJson())) as Map<String, Object?>;
}

MetricComparison _metric(Comparison c, String name) => c.headline.singleWhere((m) => m.name == name);

void main() {
  group('MetricComparison.change', () {
    test('better or worse only when the runs do not overlap', () {
      expect(const MetricComparison('m', '', [10, 11, 12], [7, 8, 9]).change, Change.better);
      expect(const MetricComparison('m', '', [10, 11, 12], [13, 14, 15]).change, Change.worse);
      // Medians differ a lot, but one after-run is as slow as a before-run.
      expect(const MetricComparison('m', '', [10, 11, 12], [5, 6, 10]).change, Change.noClearChange);
      expect(const MetricComparison('m', '', [0, 0, 0], [0, 0, 0]).change, Change.noClearChange);
    });

    test('needs enough runs on both sides', () {
      expect(const MetricComparison('m', '', [10, 11], [1, 2, 3]).change, Change.tooFewRuns);
    });

    test('percent change is of the median, and absent from zero', () {
      expect(const MetricComparison('m', '', [100, 100, 100], [62, 62, 62]).percentChange, closeTo(-38, 0.001));
      expect(const MetricComparison('m', '', [0, 0, 0], [5, 5, 5]).percentChange, isNull);
    });
  });

  test('reads what measure writes: frame timing, rebuilds, rebuilds by file', () {
    final before = _measured([
      for (final (i, ms, n) in [(1, 160.0, 4600), (2, 170.0, 4650), (3, 167.0, 4611)])
        _run(i, slowestMs: ms, rebuilds: {'lib/a.dart': n, 'lib/b.dart': 100}),
    ]);
    final after = _measured([
      for (final (i, ms, n) in [(1, 80.0, 2860), (2, 79.0, 2900), (3, 90.0, 2850)])
        _run(i, slowestMs: ms, rebuilds: {'lib/a.dart': n, 'lib/b.dart': 101 + i}),
    ]);

    final c = compareMeasurements(before, after);
    expect(c.warnings, isEmpty);
    expect(_metric(c, 'Slowest frame').change, Change.better);
    expect(_metric(c, 'Slowest frame').afterMedian, 80);
    expect(_metric(c, 'Rebuilds (after warm-up)').change, Change.better);
    expect(_metric(c, 'Frames over budget').change, Change.noClearChange);
    expect(c.hasRegression, isFalse);

    // Largest change first; lib/b.dart's +2..+4 is consistent, so worse.
    expect(c.byFile.map((m) => m.name), ['lib/a.dart', 'lib/b.dart']);
    expect(c.byFile.first.change, Change.better);
    expect(c.byFile.last.change, Change.worse);

    final report = formatComparison(c);
    expect(report, contains('✅ better'));
    expect(report, contains('lib/a.dart  4,611 -> 2,860  (-38%)'));
  });

  test('shows files outside the project as package: URIs', () {
    expect(
      displayPath('../../../Users/me/AppData/Local/Pub/Cache/hosted/pub.dev/provider-6.1.5+1/lib/src/inherited_provider.dart'),
      'package:provider/src/inherited_provider.dart',
    );
    expect(displayPath('../../flutter/packages/flutter/lib/src/widgets/framework.dart'),
        'package:flutter/src/widgets/framework.dart');
    expect(displayPath('lib/ui/home.dart'), 'lib/ui/home.dart');
  });

  test('a clearly slower after is a regression', () {
    final before = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50.0 + i)]);
    final after = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 90.0 + i)]);
    expect(compareMeasurements(before, after).hasRegression, isTrue);
  });

  test('a file that stops rebuilding counts as zero after', () {
    final before = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50, rebuilds: {'lib/gone.dart': 40})]);
    final after = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50)]);
    final gone = compareMeasurements(before, after).byFile.single;
    expect(gone.after, [0, 0, 0]);
    expect(gone.change, Change.better);
  });

  test('warns when the runs may not have done the same things', () {
    final withFlow = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50)]);
    final noFlow = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50)], flow: null);
    expect(compareMeasurements(withFlow, noFlow).warnings.single, contains('Only one'));
    expect(compareMeasurements(noFlow, noFlow).warnings.single, contains('Neither'));
  });

  test('older results without rebuild data still compare frame timing', () {
    final before = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50)])
      ..remove('rebuildsPerRun')
      ..remove('rebuildsByFilePerRun');
    final after = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50)]);
    final c = compareMeasurements(before, after);
    expect(c.headline.map((m) => m.name), isNot(contains('Rebuilds (after warm-up)')));
    expect(c.warnings.single, contains('Rebuild counts are missing'));
  });

  test('rejects JSON that is not a multi-run measurement', () {
    final ok = _measured([for (var i = 1; i <= 3; i++) _run(i, slowestMs: 50)]);
    expect(
      () => compareMeasurements({'rebuilds': []}, ok),
      throwsA(isA<CompareInputException>().having((e) => e.message, 'message', contains('--runs'))),
    );
  });
}
