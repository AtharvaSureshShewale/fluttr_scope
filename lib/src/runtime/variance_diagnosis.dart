import 'environment_metadata.dart';
import 'multi_run.dart';
import 'stats.dart';

/// Runtime activity dimensions this probe has no instrumentation for at
/// all. Listed explicitly (never silently omitted) so a report can say
/// "not observable" instead of just not mentioning them -- the difference
/// between "we checked and there's nothing there" and "we didn't check"
/// matters when someone is trying to explain a variance result.
const unobservableActivityDimensions = [
  'Network activity',
  'Timers',
  'Async activity',
  'Image/asset activity',
  'Semantics collection',
];

/// One activity/timing dimension's cross-run variability, for the
/// "Potential contributors" listing.
class DimensionVariance {
  final String label;
  final Stats stats;

  const DimensionVariance({required this.label, required this.stats});
}

/// Magnitude threshold for calling one run's activity "substantially"
/// different from another's -- a stated judgment call (same treatment as
/// [FrameSeverity]/[Confidence] elsewhere in this package), not a derived
/// constant. 1.5x is a round number comfortably above run-to-run noise on
/// a count metric like rebuilds.
const substantialDifferenceRatio = 1.5;

/// A plain-language comparison between the two most extreme runs (by
/// over-budget %), grounded in whatever activity data is actually
/// available -- never asserting causation, only describing what
/// activity-metric differences are and aren't consistent with.
class RunComparison {
  final RunAnalysis lowest;
  final RunAnalysis highest;
  final String summary;

  const RunComparison({required this.lowest, required this.highest, required this.summary});
}

/// Whether repeated captures look like they exercised the app the same
/// way each time -- the closest thing to a "flow determinism" signal
/// available without any scripted-interaction flow to actually hold
/// constant (see [flowScriptingAvailable]).
class FlowDeterminismAssessment {
  final bool deterministic;
  final String explanation;

  const FlowDeterminismAssessment({required this.deterministic, required this.explanation});
}

/// This version of the tool has no scripted-interaction flow at all --
/// capture is a fixed-duration passive window after launch, not a
/// repeatable script. Kept as a named constant so every place that needs
/// to caveat "flow" behavior does so consistently, and so it's a one-line
/// change (not a scattered assumption) the day flow scripting exists.
const flowScriptingAvailable = false;

/// Everything [diagnoseVariance] can say about *why* a multi-run
/// measurement came back unstable -- built entirely from data the probe
/// actually captured, with unsupported dimensions listed as unavailable
/// rather than guessed at, and hedged (never causal) language throughout.
class VarianceDiagnosis {
  final Confidence status;
  final double coefficientOfVariation;
  final List<DimensionVariance> contributors;
  final List<String> unavailableDimensions;
  final EnvironmentMetadata? environment;
  final RunComparison? runComparison;
  final FlowDeterminismAssessment flowDeterminism;
  final List<String> recommendations;

  const VarianceDiagnosis({
    required this.status,
    required this.coefficientOfVariation,
    required this.contributors,
    required this.unavailableDimensions,
    required this.environment,
    required this.runComparison,
    required this.flowDeterminism,
    required this.recommendations,
  });

  Map<String, Object?> toJson() => {
        'status': status.name,
        'coefficientOfVariation': coefficientOfVariation,
        'contributors': [
          for (final c in contributors)
            {
              'label': c.label,
              'confidence': c.stats.confidence.name,
              'coefficientOfVariation': c.stats.coefficientOfVariation,
              'isUnstable': c.stats.isUnstable,
            },
        ],
        'unavailableDimensions': unavailableDimensions,
        'environment': environment?.toJson(),
        'runComparison': runComparison == null
            ? null
            : {
                'lowestRunIndex': runComparison!.lowest.runIndex,
                'highestRunIndex': runComparison!.highest.runIndex,
                'summary': runComparison!.summary,
              },
        'flowDeterminism': {
          'deterministic': flowDeterminism.deterministic,
          'explanation': flowDeterminism.explanation,
        },
        'recommendations': recommendations,
      };
}

/// Builds a [VarianceDiagnosis] from a completed [MultiRunSummary].
/// Returns `null` when there's nothing to diagnose: fewer than 2 valid
/// runs means there's no run-to-run variability to explain at all.
VarianceDiagnosis? diagnoseVariance(MultiRunSummary summary) {
  final runs = summary.validRuns;
  if (runs.length < 2 || summary.overBudgetPercent == null) return null;

  final contributors = <DimensionVariance>[
    DimensionVariance(label: 'Frame timing (over-budget %)', stats: summary.overBudgetPercent!),
    DimensionVariance(label: 'Jank clusters', stats: summary.jankClusterCount!),
    DimensionVariance(
      label: 'Slowest steady-state frame',
      stats: summary.slowestSteadyStateFrameMs!,
    ),
    DimensionVariance(
      label: 'Rebuild activity',
      stats: computeStats([for (final r in runs) r.rebuildCount.toDouble()]),
    ),
    if (runs.every((r) => r.heapDeltaBytes != null))
      DimensionVariance(
        label: 'Heap growth',
        stats: computeStats([for (final r in runs) r.heapDeltaBytes!.toDouble()]),
      ),
  ];

  final runComparison = _compareExtremeRuns(runs);
  final flowDeterminism = _assessFlowDeterminism(contributors);
  final overallStatus = summary.overBudgetPercent!.confidence;

  return VarianceDiagnosis(
    status: overallStatus,
    coefficientOfVariation: summary.overBudgetPercent!.coefficientOfVariation,
    contributors: contributors,
    unavailableDimensions: unobservableActivityDimensions,
    environment: summary.environment,
    runComparison: runComparison,
    flowDeterminism: flowDeterminism,
    recommendations: _buildRecommendations(
      status: overallStatus,
      environment: summary.environment,
    ),
  );
}

RunComparison _compareExtremeRuns(List<RunAnalysis> runs) {
  var lowest = runs.first;
  var highest = runs.first;
  for (final r in runs) {
    if (r.steadyState.overBudgetPercent < lowest.steadyState.overBudgetPercent) lowest = r;
    if (r.steadyState.overBudgetPercent > highest.steadyState.overBudgetPercent) highest = r;
  }

  final buffer = StringBuffer();
  if (identical(lowest, highest)) {
    buffer.write('All runs had the same over-budget %, so there is no extreme pair to compare.');
    return RunComparison(lowest: lowest, highest: highest, summary: buffer.toString());
  }

  final lowRebuilds = lowest.rebuildCount;
  final highRebuilds = highest.rebuildCount;
  final rebuildRatio = lowRebuilds == 0
      ? (highRebuilds == 0 ? 1.0 : double.infinity)
      : highRebuilds / lowRebuilds;

  buffer.write(
    'Run #${highest.runIndex} (${highest.steadyState.overBudgetPercent.toStringAsFixed(1)}% '
    'over budget) vs Run #${lowest.runIndex} '
    '(${lowest.steadyState.overBudgetPercent.toStringAsFixed(1)}%): ',
  );
  if (rebuildRatio >= substantialDifferenceRatio) {
    buffer.write(
      'Run #${highest.runIndex} performed substantially more rebuild work '
      '($highRebuilds rebuilds vs $lowRebuilds, ${rebuildRatio.toStringAsFixed(1)}x) -- consistent '
      'with (though not proof of) the frame-timing difference coming from the app doing more '
      'work, not just rendering the same work slower.',
    );
  } else {
    buffer.write(
      'rebuild counts were similar ($highRebuilds vs $lowRebuilds rebuilds, '
      '${rebuildRatio.toStringAsFixed(1)}x) despite the very different frame timing -- this '
      'points more toward environment/scheduling noise than the app doing different amounts '
      'of work between runs.',
    );
  }

  return RunComparison(lowest: lowest, highest: highest, summary: buffer.toString());
}

FlowDeterminismAssessment _assessFlowDeterminism(List<DimensionVariance> contributors) {
  final rebuildVariance =
      contributors.firstWhere((c) => c.label == 'Rebuild activity').stats;

  if (!flowScriptingAvailable) {
    if (rebuildVariance.isUnstable) {
      return FlowDeterminismAssessment(
        deterministic: false,
        explanation:
            'Flow behavior is not deterministic. No scripted interaction flow exists in this '
            'version of the tool -- capture is a fixed-duration passive window after launch, not '
            'a repeatable script -- but rebuild activity varied substantially between runs '
            '(CoV ${(rebuildVariance.coefficientOfVariation * 100).toStringAsFixed(1)}%) with no '
            'flow to hold constant. This measurement should not be treated as reproducible until '
            'a deterministic flow exists.',
      );
    }
    return const FlowDeterminismAssessment(
      deterministic: true,
      explanation:
          'No scripted interaction flow exists in this version of the tool, so flow determinism '
          'cannot be directly assessed -- but rebuild activity (the closest available proxy for '
          '"did the app do the same thing each run") was consistent across runs, which is at '
          'least not evidence against reproducibility.',
    );
  }
  // Unreachable while flowScriptingAvailable is false; kept for the day it
  // exists, so this function's shape doesn't need to change.
  return const FlowDeterminismAssessment(
    deterministic: true,
    explanation: 'Flow scripting is available but no assessment was implemented for it yet.',
  );
}

List<String> _buildRecommendations({
  required Confidence status,
  required EnvironmentMetadata? environment,
}) {
  if (status == Confidence.high) {
    return const [
      'Measurement is stable across runs -- over-budget % is a reasonable candidate for a '
          'future CI regression signal.',
    ];
  }

  final recommendations = <String>[];
  if (environment?.looksLikeEmulator ?? false) {
    recommendations.add(
      'Emulator environment may contribute to variance -- not confirmed, since this tool has '
      'no way to isolate environment noise from application behavior yet.',
    );
  }
  recommendations.add('Run on a physical device and/or make the flow deterministic.');
  return recommendations;
}

/// Renders a [VarianceDiagnosis] as the console `VARIANCE DIAGNOSIS`
/// section appended to the multi-run report.
String formatVarianceDiagnosis(VarianceDiagnosis diagnosis) {
  final buffer = StringBuffer();
  buffer.writeln('VARIANCE DIAGNOSIS');
  buffer.writeln('-' * 24);
  buffer.writeln('Status: ${diagnosis.status == Confidence.high ? 'STABLE' : 'UNSTABLE'}');
  buffer.writeln('CoV: ${(diagnosis.coefficientOfVariation * 100).toStringAsFixed(1)}%');
  buffer.writeln();

  final unstableContributors = diagnosis.contributors.where((c) => c.stats.isUnstable).toList();
  buffer.writeln('Potential contributors:');
  if (unstableContributors.isEmpty) {
    buffer.writeln('  (none -- every observable dimension was stable across runs)');
  } else {
    for (final c in unstableContributors) {
      final covPct = (c.stats.coefficientOfVariation * 100).toStringAsFixed(1);
      buffer.writeln('  ${c.label}: HIGH variance (CoV $covPct%)');
    }
  }
  buffer.writeln();
  buffer.writeln('Not observable with the current probe:');
  for (final label in diagnosis.unavailableDimensions) {
    buffer.writeln('  $label');
  }

  if (diagnosis.runComparison != null) {
    buffer.writeln();
    buffer.writeln('Run comparison:');
    buffer.writeln('  ${diagnosis.runComparison!.summary}');
  }

  buffer.writeln();
  buffer.writeln('Flow determinism:');
  buffer.writeln('  ${diagnosis.flowDeterminism.explanation}');

  buffer.writeln();
  final env = diagnosis.environment;
  buffer.writeln('Measurement environment:');
  buffer.writeln('  ${env == null ? 'unknown' : (env.looksLikeEmulator ? 'Emulator (heuristic: device id matched a known emulator/simulator pattern)' : 'Physical device (assumed -- device id did not match a known emulator/simulator pattern)')}');
  if (env != null) {
    buffer.writeln('  Device: ${env.device}');
    buffer.writeln('  Host: ${env.hostPlatform}');
    if (env.dartVmVersion != null) buffer.writeln('  Target Dart VM: ${env.dartVmVersion}');
  }

  buffer.writeln();
  buffer.writeln('Recommendation:');
  for (final r in diagnosis.recommendations) {
    buffer.writeln('  $r');
  }

  return buffer.toString();
}
