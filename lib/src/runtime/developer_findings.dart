import 'package:path/path.dart' as p;

import '../model/finding.dart';
import '../model/source_location.dart';
import 'frame_budget.dart';
import 'rebuild_frame_correlation.dart';
import 'stats.dart';
import 'unified_finding.dart';
import 'widget_frame_impact.dart';

// ---------------------------------------------------------------------
// Presentation only. All correlation/classification/priority logic lives
// in unified_finding.dart -- this file turns a UnifiedFinding into text
// and nothing else. Every string below is built from real fields on
// UnifiedFinding/WidgetFrameImpactSummary/Finding; none of it is invented
// per finding. Static text (whatToCheck, whyItMatters) is a fixed lookup
// by severity, not computed per-widget, since it's investigation
// guidance, not a claim about this specific widget's cause.
// ---------------------------------------------------------------------

String _shortLabel(SourceLocation loc) =>
    '${p.basenameWithoutExtension(loc.file)} (line ${loc.line})';

String _round(double v) => v.round().toString();

String titleFor(UnifiedFinding f) {
  final label = _shortLabel(f.location);
  if (f.relation == FindingRelation.notExercised) {
    return 'Not tested in this runtime flow';
  }
  if (f.severity == FindingSeverity.inconsistent) {
    return f.staticFinding != null
        ? 'Static issue found, but runtime evidence is inconclusive'
        : 'Performance measurement is inconsistent';
  }
  final hasStatic = f.staticFinding != null;
  return switch (f.severity) {
    FindingSeverity.inconsistent => 'Performance measurement is inconsistent', // unreachable, see above
    FindingSeverity.healthy => '$label looks healthy',
    FindingSeverity.check => '$label rebuilds frequently',
    FindingSeverity.investigate =>
      hasStatic ? '$label may be affecting slow frames' : '$label may be affecting slow frames',
    FindingSeverity.highPriority => hasStatic
        ? '$label is rebuilding during slow frames, backed by a static finding'
        : '$label is rebuilding during slow frames',
  };
}

/// "What happened?" -- built directly from the widget's median evidence.
String whatHappened(WidgetFrameImpactSummary impact) {
  final rebuilds = _round(impact.rebuildCountStats.median);
  final touched = _round(impact.framesTouchedStats.median);
  final overBudget = _round(impact.overBudgetFrameCountStats.median);
  return 'This widget rebuilt $rebuilds times during the measured window '
      '(median across ${impact.totalRuns} run(s)). $overBudget of the $touched frames in which it '
      'rebuilt were slow.';
}

String whyItMatters(FindingSeverity severity) => switch (severity) {
      FindingSeverity.healthy =>
        'This widget rebuilt occasionally and showed little measurable impact on slow frames.',
      FindingSeverity.check => 'This widget rebuilt frequently, but the current runtime evidence '
          'does not show a strong relationship with slow frames.',
      FindingSeverity.investigate => 'This widget did not rebuild often, but the frames in which '
          'it rebuilt were frequently slow. It may be worth investigating.',
      FindingSeverity.highPriority => 'This widget rebuilt frequently and its rebuilds '
          'consistently occurred during slow frames. It is a high-priority candidate for '
          'investigation.',
      FindingSeverity.inconsistent => 'The same measurement produced substantially different '
          'runtime results between runs, so we cannot confidently identify this as a reproducible '
          'application performance issue.',
    };

String whatToCheck(FindingSeverity severity) => switch (severity) {
      FindingSeverity.healthy => 'No immediate performance action is recommended.',
      FindingSeverity.check => 'The widget rebuilds frequently, but current evidence does not '
          'show meaningful frame impact. Only investigate if you observe a user-visible problem.',
      FindingSeverity.investigate => 'Investigate what work happens when this widget rebuilds. '
          'The rebuilds are relatively infrequent, but they overlap with slow frames.',
      FindingSeverity.highPriority => 'Check whether this widget is listening to state that it '
          'doesn\'t actually use. Consider moving rapidly changing state closer to the widget '
          'that consumes it.',
      FindingSeverity.inconsistent => 'Try the same measurement on a physical device and/or make '
          'the tested flow more deterministic, then remeasure.',
    };

/// "Evidence" -- the simple bullet list, in developer language. Always
/// includes median, range, run-to-run variation, confidence, and how many
/// runs were used, shown for every finding (not just unstable ones) since
/// more context never hurts. The "how sure we are" line uses the same
/// [headerFor] label as the block's own header, so it can never contradict
/// it (e.g. a runtime-only finding headered as an issue worth investigating
/// must not then claim "HIGH PRIORITY" two sections later).
List<String> evidenceLines(UnifiedFinding f) {
  final impact = f.impact!;
  final (icon, label) = headerFor(f);
  return [
    'Rebuilds: ${_round(impact.rebuildCountStats.median)} '
        '(range ${_round(impact.rebuildCountStats.min)}-${_round(impact.rebuildCountStats.max)})',
    'Frames touched: ${_round(impact.framesTouchedStats.median)}',
    'Slow frames: ${_round(impact.overBudgetFrameCountStats.median)}',
    'Slow-frame overlap: ${impact.percentFramesOverBudgetStats.median.toStringAsFixed(0)}% '
        '(range ${impact.percentFramesOverBudgetStats.min.toStringAsFixed(0)}-'
        '${impact.percentFramesOverBudgetStats.max.toStringAsFixed(0)}%)',
    'Run-to-run variation: '
        '${(impact.percentFramesOverBudgetStats.coefficientOfVariation * 100).toStringAsFixed(0)}%',
    'How sure we are: $label $icon',
    'Runs used: ${impact.runsObservedIn}/${impact.totalRuns}',
  ];
}

/// "Why am I seeing this?" -- a numbered list of the actual observations
/// that led to [impact.classification], never an invented narrative.
List<String> whyAmISeeing(WidgetFrameImpactSummary impact) {
  final rebuilds = _round(impact.rebuildCountStats.median);
  final touched = _round(impact.framesTouchedStats.median);
  final overBudget = _round(impact.overBudgetFrameCountStats.median);
  final metRequirement = impact.confidence != Confidence.low;
  return [
    'This code rebuilt $rebuilds times (median across ${impact.totalRuns} run(s)).',
    'The measured flow exercised this widget in ${impact.runsObservedIn}/${impact.totalRuns} run(s).',
    '$overBudget of the $touched frames containing its rebuild activity were slow (median).',
    'The measurement was repeated across ${impact.totalRuns} run(s).',
    metRequirement
        ? 'The result met the configured confidence requirements (${impact.confidence.name}).'
        : 'The result did NOT meet the configured confidence requirements '
            '(${impact.confidence.name}) -- run-to-run results varied too much to trust.',
  ];
}

/// "Technical details" -- the raw evidence, technical terminology
/// included, for developers who want to dig in. Fields this probe cannot
/// supply (per-widget isolated build/raster split) are stated as
/// unavailable rather than omitted silently.
List<String> technicalDetailsLines(WidgetFrameImpactSummary impact, {Finding? staticFinding}) {
  final lines = <String>[
    if (staticFinding != null) 'Rule: ${staticFinding.ruleId}',
    if (staticFinding != null) 'Static severity: ${staticFinding.severity.name}',
    'Source location: ${impact.location}',
    'Widget identity: creation location only (no per-instance id available)',
    'Attribution method: exact frame-number join (Flutter.RebuiltWidgets '
        'frameNumber == Flutter.Frame frameNumber)',
    'Rebuild count -- median: ${impact.rebuildCountStats.median.toStringAsFixed(1)}, '
        'mean: ${impact.rebuildCountStats.mean.toStringAsFixed(1)}, '
        'min: ${impact.rebuildCountStats.min.toStringAsFixed(0)}, '
        'max: ${impact.rebuildCountStats.max.toStringAsFixed(0)}, '
        'stdDev: ${impact.rebuildCountStats.stdDev.toStringAsFixed(1)}, '
        'CoV: ${(impact.rebuildCountStats.coefficientOfVariation * 100).toStringAsFixed(1)}%',
    'Frames touched -- median: ${impact.framesTouchedStats.median.toStringAsFixed(1)}',
    'Over-budget frames -- median: ${impact.overBudgetFrameCountStats.median.toStringAsFixed(1)}, '
        'CoV: ${(impact.overBudgetFrameCountStats.coefficientOfVariation * 100).toStringAsFixed(1)}%',
    'Overlap percentage -- median: ${impact.percentFramesOverBudgetStats.median.toStringAsFixed(1)}%, '
        'CoV: ${(impact.percentFramesOverBudgetStats.coefficientOfVariation * 100).toStringAsFixed(1)}%',
    if (impact.frameDurationStatsMs != null)
      'Frame duration (build+raster combined, not this widget\'s isolated cost) -- median: '
          '${impact.frameDurationStatsMs!.median.toStringAsFixed(1)}ms'
    else
      'Frame duration: not available for this widget',
    'Assumed frame budget: ${(defaultFrameBudget.inMicroseconds / 1000).toStringAsFixed(1)}ms '
        '(60Hz assumption, not a measured refresh rate)',
    'Runs: ${impact.totalRuns} total, ${impact.runsObservedIn} observed in',
    'Confidence: ${impact.confidence.name}',
    'Classification: ${describeClassification(impact.classification)}',
    'Frame IDs: specific to each run\'s own numbering, not comparable across runs -- see raw '
        'JSON output (--format=json) for exact per-run frame numbers.',
  ];
  return lines;
}

/// The mandatory causation disclaimer -- present on every finding that has
/// runtime evidence, worded exactly to avoid implying causation.
const causationDisclaimer =
    'This is an observed temporal association, not a proven causal relationship. The evidence '
    'shows this widget\'s rebuilds overlapped slow frames -- it does not establish that the '
    'rebuilds (or the static issue) caused those frames to be slow.';

/// The header icon/label for one finding -- special-cased for
/// [FindingRelation.runtimeOnly] and [FindingRelation.notExercised], which
/// mandate a fixed presentation regardless of the underlying quadrant;
/// standalone and matched findings use the real classification-derived
/// severity.
(String icon, String label) headerFor(UnifiedFinding f) => switch (f.relation) {
      FindingRelation.notExercised => ('⚪', 'NOT TESTED'),
      FindingRelation.runtimeOnly when f.severity != FindingSeverity.inconsistent =>
        ('🟠', 'RUNTIME PERFORMANCE ISSUE'),
      _ => severityPresentation(f.severity),
    };

/// Renders one [UnifiedFinding] as the full developer format: severity,
/// title, source location, the paired-evidence explanation (matched /
/// runtime-only / not-exercised, as applicable), What happened / Why it
/// matters / Evidence / What to check / Why am I seeing this / Why is
/// this prioritized, the causation disclaimer, and Technical details.
String formatDeveloperFinding(UnifiedFinding f) {
  final buffer = StringBuffer();
  final (icon, label) = headerFor(f);
  buffer.writeln('$icon $label');
  buffer.writeln(titleFor(f));
  buffer.writeln();
  buffer.writeln('📍 ${f.location}');
  buffer.writeln();

  if (f.relation == FindingRelation.notExercised) {
    buffer.writeln(
      'We found a static optimization opportunity, but the selected runtime flow did not '
      'exercise this code. No runtime performance impact can be claimed.',
    );
    final finding = f.staticFinding;
    if (finding != null) {
      buffer.writeln();
      buffer.writeln('Static finding: ${finding.ruleId} -- ${finding.message}');
    }
    return buffer.toString();
  }

  final impact = f.impact!;

  if (f.relation == FindingRelation.runtimeOnly) {
    buffer.writeln(
      'The widget showed significant rebuild/frame activity during the measured flow, but no '
      'matching static rule was found. Runtime analysis can discover issues that static '
      'analysis does not.',
    );
    buffer.writeln();
  }

  if (f.relation == FindingRelation.matched) {
    final finding = f.staticFinding!;
    final inconclusive = f.severity == FindingSeverity.inconsistent;
    buffer.writeln(
      inconclusive
          ? 'This code has a static optimization opportunity. We observed the widget during '
              'runtime, but performance behavior varied substantially between runs, so we cannot '
              'confidently say that this issue is affecting performance.'
          : 'This widget has a static code-quality finding, and the tested runtime flow actually '
              'exercised it -- runtime evidence is available for the same location.',
    );
    buffer.writeln();
    buffer.writeln('Static finding: ${finding.ruleId} -- ${finding.message}');
    buffer.writeln('Runtime evidence: ${confidenceStatement(impact.confidence)}');
    buffer.writeln();
  }

  buffer.writeln('What happened?');
  buffer.writeln(whatHappened(impact));
  buffer.writeln();

  buffer.writeln('Why does it matter?');
  buffer.writeln(whyItMatters(f.severity));
  buffer.writeln();

  buffer.writeln('Evidence');
  for (final line in evidenceLines(f)) {
    buffer.writeln('- $line');
  }
  buffer.writeln();

  buffer.writeln('What to check');
  buffer.writeln(whatToCheck(f.severity));
  buffer.writeln();

  buffer.writeln('Why am I seeing this?');
  var i = 1;
  for (final line in whyAmISeeing(impact)) {
    buffer.writeln('$i. $line');
    i++;
  }
  buffer.writeln(
    'Therefore this was classified as: ${describeClassification(impact.classification)}.',
  );
  buffer.writeln();

  buffer.writeln('Why is this prioritized?');
  for (final line in whyPrioritized(f)) {
    buffer.writeln('- $line');
  }
  buffer.writeln();

  buffer.writeln(causationDisclaimer);
  buffer.writeln();

  buffer.writeln('Technical details:');
  for (final line in technicalDetailsLines(impact, staticFinding: f.staticFinding)) {
    buffer.writeln('  $line');
  }

  return buffer.toString();
}

/// One summary line's bucket -- derived from [headerFor] so the summary
/// counts can never drift out of sync with how each finding is actually
/// headered individually.
String _summaryLabelFor(String icon) => switch (icon) {
      '🔴' => 'finding(s) backed by runtime evidence',
      '🟠' => 'runtime issue(s) worth investigating',
      '🟡' => 'widget(s) worth checking',
      '⚪' => 'static finding(s) not exercised',
      '🟢' => 'healthy runtime widget(s)',
      '⚠️' => 'measurement(s) inconclusive',
      _ => 'finding(s)',
    };

/// Renders the full [UnifiedFindingsReport]: the human-readable
/// "PERFORMANCE SUMMARY" header, then one block per finding in priority
/// order, then a compact not-tested list. If there's nothing to show,
/// says so plainly instead of fabricating a finding.
String formatDeveloperFindingsReport(UnifiedFindingsReport report) {
  final buffer = StringBuffer();
  buffer.writeln('PERFORMANCE SUMMARY');
  buffer.writeln('-' * 20);
  buffer.writeln();

  // Count every finding (healthy widgets and not-exercised included) by
  // the exact icon it will be headered with, so these counts can never
  // contradict the individual blocks below.
  final counts = <String, int>{};
  for (final f in report.allFindings) {
    final (icon, _) = headerFor(f);
    counts[icon] = (counts[icon] ?? 0) + 1;
  }
  for (final n in report.notExercised) {
    final (icon, _) = headerFor(n);
    counts[icon] = (counts[icon] ?? 0) + 1;
  }
  for (final icon in const ['🔴', '🟠', '🟡', '⚪', '🟢', '⚠️']) {
    final count = counts[icon] ?? 0;
    if (count == 0 && icon != '🔴' && icon != '🟢') continue; // always show headline + healthy
    buffer.writeln('$icon $count ${_summaryLabelFor(icon)}');
  }

  buffer.writeln();
  buffer.writeln('Flow: not tracked (this version measures a fixed-duration window, not a '
      'scripted interaction flow)');
  buffer.writeln();
  buffer.writeln('Runs: ${report.totalRuns}');
  buffer.writeln('Warm-up: ${report.warmup.inSeconds}s');
  buffer.writeln('Steady-state: ${report.steadyStateDuration.inSeconds}s');
  buffer.writeln();
  final (overallIcon, _) = severityPresentation(
    report.overallConfidence == Confidence.high
        ? FindingSeverity.healthy
        : report.overallConfidence == Confidence.low
            ? FindingSeverity.inconsistent
            : FindingSeverity.check,
  );
  buffer.writeln(
    'Overall measurement confidence: ${report.overallConfidence.name.toUpperCase()} $overallIcon',
  );

  if (report.findings.isEmpty) {
    buffer.writeln();
    buffer.writeln('🟢 No high-confidence rebuild/frame issues found.');
    buffer.writeln(
      'Nothing in the measured flow met the threshold for a high-priority runtime finding.',
    );
    if (report.notExercised.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('${report.notExercised.length} static finding(s) were not exercised by '
          'this capture -- see below.');
    }
  } else {
    for (final finding in report.findings) {
      buffer.writeln();
      buffer.writeln('=' * 40);
      buffer.write(formatDeveloperFinding(finding));
    }
  }

  if (report.notExercised.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('=' * 40);
    buffer.writeln('⚪ NOT TESTED (${report.notExercised.length}) -- static finding(s) whose code '
        'was never observed running during this capture:');
    for (final n in report.notExercised) {
      buffer.writeln('  ${n.location}  ${n.staticFinding!.ruleId}');
    }
  }

  return buffer.toString();
}
