import 'package:fluttr_scope/src/runtime/frame_budget.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/multi_run.dart';
import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:test/test.dart';

FrameMetrics _f({required int buildUs, required int rasterUs, int startTimeMicros = 0}) =>
    FrameMetrics(
      frameNumber: 1,
      build: Duration(microseconds: buildUs),
      raster: Duration(microseconds: rasterUs),
      elapsed: Duration(microseconds: buildUs + rasterUs),
      startTimeMicros: startTimeMicros,
    );

/// A synthetic [RunAnalysis] with directly-controlled steady-state/startup
/// numbers -- [FrameBudgetSummary.overBudgetPercent] is a computed getter
/// (framesOverBudget / totalFrames), so totalFrames is fixed at 1000 and
/// framesOverBudget derived from the desired percentage to hit it exactly.
RunAnalysis _run(
  int index, {
  required double overBudgetPercent,
  required int jankClusterCount,
  required double slowestMs,
  double? startupWorstMs,
}) {
  final slowest = _f(buildUs: (slowestMs * 1000).round(), rasterUs: 0);
  final steadyState = FrameBudgetSummary(
    budget: defaultFrameBudget,
    totalFrames: 1000,
    framesOverBudget: (overBudgetPercent * 10).round(),
    slowestFrame: slowest,
    jankClusters: List.generate(jankClusterCount, (_) => [slowest, slowest, slowest, slowest]),
    minClusterSize: 4,
  );
  final startup = FrameBudgetSummary(
    budget: defaultFrameBudget,
    totalFrames: startupWorstMs == null ? 0 : 10,
    framesOverBudget: 0,
    slowestFrame:
        startupWorstMs == null ? null : _f(buildUs: (startupWorstMs * 1000).round(), rasterUs: 0),
    jankClusters: const [],
    minClusterSize: 4,
  );
  return RunAnalysis(runIndex: index, steadyState: steadyState, startup: startup);
}

void main() {
  group('summarizeRuns aggregation', () {
    final fiveStableRuns = [
      _run(1, overBudgetPercent: 14.7, jankClusterCount: 8, slowestMs: 39.1),
      _run(2, overBudgetPercent: 13.9, jankClusterCount: 7, slowestMs: 37.8),
      _run(3, overBudgetPercent: 15.1, jankClusterCount: 9, slowestMs: 44.2),
      _run(4, overBudgetPercent: 14.4, jankClusterCount: 8, slowestMs: 38.5),
      _run(5, overBudgetPercent: 14.8, jankClusterCount: 8, slowestMs: 39.7),
    ];

    MultiRunSummary summarize(List<RunAnalysis> runs, {List<InvalidRun> invalid = const []}) =>
        summarizeRuns(
          requestedRuns: runs.length + invalid.length,
          warmup: const Duration(seconds: 5),
          captureDuration: const Duration(seconds: 20),
          validRuns: runs,
          invalidRuns: invalid,
        );

    test('median matches computeStats over the per-run over-budget percentages', () {
      final summary = summarize(fiveStableRuns);
      final expected = computeStats(const [14.7, 13.9, 15.1, 14.4, 14.8]);
      expect(summary.overBudgetPercent!.median, closeTo(expected.median, 1e-9));
      expect(summary.overBudgetPercent!.mean, closeTo(expected.mean, 1e-9));
      expect(summary.overBudgetPercent!.min, closeTo(expected.min, 1e-9));
      expect(summary.overBudgetPercent!.max, closeTo(expected.max, 1e-9));
    });

    test('mean, standard deviation, and CoV are computed for each headline metric', () {
      final summary = summarize(fiveStableRuns);
      expect(summary.overBudgetPercent!.stdDev, greaterThan(0));
      expect(summary.overBudgetPercent!.coefficientOfVariation, greaterThan(0));
      expect(summary.jankClusterCount!.mean, closeTo(8.0, 1e-9));
      expect(summary.slowestSteadyStateFrameMs!.mean, closeTo(39.86, 1e-2));
    });

    test('confidence is HIGH for a tightly clustered set of runs', () {
      final summary = summarize(fiveStableRuns);
      expect(summary.overBudgetPercent!.confidence, Confidence.high);
      expect(summary.overBudgetPercent!.isUnstable, isFalse);
    });

    test('per-run values are preserved in run order for the Runs: listing', () {
      final summary = summarize(fiveStableRuns);
      final values = summary.overBudgetPercent!.values;
      expect(values, hasLength(5));
      for (final (i, expected) in const [14.7, 13.9, 15.1, 14.4, 14.8].indexed) {
        expect(values[i], closeTo(expected, 1e-9));
      }
      expect(summary.validRuns.map((r) => r.runIndex), [1, 2, 3, 4, 5]);
    });

    test('per-run metrics are computed before aggregation, never by pooling '
        'raw frames across runs into one count', () {
      // Run A: 50% over budget (5 of 10 frames). Run B: 5% (5 of 100).
      // Pooled/concatenated: 10 of 110 = ~9.1%. Per-run-first (mean of the
      // two percentages): 27.5%. These must differ -- if they matched,
      // the implementation would be silently pooling frames.
      final runA = FrameBudgetSummary(
        budget: defaultFrameBudget,
        totalFrames: 10,
        framesOverBudget: 5,
        slowestFrame: _f(buildUs: 20000, rasterUs: 0),
        jankClusters: const [],
        minClusterSize: 4,
      );
      final runB = FrameBudgetSummary(
        budget: defaultFrameBudget,
        totalFrames: 100,
        framesOverBudget: 5,
        slowestFrame: _f(buildUs: 18000, rasterUs: 0),
        jankClusters: const [],
        minClusterSize: 4,
      );
      final emptyStartup = FrameBudgetSummary(
        budget: defaultFrameBudget,
        totalFrames: 0,
        framesOverBudget: 0,
        slowestFrame: null,
        jankClusters: const [],
        minClusterSize: 4,
      );
      final summary = summarizeRuns(
        requestedRuns: 2,
        warmup: Duration.zero,
        captureDuration: const Duration(seconds: 20),
        validRuns: [
          RunAnalysis(runIndex: 1, steadyState: runA, startup: emptyStartup),
          RunAnalysis(runIndex: 2, steadyState: runB, startup: emptyStartup),
        ],
        invalidRuns: const [],
      );

      final pooledPercent = (5 + 5) / (10 + 100) * 100;
      expect(summary.overBudgetPercent!.mean, isNot(closeTo(pooledPercent, 0.5)));
      expect(summary.overBudgetPercent!.mean, closeTo(27.5, 1e-9));
    });

    test('startup worst frame is the max across runs and is kept separate '
        'from the steady-state slowest-frame stats', () {
      final runs = [
        _run(1, overBudgetPercent: 5, jankClusterCount: 1, slowestMs: 20, startupWorstMs: 700),
        _run(2, overBudgetPercent: 5, jankClusterCount: 1, slowestMs: 22, startupWorstMs: 300),
      ];
      final summary = summarize(runs);
      expect(summary.startupWorstFrameMs, 700);
      // The huge startup spike must not leak into steady-state numbers.
      expect(summary.slowestSteadyStateFrameMs!.max, 22);
    });

    test('startupWorstFrameMs is null when no run captured startup frames '
        '(e.g. warmup was 0)', () {
      final runs = [
        _run(1, overBudgetPercent: 5, jankClusterCount: 1, slowestMs: 20),
        _run(2, overBudgetPercent: 5, jankClusterCount: 1, slowestMs: 22),
      ];
      final summary = summarize(runs);
      expect(summary.startupWorstFrameMs, isNull);
    });

    test('dominant bottleneck is a majority vote among over-budget runs only', () {
      RunAnalysis buildDominant(int i) {
        final slowest = _f(buildUs: 24000, rasterUs: 2000); // build-dominant
        final steady = FrameBudgetSummary(
          budget: defaultFrameBudget,
          totalFrames: 100,
          framesOverBudget: 10,
          slowestFrame: slowest,
          jankClusters: const [],
          minClusterSize: 4,
        );
        final startup = FrameBudgetSummary(
          budget: defaultFrameBudget,
          totalFrames: 0,
          framesOverBudget: 0,
          slowestFrame: null,
          jankClusters: const [],
          minClusterSize: 4,
        );
        return RunAnalysis(runIndex: i, steadyState: steady, startup: startup);
      }

      final summary = summarizeRuns(
        requestedRuns: 3,
        warmup: Duration.zero,
        captureDuration: const Duration(seconds: 20),
        validRuns: [buildDominant(1), buildDominant(2), buildDominant(3)],
        invalidRuns: const [],
      );
      expect(summary.dominantBottleneck, FrameBottleneck.build);
    });

    test('dominant bottleneck is null when no valid run had an over-budget frame', () {
      final runs = [
        _run(1, overBudgetPercent: 0, jankClusterCount: 0, slowestMs: 5),
        _run(2, overBudgetPercent: 0, jankClusterCount: 0, slowestMs: 4),
      ];
      final summary = summarize(runs);
      expect(summary.dominantBottleneck, isNull);
    });
  });

  group('unstable measurements', () {
    test('a wild outlier among the runs drops confidence below HIGH and '
        'marks the metric unstable', () {
      final runs = [
        _run(1, overBudgetPercent: 8, jankClusterCount: 2, slowestMs: 20),
        _run(2, overBudgetPercent: 9, jankClusterCount: 2, slowestMs: 21),
        _run(3, overBudgetPercent: 45, jankClusterCount: 2, slowestMs: 22), // outlier
        _run(4, overBudgetPercent: 7, jankClusterCount: 2, slowestMs: 20),
        _run(5, overBudgetPercent: 8, jankClusterCount: 2, slowestMs: 21),
      ];
      final summary = summarizeRuns(
        requestedRuns: 5,
        warmup: Duration.zero,
        captureDuration: const Duration(seconds: 20),
        validRuns: runs,
        invalidRuns: const [],
      );

      expect(summary.overBudgetPercent!.isUnstable, isTrue);
      expect(summary.overBudgetPercent!.confidence, isNot(Confidence.high));
      // The outlier must still be present in the raw data, not discarded.
      expect(summary.overBudgetPercent!.values, contains(45.0));
      expect(summary.overBudgetPercent!.max, 45.0);
    });

    test('formatMultiRunReport prints an explicit UNSTABLE warning, never '
        'just a quiet number, for an unstable metric', () {
      final runs = [
        _run(1, overBudgetPercent: 8, jankClusterCount: 2, slowestMs: 20),
        _run(2, overBudgetPercent: 9, jankClusterCount: 2, slowestMs: 21),
        _run(3, overBudgetPercent: 45, jankClusterCount: 2, slowestMs: 22),
        _run(4, overBudgetPercent: 7, jankClusterCount: 2, slowestMs: 20),
        _run(5, overBudgetPercent: 8, jankClusterCount: 2, slowestMs: 21),
      ];
      final summary = summarizeRuns(
        requestedRuns: 5,
        warmup: Duration.zero,
        captureDuration: const Duration(seconds: 20),
        validRuns: runs,
        invalidRuns: const [],
      );
      final report = formatMultiRunReport(summary);
      expect(report, contains('UNSTABLE'));
      expect(report, contains('CI gate'));
    });
  });

  group('invalid runs', () {
    test('invalid runs are preserved with their reasons and do not '
        'silently become zeros in the statistics', () {
      final summary = summarizeRuns(
        requestedRuns: 5,
        warmup: Duration.zero,
        captureDuration: const Duration(seconds: 20),
        validRuns: [
          _run(1, overBudgetPercent: 14.7, jankClusterCount: 8, slowestMs: 39.1),
          _run(2, overBudgetPercent: 14.4, jankClusterCount: 8, slowestMs: 38.5),
        ],
        invalidRuns: const [
          InvalidRun(runIndex: 3, reason: 'flutter run never printed a VM Service URI'),
          InvalidRun(runIndex: 4, reason: 'only 3 steady-state frame(s) captured (minimum 10)'),
          InvalidRun(runIndex: 5, reason: 'flutter run never printed a VM Service URI'),
        ],
      );

      expect(summary.invalidRuns, hasLength(3));
      expect(summary.invalidRuns.map((r) => r.runIndex), [3, 4, 5]);
      // Only the 2 valid runs feed the statistics -- not 5, and no zeros
      // were substituted for the missing 3.
      expect(summary.overBudgetPercent!.values, hasLength(2));
      expect(summary.overBudgetPercent!.mean, closeTo((14.7 + 14.4) / 2, 1e-9));
    });

    test('all runs invalid produces null statistics and a clear message, '
        'not a crash or a fabricated zero', () {
      final summary = summarizeRuns(
        requestedRuns: 3,
        warmup: Duration.zero,
        captureDuration: const Duration(seconds: 20),
        validRuns: const [],
        invalidRuns: const [
          InvalidRun(runIndex: 1, reason: 'app failed to launch'),
          InvalidRun(runIndex: 2, reason: 'app failed to launch'),
          InvalidRun(runIndex: 3, reason: 'app failed to launch'),
        ],
      );

      expect(summary.overBudgetPercent, isNull);
      expect(summary.jankClusterCount, isNull);
      expect(summary.slowestSteadyStateFrameMs, isNull);
      expect(summary.dominantBottleneck, isNull);

      final report = formatMultiRunReport(summary);
      expect(report, contains('No valid runs'));
      expect(report, contains('INVALID RUNS (3)'));

      final json = summary.toJson();
      expect(json['overBudgetPercent'], isNull);
      expect((json['invalidRuns'] as List), hasLength(3));
    });

    test('minSteadyStateFramesPerRun is a stated, documented threshold '
        '(not a magic number scattered through the code)', () {
      expect(minSteadyStateFramesPerRun, 10);
    });
  });

  group('warm-up applied independently per run', () {
    test('two runs with different launch-time clock bases each split '
        'correctly using their own first frame as the reference point', () {
      // Simulates two separate app launches: run A's frames start around
      // engine-clock 1_000_000us, run B's around a completely different
      // base (5_000_000us) -- these are independent monotonic clocks, not
      // synchronized across launches, so each split must use only its own
      // run's first frame as the warm-up reference.
      final runAFrames = [
        for (var i = 0; i < 30; i++)
          _f(buildUs: 5000, rasterUs: 3000, startTimeMicros: 1000000 + i * 16667),
      ];
      final runBFrames = [
        for (var i = 0; i < 30; i++)
          _f(buildUs: 5000, rasterUs: 3000, startTimeMicros: 5000000 + i * 16667),
      ];

      final captureA = splitByWarmup(runAFrames, const Duration(milliseconds: 250));
      final captureB = splitByWarmup(runBFrames, const Duration(milliseconds: 250));

      expect(captureA.startup, isNotEmpty);
      expect(captureB.startup, isNotEmpty);
      // Each run's steady-state frames start relative to *its own* first
      // frame, not to the other run's clock base.
      expect(
        captureA.steadyState.first.startTimeMicros - runAFrames.first.startTimeMicros,
        captureB.steadyState.first.startTimeMicros - runBFrames.first.startTimeMicros,
      );
    });
  });
}
