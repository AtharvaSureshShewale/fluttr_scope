import '../model/finding.dart';
import '../model/source_location.dart';
import 'stats.dart';
import 'widget_frame_impact.dart';

/// One widget's frame-impact evidence, aggregated across every run of a
/// multi-run measurement -- never built from a single run, so a widget
/// can't become a high-confidence finding because one run happened to be
/// bad (see [aggregateWidgetFrameImpactsAcrossRuns]).
class WidgetFrameImpactSummary {
  final SourceLocation location;
  final int totalRuns;
  final int runsObservedIn;
  final Stats rebuildCountStats;
  final Stats framesTouchedStats;
  final Stats overBudgetFrameCountStats;
  final Stats percentFramesOverBudgetStats;

  /// Cross-run stats of each run's *median* frame build+raster duration
  /// (ms) across the frames this widget touched -- see
  /// [WidgetFrameImpact.frameBuildStatsMs] for what this is and isn't
  /// (frame duration, not an isolated per-widget cost). `null` only if no
  /// run had any duration data for this widget at all.
  final Stats? frameDurationStatsMs;

  const WidgetFrameImpactSummary({
    required this.location,
    required this.totalRuns,
    required this.runsObservedIn,
    required this.rebuildCountStats,
    required this.framesTouchedStats,
    required this.overBudgetFrameCountStats,
    required this.percentFramesOverBudgetStats,
    this.frameDurationStatsMs,
  });

  /// Derived from *median* values across runs, not any single run's --
  /// the whole point of aggregating first.
  RebuildLevel get rebuildLevel =>
      rebuildCountStats.median >= highRebuildCountThreshold ? RebuildLevel.high : RebuildLevel.low;

  FrameImpactLevel get frameImpactLevel =>
      (overBudgetFrameCountStats.median >= highFrameImpactMinOverBudgetFrames &&
              percentFramesOverBudgetStats.median >= highFrameImpactMinPercent)
          ? FrameImpactLevel.high
          : FrameImpactLevel.low;

  ImpactClassification get classification {
    final highRebuild = rebuildLevel == RebuildLevel.high;
    final highImpact = frameImpactLevel == FrameImpactLevel.high;
    if (highRebuild && highImpact) return ImpactClassification.highRebuildHighImpact;
    if (highRebuild) return ImpactClassification.highRebuildLowImpact;
    if (highImpact) return ImpactClassification.lowRebuildHighImpact;
    return ImpactClassification.lowRebuildLowImpact;
  }

  /// The confidence attached to the frame-impact claim specifically --
  /// reusing the exact same CoV-derived [Confidence] machinery as the
  /// variance-diagnosis milestone, including its "fewer than 2 runs is
  /// always LOW" rule, which is what actually enforces "not a finding from
  /// one bad run" here.
  Confidence get confidence => percentFramesOverBudgetStats.confidence;

  Map<String, Object?> toJson() => {
        'location': location.toJson(),
        'totalRuns': totalRuns,
        'runsObservedIn': runsObservedIn,
        'rebuildCount': _statsToJson(rebuildCountStats),
        'framesTouched': _statsToJson(framesTouchedStats),
        'overBudgetFrameCount': _statsToJson(overBudgetFrameCountStats),
        'percentFramesOverBudget': _statsToJson(percentFramesOverBudgetStats),
        'frameDurationMs': frameDurationStatsMs == null ? null : _statsToJson(frameDurationStatsMs!),
        'classification': describeClassification(classification),
        'confidence': confidence.name,
      };
}

Map<String, Object?> _statsToJson(Stats s) => {
      'median': s.median,
      'mean': s.mean,
      'min': s.min,
      'max': s.max,
      'stdDev': s.stdDev,
      'coefficientOfVariation': s.coefficientOfVariation,
    };

/// Aggregates one [WidgetFrameImpact] list per run into cross-run
/// [WidgetFrameImpactSummary]s.
///
/// A widget observed in only some runs is padded with `0` for the runs it
/// wasn't observed in (not excluded) -- so a widget that only showed up in
/// 1 of 5 runs gets a low median and a low [Confidence], correctly
/// reflecting how inconsistent it was, rather than looking like a solid
/// n=1 "finding". [WidgetFrameImpactSummary.runsObservedIn] separately
/// reports how many runs it actually appeared in.
List<WidgetFrameImpactSummary> aggregateWidgetFrameImpactsAcrossRuns(
  List<List<WidgetFrameImpact>> perRunImpacts,
) {
  final totalRuns = perRunImpacts.length;
  final perRunByLocation = [
    for (final run in perRunImpacts) {for (final i in run) i.location: i},
  ];
  final allLocations = <SourceLocation>{
    for (final run in perRunImpacts)
      for (final i in run) i.location,
  };

  return [
    for (final location in allLocations)
      _summarize(location, totalRuns, perRunByLocation),
  ];
}

WidgetFrameImpactSummary _summarize(
  SourceLocation location,
  int totalRuns,
  List<Map<SourceLocation, WidgetFrameImpact>> perRunByLocation,
) {
  final rebuildCounts = <double>[];
  final framesTouched = <double>[];
  final overBudgetCounts = <double>[];
  final percents = <double>[];
  final frameDurations = <double>[];
  var runsObservedIn = 0;

  for (final runMap in perRunByLocation) {
    final impact = runMap[location];
    if (impact != null) {
      runsObservedIn++;
      rebuildCounts.add(impact.rebuildCount.toDouble());
      framesTouched.add(impact.framesRebuiltIn.length.toDouble());
      overBudgetCounts.add(impact.overBudgetFrameCount.toDouble());
      percents.add(impact.percentFramesOverBudget);
      if (impact.frameBuildStatsMs != null) frameDurations.add(impact.frameBuildStatsMs!.median);
    } else {
      rebuildCounts.add(0);
      framesTouched.add(0);
      overBudgetCounts.add(0);
      percents.add(0);
    }
  }

  return WidgetFrameImpactSummary(
    location: location,
    totalRuns: totalRuns,
    runsObservedIn: runsObservedIn,
    rebuildCountStats: computeStats(rebuildCounts),
    framesTouchedStats: computeStats(framesTouched),
    overBudgetFrameCountStats: computeStats(overBudgetCounts),
    percentFramesOverBudgetStats: computeStats(percents),
    frameDurationStatsMs: frameDurations.isEmpty ? null : computeStats(frameDurations),
  );
}

/// A static finding whose location also has runtime frame-impact evidence.
class MatchedFinding {
  final Finding finding;
  final WidgetFrameImpactSummary impact;

  const MatchedFinding({required this.finding, required this.impact});
}

/// A static finding whose location was never observed rebuilding in any
/// run -- explicitly reported as such, per this milestone's requirement
/// to never attach runtime evidence to a finding that wasn't exercised.
class NotExercisedFinding {
  final Finding finding;

  const NotExercisedFinding({required this.finding});
}

/// A widget with significant rebuild/frame evidence but no matching static
/// finding at its location -- real runtime signal a static rule doesn't
/// (and, per this milestone's scope, shouldn't) explain. Only surfaced for
/// [ImpactClassification.highRebuildHighImpact] widgets; anything less
/// isn't a "finding", just unremarkable activity.
class RuntimeOnlyFinding {
  final WidgetFrameImpactSummary impact;

  const RuntimeOnlyFinding({required this.impact});
}

class RebuildFrameCorrelationResult {
  final List<MatchedFinding> matched;
  final List<NotExercisedFinding> notExercised;
  final List<RuntimeOnlyFinding> runtimeOnly;

  const RebuildFrameCorrelationResult({
    required this.matched,
    required this.notExercised,
    required this.runtimeOnly,
  });
}

/// Orders impacts by how strongly they point at a performance problem:
/// more slow frames first, then more rebuilds.
int compareImpactStrength(WidgetFrameImpactSummary a, WidgetFrameImpactSummary b) {
  final bySlow = a.overBudgetFrameCountStats.median.compareTo(b.overBudgetFrameCountStats.median);
  return bySlow != 0 ? bySlow : a.rebuildCountStats.median.compareTo(b.rebuildCountStats.median);
}

/// Joins [staticFindings] to [widgetImpacts] by exact source location --
/// the same join key every other correlation in this package uses.
/// [staticFindings] is typically pre-filtered by the caller (e.g. to
/// performance-category findings) the same way `security_command.dart`
/// filters to security findings before correlating; this function itself
/// makes no category assumption.
RebuildFrameCorrelationResult correlateRebuildsToFrames(
  List<Finding> staticFindings,
  List<WidgetFrameImpactSummary> widgetImpacts,
) {
  final byLocation = {for (final w in widgetImpacts) w.location: w};
  final matchedLocations = <SourceLocation>{};

  final matched = <MatchedFinding>[];
  final notExercised = <NotExercisedFinding>[];
  for (final finding in staticFindings) {
    final impact = finding.recordIn(byLocation, compareImpactStrength);
    if (impact != null) {
      matched.add(MatchedFinding(finding: finding, impact: impact));
      matchedLocations.add(impact.location);
    } else {
      notExercised.add(NotExercisedFinding(finding: finding));
    }
  }

  final runtimeOnly = [
    for (final impact in widgetImpacts)
      if (!matchedLocations.contains(impact.location) &&
          impact.classification == ImpactClassification.highRebuildHighImpact)
        RuntimeOnlyFinding(impact: impact),
  ];

  return RebuildFrameCorrelationResult(
    matched: matched,
    notExercised: notExercised,
    runtimeOnly: runtimeOnly,
  );
}

String _round(double v) => v.round().toString();

/// Renders one [WidgetFrameImpactSummary] as the `PERFORMANCE FINDING` /
/// `RUNTIME-ONLY PERFORMANCE FINDING` block.
///
/// Deliberately does not print a widget *name* ("ProductCard") or an
/// isolated "total build time" for the widget -- neither is available
/// from this probe (see `widget_frame_impact.dart`'s docs): there's no
/// per-instance widget identity in the rebuild-count event stream, only a
/// creation location, and no per-widget share of a frame's build time,
/// only the frame's total. Printing either would be fabricated precision.
/// Source location is the identity; frame duration stats describe the
/// *frames touched*, not the widget's own isolated cost.
String formatWidgetFrameImpact(
  WidgetFrameImpactSummary impact, {
  required String header,
  Finding? matchedFinding,
}) {
  final buffer = StringBuffer();
  buffer.writeln(header);
  buffer.writeln('-' * 24);
  buffer.writeln('Source: ${impact.location}');
  if (matchedFinding != null) {
    buffer.writeln('Rule: ${matchedFinding.ruleId} -- ${matchedFinding.message}');
  } else {
    buffer.writeln('Rule: (none -- no static rule flags this location)');
  }
  buffer.writeln();
  buffer.writeln(
    'Rebuilds (median across ${impact.totalRuns} run(s)): '
    '${_round(impact.rebuildCountStats.median)} '
    '(range ${_round(impact.rebuildCountStats.min)}-${_round(impact.rebuildCountStats.max)}, '
    'stdDev ${impact.rebuildCountStats.stdDev.toStringAsFixed(1)})',
  );
  buffer.writeln('Observed in: ${impact.runsObservedIn}/${impact.totalRuns} run(s)');
  buffer.writeln(
    'Associated over-budget frames (median): '
    '${_round(impact.overBudgetFrameCountStats.median)} '
    '(${impact.percentFramesOverBudgetStats.median.toStringAsFixed(1)}% of frames touched)',
  );
  buffer.writeln();
  buffer.writeln('Rebuild volume: ${impact.rebuildLevel.name.toUpperCase()}');
  buffer.writeln('Frame impact: ${impact.frameImpactLevel.name.toUpperCase()}');
  buffer.writeln('Classification: ${describeClassification(impact.classification)}');
  buffer.writeln('Measurement confidence: ${impact.confidence.name.toUpperCase()}');
  buffer.writeln();
  buffer.writeln(
    'Evidence: This location\'s rebuild activity overlapped '
    '${_round(impact.overBudgetFrameCountStats.median)} over-budget frame(s) (median across '
    'runs), out of ${_round(impact.rebuildCountStats.median)} rebuilds across '
    '${_round(impact.framesTouchedStats.median)} frames touched.',
  );
  buffer.writeln(
    'Important: This is an observed temporal association between rebuild activity and frame '
    'timing, not a proven causal relationship.',
  );
  return buffer.toString();
}

/// Renders a full [RebuildFrameCorrelationResult]: one block per matched
/// finding with runtime evidence, one per runtime-only high-impact widget,
/// and a compact list of statically-flagged locations that were never
/// observed rebuilding at all (`NOT EXERCISED` -- explicitly reported,
/// never silently dropped, and never given fabricated runtime evidence).
String formatRebuildFrameCorrelation(RebuildFrameCorrelationResult result) {
  final buffer = StringBuffer();
  buffer.writeln('REBUILD-TO-FRAME CORRELATION');
  buffer.writeln('=' * 29);

  if (result.matched.isEmpty && result.runtimeOnly.isEmpty && result.notExercised.isEmpty) {
    buffer.writeln();
    buffer.writeln('No performance findings and no rebuild activity to correlate.');
    return buffer.toString();
  }

  for (final m in result.matched) {
    buffer.writeln();
    buffer.write(formatWidgetFrameImpact(
      m.impact,
      header: 'PERFORMANCE FINDING',
      matchedFinding: m.finding,
    ));
  }

  for (final r in result.runtimeOnly) {
    buffer.writeln();
    buffer.write(formatWidgetFrameImpact(r.impact, header: 'RUNTIME-ONLY PERFORMANCE FINDING'));
  }

  if (result.notExercised.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('NOT EXERCISED (${result.notExercised.length}):');
    buffer.writeln(
      '  Static finding(s) below were never observed rebuilding during any run -- no runtime '
      'evidence is attached; this does not mean the finding is wrong, only that this capture '
      'never exercised that code path.',
    );
    for (final n in result.notExercised) {
      buffer.writeln('  ${n.finding.location}  ${n.finding.ruleId}');
    }
  }

  return buffer.toString();
}
