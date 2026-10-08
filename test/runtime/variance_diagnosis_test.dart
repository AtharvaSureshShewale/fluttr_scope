import 'package:fluttr_scope/src/runtime/environment_metadata.dart';
import 'package:fluttr_scope/src/runtime/frame_budget.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/multi_run.dart';
import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:fluttr_scope/src/runtime/variance_diagnosis.dart';
import 'package:test/test.dart';

FrameMetrics _f({required int buildUs, required int rasterUs}) => FrameMetrics(
      frameNumber: 1,
      build: Duration(microseconds: buildUs),
      raster: Duration(microseconds: rasterUs),
      elapsed: Duration(microseconds: buildUs + rasterUs),
      startTimeMicros: 0,
    );

RunAnalysis _run(
  int index, {
  required double overBudgetPercent,
  required int rebuildCount,
  int? heapDeltaBytes,
}) {
  final slowest = _f(buildUs: 20000, rasterUs: 2000);
  final steadyState = FrameBudgetSummary(
    budget: defaultFrameBudget,
    totalFrames: 1000,
    framesOverBudget: (overBudgetPercent * 10).round(),
    slowestFrame: slowest,
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
  return RunAnalysis(
    runIndex: index,
    steadyState: steadyState,
    startup: emptyStartup,
    rebuildCount: rebuildCount,
    heapDeltaBytes: heapDeltaBytes,
  );
}

MultiRunSummary summarize(List<RunAnalysis> runs, {EnvironmentMetadata? environment, String? flow}) =>
    summarizeRuns(
      requestedRuns: runs.length,
      warmup: const Duration(seconds: 5),
      captureDuration: const Duration(seconds: 20),
      validRuns: runs,
      invalidRuns: const [],
      environment: environment,
      flow: flow,
    );

const _emulatorEnv = EnvironmentMetadata(
  device: 'emulator-5554',
  looksLikeEmulator: true,
  hostPlatform: 'windows 10.0',
  buildMode: 'debug',
  assumedFrameBudget: defaultFrameBudget,
  dartVmVersion: '3.5.0',
);

const _physicalEnv = EnvironmentMetadata(
  device: 'my-pixel-8',
  looksLikeEmulator: false,
  hostPlatform: 'windows 10.0',
  buildMode: 'debug',
  assumedFrameBudget: defaultFrameBudget,
  dartVmVersion: '3.5.0',
);

void main() {
  group('diagnoseVariance edge cases', () {
    test('returns null with fewer than 2 valid runs -- nothing to diagnose', () {
      final zero = summarize(const []);
      expect(diagnoseVariance(zero), isNull);

      final one = summarize([_run(1, overBudgetPercent: 10, rebuildCount: 100)]);
      expect(diagnoseVariance(one), isNull);
    });
  });

  group('stable runs', () {
    final stableRuns = [
      _run(1, overBudgetPercent: 14.7, rebuildCount: 420, heapDeltaBytes: 12000000),
      _run(2, overBudgetPercent: 13.9, rebuildCount: 410, heapDeltaBytes: 12500000),
      _run(3, overBudgetPercent: 15.1, rebuildCount: 430, heapDeltaBytes: 11800000),
      _run(4, overBudgetPercent: 14.4, rebuildCount: 415, heapDeltaBytes: 12200000),
      _run(5, overBudgetPercent: 14.8, rebuildCount: 425, heapDeltaBytes: 12100000),
    ];

    test('status is HIGH confidence and no dimension is listed as a contributor', () {
      final diagnosis = diagnoseVariance(summarize(stableRuns))!;
      expect(diagnosis.status, Confidence.high);
      expect(diagnosis.contributors.every((c) => !c.stats.isUnstable), isTrue);
    });

    test('recommendation treats the metric as CI-gate-worthy, no emulator caveat needed', () {
      final diagnosis = diagnoseVariance(summarize(stableRuns, environment: _emulatorEnv))!;
      expect(diagnosis.recommendations.single, contains('CI regression signal'));
    });

    test('formatVarianceDiagnosis reports STABLE and an empty contributors list', () {
      final diagnosis = diagnoseVariance(summarize(stableRuns))!;
      final report = formatVarianceDiagnosis(diagnosis);
      expect(report, contains('Status: STABLE'));
      expect(report, contains('none -- every observable dimension was stable'));
    });
  });

  group('highly variable runs', () {
    final variableRuns = [
      _run(1, overBudgetPercent: 21.9, rebuildCount: 900),
      _run(2, overBudgetPercent: 20.4, rebuildCount: 850),
      _run(3, overBudgetPercent: 0.3, rebuildCount: 420),
      _run(4, overBudgetPercent: 50.5, rebuildCount: 1600),
      _run(5, overBudgetPercent: 63.7, rebuildCount: 1820),
    ];

    test('status is not HIGH confidence and frame timing is listed as a contributor', () {
      final diagnosis = diagnoseVariance(summarize(variableRuns))!;
      expect(diagnosis.status, isNot(Confidence.high));
      expect(
        diagnosis.contributors
            .firstWhere((c) => c.label == 'Frame timing (over-budget %)')
            .stats
            .isUnstable,
        isTrue,
      );
    });

    test('formatVarianceDiagnosis reports UNSTABLE with the actual CoV', () {
      final diagnosis = diagnoseVariance(summarize(variableRuns))!;
      final report = formatVarianceDiagnosis(diagnosis);
      expect(report, contains('Status: UNSTABLE'));
      expect(report, contains('Frame timing (over-budget %): HIGH variance'));
    });
  });

  group('run comparison: identical runtime activity, different frame timing', () {
    test('similar rebuild counts across the extreme runs points toward '
        'environment noise, not application behavior -- and does not claim '
        'causation', () {
      final runs = [
        _run(1, overBudgetPercent: 5, rebuildCount: 500),
        _run(2, overBudgetPercent: 60, rebuildCount: 510), // huge frame diff, same activity
      ];
      final diagnosis = diagnoseVariance(summarize(runs))!;
      final comparison = diagnosis.runComparison!;
      expect(comparison.summary, contains('similar'));
      expect(comparison.summary, contains('environment/scheduling noise'));
      expect(comparison.summary, isNot(contains('caused')));
    });

    test('flow determinism is assessed as deterministic when rebuild '
        'activity was consistent across runs', () {
      final runs = [
        _run(1, overBudgetPercent: 5, rebuildCount: 500),
        _run(2, overBudgetPercent: 6, rebuildCount: 505),
        _run(3, overBudgetPercent: 5, rebuildCount: 495),
      ];
      final diagnosis = diagnoseVariance(summarize(runs))!;
      expect(diagnosis.flowDeterminism.deterministic, isTrue);
      expect(diagnosis.flowDeterminism.explanation, isNot(contains('is not deterministic')));
    });
  });

  group('run comparison: different runtime activity, different frame timing', () {
    test('substantially different rebuild counts across the extreme runs is '
        'reported as consistent with -- not proof of -- more application work', () {
      final runs = [
        _run(1, overBudgetPercent: 0.3, rebuildCount: 420),
        _run(2, overBudgetPercent: 63.7, rebuildCount: 1820), // ~4.3x rebuilds
      ];
      final diagnosis = diagnoseVariance(summarize(runs))!;
      final comparison = diagnosis.runComparison!;
      expect(comparison.summary, contains('substantially more rebuild work'));
      expect(comparison.summary, contains('consistent with'));
      expect(comparison.summary, contains('not proof of'));
    });

    test('flow determinism is assessed as non-deterministic (the literal '
        'required sentence) when rebuild activity varied substantially', () {
      final runs = [
        _run(1, overBudgetPercent: 21.9, rebuildCount: 900),
        _run(2, overBudgetPercent: 20.4, rebuildCount: 850),
        _run(3, overBudgetPercent: 0.3, rebuildCount: 420),
        _run(4, overBudgetPercent: 50.5, rebuildCount: 1600),
        _run(5, overBudgetPercent: 63.7, rebuildCount: 1820),
      ];
      final diagnosis = diagnoseVariance(summarize(runs))!;
      expect(diagnosis.flowDeterminism.deterministic, isFalse);
      expect(diagnosis.flowDeterminism.explanation, contains('Flow behavior is not deterministic.'));
    });
  });

  group('incomplete metadata', () {
    test('heap growth is omitted from contributors (not crashed on) when '
        'some valid runs lack a heap delta', () {
      final runs = [
        _run(1, overBudgetPercent: 10, rebuildCount: 500, heapDeltaBytes: 1000),
        _run(2, overBudgetPercent: 12, rebuildCount: 510), // no heapDeltaBytes
      ];
      final diagnosis = diagnoseVariance(summarize(runs))!;
      expect(diagnosis.contributors.any((c) => c.label == 'Heap growth'), isFalse);
      // The rest of the diagnosis still works despite the gap.
      expect(diagnosis.contributors.any((c) => c.label == 'Rebuild activity'), isTrue);
    });

    test('a null environment does not crash formatting and reports "unknown"', () {
      final runs = [
        _run(1, overBudgetPercent: 10, rebuildCount: 500),
        _run(2, overBudgetPercent: 12, rebuildCount: 510),
      ];
      final diagnosis = diagnoseVariance(summarize(runs, environment: null))!;
      expect(diagnosis.environment, isNull);
      final report = formatVarianceDiagnosis(diagnosis);
      expect(report, contains('unknown'));
    });
  });

  group('environment metadata', () {
    test('an emulator environment adds the hedged (never causal) emulator caveat '
        'only when the measurement is unstable', () {
      final unstableRuns = [
        _run(1, overBudgetPercent: 0.3, rebuildCount: 420),
        _run(2, overBudgetPercent: 63.7, rebuildCount: 1820),
      ];
      final diagnosis = diagnoseVariance(summarize(unstableRuns, environment: _emulatorEnv))!;
      final emulatorLine = diagnosis.recommendations.firstWhere((r) => r.contains('Emulator'));
      expect(emulatorLine, contains('may contribute'));
      expect(emulatorLine, isNot(contains('caused')));
      expect(diagnosis.recommendations, contains('Run on a physical device and/or drive each run with a repeatable flow (--flow).'));
    });

    test('a physical-device environment never mentions the emulator', () {
      final unstableRuns = [
        _run(1, overBudgetPercent: 0.3, rebuildCount: 420),
        _run(2, overBudgetPercent: 63.7, rebuildCount: 1820),
      ];
      final diagnosis = diagnoseVariance(summarize(unstableRuns, environment: _physicalEnv))!;
      expect(diagnosis.recommendations.any((r) => r.contains('Emulator')), isFalse);
    });

    test('formatVarianceDiagnosis prints the device id and Dart VM version when available', () {
      final runs = [
        _run(1, overBudgetPercent: 10, rebuildCount: 500),
        _run(2, overBudgetPercent: 12, rebuildCount: 510),
      ];
      final diagnosis = diagnoseVariance(summarize(runs, environment: _emulatorEnv))!;
      final report = formatVarianceDiagnosis(diagnosis);
      expect(report, contains('emulator-5554'));
      expect(report, contains('3.5.0'));
      expect(report, contains('Emulator'));
    });
  });

  group('variance diagnosis never invents unobservable data', () {
    test('lists network/timers/async/image/semantics as explicitly unavailable, never fabricated', () {
      final runs = [
        _run(1, overBudgetPercent: 10, rebuildCount: 500),
        _run(2, overBudgetPercent: 12, rebuildCount: 510),
      ];
      final diagnosis = diagnoseVariance(summarize(runs))!;
      expect(diagnosis.unavailableDimensions, containsAll([
        'Network activity',
        'Timers',
        'Async activity',
        'Image/asset activity',
        'Semantics collection',
      ]));
      // None of the contributors this tool reports are among the
      // unobservable ones -- it must never claim to measure what it can't.
      final contributorLabels = diagnosis.contributors.map((c) => c.label).toSet();
      expect(contributorLabels.intersection(diagnosis.unavailableDimensions.toSet()), isEmpty);

      final report = formatVarianceDiagnosis(diagnosis);
      expect(report, contains('Not observable with the current probe:'));
      expect(report, contains('Network activity'));
    });
  });

  group('runs driven by a flow (--flow)', () {
    const flow = 'integration_test/checkout_flow_test.dart';

    test('identical app work, different frame timing: blames the environment, not the app', () {
      // Measured on a real app: 1376 rebuilds in every run, 4.0% vs 8.9% slow frames.
      final runs = [
        _run(1, overBudgetPercent: 4.6, rebuildCount: 1376),
        _run(2, overBudgetPercent: 4.0, rebuildCount: 1376),
        _run(3, overBudgetPercent: 8.9, rebuildCount: 1376),
      ];
      final diagnosis = diagnoseVariance(summarize(runs, environment: _emulatorEnv, flow: flow))!;
      expect(diagnosis.flowDeterminism.deterministic, isTrue);
      expect(diagnosis.flowDeterminism.explanation, contains(flow));
      expect(diagnosis.flowDeterminism.explanation, contains('not the app'));
      expect(diagnosis.flowDeterminism.explanation, isNot(contains('No flow was used')));
      expect(diagnosis.recommendations.last, contains('the remaining variance is the environment'));
    });

    test('a flow whose app work still varies is called out as the problem', () {
      final runs = [
        _run(1, overBudgetPercent: 20, rebuildCount: 900),
        _run(2, overBudgetPercent: 40, rebuildCount: 1800),
        _run(3, overBudgetPercent: 5, rebuildCount: 400),
      ];
      final diagnosis = diagnoseVariance(summarize(runs, flow: flow))!;
      expect(diagnosis.flowDeterminism.deterministic, isFalse);
      expect(diagnosis.flowDeterminism.explanation, contains('Flow behavior is not deterministic.'));
      expect(diagnosis.flowDeterminism.explanation, contains('the flow itself'));
      expect(diagnosis.recommendations.last, startsWith('Make the flow deterministic'));
    });
  });
}
