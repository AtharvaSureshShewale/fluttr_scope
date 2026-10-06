import 'environment_metadata.dart';
import 'frame_budget.dart';
import 'run_timeline.dart';
import 'runtime_driver.dart';
import 'stats.dart';
import 'widget_frame_impact.dart';

/// Minimum steady-state frames for a run to be usable at all -- below
/// this, "over-budget %" and "slowest frame" are noise, not a
/// measurement. Stated explicitly as a judgment call: 10 frames is a
/// handful of seconds even in a bad case, enough to not be a single
/// fluke frame, not a claim about statistical sufficiency.
const minSteadyStateFramesPerRun = 10;

/// One run that could not produce a usable measurement -- kept as data
/// (never silently dropped or turned into a zero), so a report can say
/// exactly how many runs were attempted versus how many were valid, and
/// why the rest weren't.
class InvalidRun {
  final int runIndex;
  final String reason;

  const InvalidRun({required this.runIndex, required this.reason});

  Map<String, Object?> toJson() => {'runIndex': runIndex, 'reason': reason};
}

/// One run's derived frame-budget analysis, after warm-up splitting.
///
/// [rebuildCount], [heapDeltaBytes], [buildTimeStatsMs], [rasterTimeStatsMs],
/// and [timeline] are all optional, defaulting to "not available" (`0`/
/// `null`) rather than required -- they were added for variance diagnosis
/// after the frame-budget fields above already existed and were tested;
/// keeping them optional means every existing call site (and every
/// existing test) keeps compiling and behaving identically without
/// updating.
class RunAnalysis {
  final int runIndex;
  final FrameBudgetSummary steadyState;
  final FrameBudgetSummary startup;

  /// Total rebuild count across every location, this run -- the one
  /// "application activity" signal the probe can actually observe (via
  /// the same `Flutter.RebuiltWidgets` events `measure` already uses).
  final int rebuildCount;

  /// Retained-heap delta (bytes) for this run, or `null` if not captured.
  final int? heapDeltaBytes;

  /// Per-frame build/raster time statistics (median/mean/CoV/...) across
  /// *every* steady-state frame in this run, not just the slowest one --
  /// computed from the same frame list [steadyState] was built from,
  /// before that detail was discarded.
  final Stats? buildTimeStatsMs;
  final Stats? rasterTimeStatsMs;

  final RunTimeline? timeline;
  final String? dartVmVersion;

  /// Per-widget-location rebuild-to-frame impact, computed from this run's
  /// steady-state frames only (see `widget_frame_impact.dart`).
  final List<WidgetFrameImpact> widgetFrameImpacts;

  const RunAnalysis({
    required this.runIndex,
    required this.steadyState,
    required this.startup,
    this.rebuildCount = 0,
    this.heapDeltaBytes,
    this.buildTimeStatsMs,
    this.rasterTimeStatsMs,
    this.timeline,
    this.dartVmVersion,
    this.widgetFrameImpacts = const [],
  });

  /// Steady-state slowest frame's total duration in milliseconds. Safe to
  /// assume non-null: a [RunAnalysis] only exists for a run that passed
  /// the [minSteadyStateFramesPerRun] validity check, so [steadyState]
  /// always has at least one frame.
  double get slowestSteadyStateFrameMs =>
      (steadyState.slowestFrame!.build + steadyState.slowestFrame!.raster).inMicroseconds / 1000;

  /// Startup's slowest frame's total duration in milliseconds, or `null`
  /// if this run captured no startup frames (e.g. warm-up was 0).
  double? get slowestStartupFrameMs {
    final f = startup.slowestFrame;
    if (f == null) return null;
    return (f.build + f.raster).inMicroseconds / 1000;
  }
}

/// Everything produced by a `--runs=N` multi-run measurement: per-run raw
/// analysis, invalid runs with reasons, and cross-run statistics for each
/// headline metric -- computed by taking each metric *per run first*,
/// then summarizing those per-run values, never by concatenating raw
/// frames across runs into one pool.
class MultiRunSummary {
  final int requestedRuns;
  final Duration warmup;
  final Duration captureDuration;
  final List<RunAnalysis> validRuns;
  final List<InvalidRun> invalidRuns;

  /// `null` only when [validRuns] is empty -- there is nothing to compute
  /// statistics over.
  final Stats? overBudgetPercent;
  final Stats? jankClusterCount;
  final Stats? slowestSteadyStateFrameMs;

  /// Worst single startup frame observed across all valid runs (just the
  /// worst-case number, not full stats -- startup is inherently a
  /// one-shot event per run, not a repeated steady-state condition, so a
  /// median/CoV over it is less meaningful). `null` if no run captured
  /// any startup frames (e.g. `warmup` was 0).
  final double? startupWorstFrameMs;

  /// The most common bottleneck classification among valid runs' over-
  /// budget steady-state slowest frames. `null` if no valid run had any
  /// over-budget frame to classify.
  final FrameBottleneck? dominantBottleneck;

  /// `null` when the caller (e.g. a test) didn't supply one -- optional
  /// for the same reason [RunAnalysis]'s new fields are optional.
  final EnvironmentMetadata? environment;

  const MultiRunSummary({
    required this.requestedRuns,
    required this.warmup,
    required this.captureDuration,
    required this.validRuns,
    required this.invalidRuns,
    required this.overBudgetPercent,
    required this.jankClusterCount,
    required this.slowestSteadyStateFrameMs,
    required this.startupWorstFrameMs,
    required this.dominantBottleneck,
    this.environment,
  });

  Map<String, Object?> toJson() => {
        'requestedRuns': requestedRuns,
        'warmupSeconds': warmup.inSeconds,
        'captureSeconds': captureDuration.inSeconds,
        'validRunCount': validRuns.length,
        'invalidRuns': invalidRuns.map((r) => r.toJson()).toList(),
        'overBudgetPercent': _statsToJson(overBudgetPercent),
        'jankClusterCount': _statsToJson(jankClusterCount),
        'slowestSteadyStateFrameMs': _statsToJson(slowestSteadyStateFrameMs),
        'startupWorstFrameMs': startupWorstFrameMs,
        'dominantBottleneck': dominantBottleneck?.name,
        'environment': environment?.toJson(),
      };
}

Map<String, Object?>? _statsToJson(Stats? stats) {
  if (stats == null) return null;
  return {
    'values': stats.values,
    'median': stats.median,
    'mean': stats.mean,
    'min': stats.min,
    'max': stats.max,
    'stdDev': stats.stdDev,
    'coefficientOfVariation': stats.coefficientOfVariation,
    'confidence': stats.confidence.name,
  };
}

/// Runs `RuntimeDriver().measure()` [runs] times, sequentially -- each a
/// full launch/relaunch/shutdown cycle, matching the existing single-run
/// behavior exactly for each individual attempt (this does not change
/// [RuntimeDriver] at all, only calls it repeatedly). [warmup] is applied
/// independently to every run's own frames; runs are never pooled before
/// splitting or summarizing.
///
/// A run that throws (launch failure, VM Service connection failure,
/// the rebuild-tracking extension never registering) or that captures
/// fewer than [minSteadyStateFramesPerRun] steady-state frames is recorded
/// as an [InvalidRun] with the reason, and the remaining runs still
/// proceed -- one flaky launch shouldn't discard every other run.
Future<MultiRunSummary> measureMultipleRuns({
  required String targetPath,
  required int runs,
  required Duration duration,
  required Duration warmup,
  required String device,
  Duration launchTimeout = const Duration(minutes: 5),
  void Function(String line)? onLaunchOutput,
  void Function(int runIndex, int totalRuns)? onRunStart,
}) async {
  final validRuns = <RunAnalysis>[];
  final invalidRuns = <InvalidRun>[];
  String? dartVmVersion;

  for (var i = 1; i <= runs; i++) {
    onRunStart?.call(i, runs);
    try {
      final result = await RuntimeDriver().measure(
        targetPath,
        duration: duration,
        device: device,
        launchTimeout: launchTimeout,
        onLaunchOutput: onLaunchOutput,
      );
      dartVmVersion ??= result.dartVmVersion;
      final capture = splitByWarmup(result.frames, warmup);
      if (capture.steadyState.length < minSteadyStateFramesPerRun) {
        invalidRuns.add(InvalidRun(
          runIndex: i,
          reason: 'only ${capture.steadyState.length} steady-state frame(s) captured '
              '(minimum $minSteadyStateFramesPerRun) -- warm-up may exceed the capture '
              'duration, or too few frames rendered',
        ));
        continue;
      }
      final steadyFrameNumbers = {for (final f in capture.steadyState) f.frameNumber};
      final steadyPerFrameRebuilds = [
        for (final r in result.perFrameRebuilds)
          if (steadyFrameNumbers.contains(r.frameNumber)) r,
      ];

      validRuns.add(RunAnalysis(
        runIndex: i,
        steadyState: summarizeFrameBudget(capture.steadyState),
        startup: summarizeFrameBudget(capture.startup),
        rebuildCount: result.rebuilds.fold(0, (sum, r) => sum + r.rebuildCount),
        heapDeltaBytes: result.heapUsage.deltaBytes,
        buildTimeStatsMs: computeStats(
          [for (final f in capture.steadyState) f.build.inMicroseconds / 1000],
        ),
        rasterTimeStatsMs: computeStats(
          [for (final f in capture.steadyState) f.raster.inMicroseconds / 1000],
        ),
        timeline: buildRunTimeline(result.frames, warmup: warmup, launchedAt: result.launchedAt),
        dartVmVersion: result.dartVmVersion,
        widgetFrameImpacts: computeWidgetFrameImpacts(steadyPerFrameRebuilds, capture.steadyState),
      ));
    } catch (e) {
      invalidRuns.add(InvalidRun(runIndex: i, reason: e.toString()));
    }
  }

  return summarizeRuns(
    requestedRuns: runs,
    warmup: warmup,
    captureDuration: duration,
    validRuns: validRuns,
    invalidRuns: invalidRuns,
    environment: detectEnvironment(device: device, dartVmVersion: dartVmVersion),
  );
}

/// Builds a [MultiRunSummary] from already-computed per-run analyses --
/// split out from [measureMultipleRuns] so the aggregation logic (the
/// part with actual decisions to test) can be exercised with synthetic
/// [RunAnalysis] data, with no device or process involved.
MultiRunSummary summarizeRuns({
  required int requestedRuns,
  required Duration warmup,
  required Duration captureDuration,
  required List<RunAnalysis> validRuns,
  required List<InvalidRun> invalidRuns,
  EnvironmentMetadata? environment,
}) {
  if (validRuns.isEmpty) {
    return MultiRunSummary(
      requestedRuns: requestedRuns,
      warmup: warmup,
      captureDuration: captureDuration,
      validRuns: validRuns,
      invalidRuns: invalidRuns,
      environment: environment,
      overBudgetPercent: null,
      jankClusterCount: null,
      slowestSteadyStateFrameMs: null,
      startupWorstFrameMs: null,
      dominantBottleneck: null,
    );
  }

  final startupWorstValues = [
    for (final run in validRuns)
      if (run.slowestStartupFrameMs != null) run.slowestStartupFrameMs!,
  ];

  return MultiRunSummary(
    requestedRuns: requestedRuns,
    warmup: warmup,
    captureDuration: captureDuration,
    validRuns: validRuns,
    invalidRuns: invalidRuns,
    environment: environment,
    overBudgetPercent: computeStats([for (final r in validRuns) r.steadyState.overBudgetPercent]),
    jankClusterCount:
        computeStats([for (final r in validRuns) r.steadyState.jankClusters.length.toDouble()]),
    slowestSteadyStateFrameMs:
        computeStats([for (final r in validRuns) r.slowestSteadyStateFrameMs]),
    startupWorstFrameMs:
        startupWorstValues.isEmpty ? null : startupWorstValues.reduce((a, b) => a > b ? a : b),
    dominantBottleneck: _dominantBottleneck(validRuns),
  );
}

/// Majority vote among valid runs' steady-state slowest-frame bottleneck
/// classification -- only counting runs that actually had an over-budget
/// frame to classify (classifying a frame that was already within budget
/// isn't meaningful). Ties are broken by a fixed, documented precedence
/// (build, then raster, then combined) purely so the result is
/// deterministic, not because build "wins" ties for any principled reason.
FrameBottleneck? _dominantBottleneck(List<RunAnalysis> runs) {
  final votes = <FrameBottleneck, int>{};
  for (final run in runs) {
    final slowest = run.steadyState.slowestFrame;
    if (slowest == null || run.steadyState.framesOverBudget == 0) continue;
    final b = classifyBottleneck(slowest);
    votes[b] = (votes[b] ?? 0) + 1;
  }
  if (votes.isEmpty) return null;

  FrameBottleneck? winner;
  var winnerVotes = -1;
  for (final b in const [FrameBottleneck.build, FrameBottleneck.raster, FrameBottleneck.combined]) {
    final v = votes[b] ?? 0;
    if (v > winnerVotes) {
      winner = b;
      winnerVotes = v;
    }
  }
  return winner;
}

String _pct(double v) => '${v.toStringAsFixed(1)}%';
String _ms(double v) => '${v.toStringAsFixed(1)}ms';
String _cov(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// A [Stats] block's median/range/stability lines, indented for the
/// console report. Includes an explicit "unstable" warning -- never just
/// a quiet number -- whenever [Stats.isUnstable] is true, so a noisy
/// metric can't be mistaken for a trustworthy one by omission.
String _formatStatsBlock(
  Stats stats, {
  required String Function(double) format,
}) {
  final buffer = StringBuffer();
  buffer.writeln('  Median: ${format(stats.median)}');
  buffer.writeln('  Range: ${format(stats.min)} - ${format(stats.max)}');
  buffer.writeln('  Std dev: ${format(stats.stdDev)}  (CoV: ${_cov(stats.coefficientOfVariation)})');
  buffer.writeln('  Stability: ${stats.confidence.name.toUpperCase()}');
  if (stats.isUnstable) {
    buffer.writeln(
      '  ⚠ UNSTABLE -- this metric varied enough between runs '
      '(CoV ${_cov(stats.coefficientOfVariation)}) that it should not be used as a '
      'CI gate without investigating the variance source (thermal throttling, '
      'background processes, emulator scheduling jitter, ...). Raw per-run '
      'values are listed under Runs: below.',
    );
  }
  return buffer.toString();
}

/// Renders a [MultiRunSummary] as the multi-run console report -- the
/// `--runs > 1` counterpart to `formatFrameCapture`'s single-run report.
String formatMultiRunReport(MultiRunSummary summary) {
  final buffer = StringBuffer();

  buffer.writeln('RUNTIME PERFORMANCE');
  buffer.writeln('-' * 31);
  buffer.writeln();
  buffer.writeln(
    'Runs: ${summary.requestedRuns} '
    '(${summary.validRuns.length} valid, ${summary.invalidRuns.length} invalid)',
  );
  buffer.writeln('Warm-up: ${summary.warmup.inSeconds}s');
  buffer.writeln('Measurement: ${summary.captureDuration.inSeconds}s');

  if (summary.invalidRuns.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('INVALID RUNS (${summary.invalidRuns.length}):');
    for (final invalid in summary.invalidRuns) {
      buffer.writeln('  #${invalid.runIndex}  ${invalid.reason}');
    }
  }

  if (summary.validRuns.isEmpty) {
    buffer.writeln();
    buffer.writeln(
      'No valid runs -- no statistics to report. Every run failed or produced '
      'too few steady-state frames; see INVALID RUNS above.',
    );
    return buffer.toString();
  }

  buffer.writeln();
  buffer.writeln('STEADY STATE');
  buffer.writeln();
  buffer.writeln('Over budget:');
  buffer.write(_formatStatsBlock(summary.overBudgetPercent!, format: _pct));
  buffer.writeln();
  buffer.writeln('Jank clusters:');
  buffer.write(_formatStatsBlock(summary.jankClusterCount!, format: (v) => v.toStringAsFixed(1)));
  buffer.writeln();
  buffer.writeln('Slowest frame:');
  buffer.write(_formatStatsBlock(summary.slowestSteadyStateFrameMs!, format: _ms));

  buffer.writeln();
  buffer.writeln(
    'Bottleneck: ${summary.dominantBottleneck == null ? 'n/a (no over-budget frames)' : summary.dominantBottleneck!.name.toUpperCase()}',
  );

  if (summary.startupWorstFrameMs != null) {
    buffer.writeln();
    buffer.writeln('STARTUP');
    buffer.writeln('  Worst observed: ${_ms(summary.startupWorstFrameMs!)}');
  }

  buffer.writeln();
  buffer.writeln('Runs:');
  for (final run in summary.validRuns) {
    buffer.writeln(
      '  #${run.runIndex}  ${_pct(run.steadyState.overBudgetPercent)}  '
      '${run.steadyState.jankClusters.length} jank cluster(s)  '
      'slowest=${_ms(run.slowestSteadyStateFrameMs)}',
    );
  }

  buffer.writeln();
  buffer.writeln(
    'Confidence: ${summary.overBudgetPercent!.confidence.name.toUpperCase()} '
    '(over-budget % is the primary CI-gate candidate metric)',
  );

  return buffer.toString();
}
