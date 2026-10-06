import '../model/finding.dart';
import '../model/source_location.dart';
import 'rebuild_frame_correlation.dart';
import 'stats.dart';
import 'widget_frame_impact.dart';

/// The correlation engine's output type: one entry per location that has
/// *either* a static finding, runtime evidence, or both. This is the
/// "unified finding model" -- structured evidence, no presentation
/// concerns -- that a formatter (or any future consumer) renders from.
/// Nothing in this file produces user-facing text.

/// The four severities a widget with runtime evidence can reach, plus
/// [inconsistent] -- not a fifth severity level, but a distinct state that
/// *overrides* the other four whenever confidence is too low to trust the
/// classification at all (see [UnifiedFinding.severity]).
enum FindingSeverity { healthy, check, investigate, highPriority, inconsistent }

(String icon, String label) severityPresentation(FindingSeverity s) => switch (s) {
      FindingSeverity.healthy => ('🟢', 'INFO'),
      FindingSeverity.check => ('🟡', 'CHECK'),
      FindingSeverity.investigate => ('🟠', 'INVESTIGATE'),
      FindingSeverity.highPriority => ('🔴', 'HIGH PRIORITY'),
      FindingSeverity.inconsistent => ('⚠️', 'INCONSISTENT'),
    };

/// Maps a widget's classification to a severity, capped by [impact]'s
/// confidence: MEDIUM confidence can never reach [FindingSeverity
/// .highPriority] (capped at [FindingSeverity.investigate] instead), and
/// LOW confidence bypasses this function entirely -- callers should check
/// [isInconsistent] first, since a LOW-confidence widget must never be
/// presented with a severity claim at all (never say "X causes jank" from
/// unstable evidence).
///
/// This is the concrete answer to "severity must consider rebuild
/// frequency, frame impact, *and* confidence" -- not rebuild count alone.
FindingSeverity classifyFindingSeverity(WidgetFrameImpactSummary impact) {
  final base = switch (impact.classification) {
    ImpactClassification.lowRebuildLowImpact => FindingSeverity.healthy,
    ImpactClassification.highRebuildLowImpact => FindingSeverity.check,
    ImpactClassification.lowRebuildHighImpact => FindingSeverity.investigate,
    ImpactClassification.highRebuildHighImpact => FindingSeverity.highPriority,
  };
  if (impact.confidence == Confidence.medium && base == FindingSeverity.highPriority) {
    return FindingSeverity.investigate;
  }
  return base;
}

/// True when the evidence varied too much run-to-run to trust a severity
/// claim at all. A widget that's consistently near-zero activity
/// trivially has low variance (nothing to vary), so this only fires for
/// widgets with *some* real signal that wasn't reproducible.
bool isInconsistent(WidgetFrameImpactSummary impact) =>
    impact.classification != ImpactClassification.lowRebuildLowImpact &&
    impact.confidence == Confidence.low;

/// The exact confidence-gated statement to attach to runtime evidence --
/// never let a LOW-confidence result produce a strong claim, per this
/// milestone's mandate.
String confidenceStatement(Confidence c) => switch (c) {
      Confidence.high => 'Runtime evidence supports this finding.',
      Confidence.medium => 'Runtime evidence suggests this may be affecting performance.',
      Confidence.low => 'Runtime behavior is inconsistent; we cannot confidently connect this '
          'finding to a performance problem.',
    };

/// How a widget's runtime evidence relates to static analysis.
enum FindingRelation { standalone, matched, runtimeOnly, notExercised }

/// The four-way evidence-strength classification: independent evidence
/// increases priority, one weak signal never overrides a strong one, and
/// unreliable runtime evidence is called out rather than blended in.
enum EvidenceCategory { staticOnly, staticAndRuntime, runtimeOnly, inconclusive }

/// One location's unified evidence: a static finding, runtime evidence, or
/// both, joined *only* by exact source location (file/line/column) -- the
/// same join key every correlation in this package uses. Never matched by
/// widget name, class name, or text.
class UnifiedFinding {
  final FindingRelation relation;
  final SourceLocation location;

  /// `null` only for a pure [FindingRelation.notExercised] finding (a
  /// static finding whose location was never observed rebuilding at all).
  final WidgetFrameImpactSummary? impact;

  final Finding? staticFinding;

  const UnifiedFinding({
    required this.relation,
    required this.location,
    this.impact,
    this.staticFinding,
  });

  /// Only meaningful when [impact] is non-null (i.e. not a pure
  /// not-exercised finding).
  FindingSeverity get severity {
    final i = impact;
    if (i == null) return FindingSeverity.healthy; // unused for notExercised rendering
    if (isInconsistent(i)) return FindingSeverity.inconsistent;
    return classifyFindingSeverity(i);
  }

  /// The item-7 evidence category. Checked in this order: unreliable
  /// runtime evidence (LOW confidence) always reads as [inconclusive]
  /// regardless of whether a static finding is also present -- confidence
  /// governs the message before relation does.
  EvidenceCategory get evidenceCategory {
    final hasStatic = staticFinding != null;
    final hasRuntime = impact != null;
    if (hasRuntime && isInconsistent(impact!)) return EvidenceCategory.inconclusive;
    if (hasStatic && hasRuntime) return EvidenceCategory.staticAndRuntime;
    if (hasStatic) return EvidenceCategory.staticOnly;
    return EvidenceCategory.runtimeOnly;
  }

  /// Lower sorts first. Implements item 11's ordering: high-confidence
  /// combined evidence, then high-confidence runtime-only, then medium-
  /// confidence combined, then static-only (not exercised), then
  /// inconclusive -- everything else (e.g. a healthy standalone widget,
  /// never individually printed anyway) sorts last.
  int get priorityRank {
    final category = evidenceCategory;
    final confidence = impact?.confidence;
    if (category == EvidenceCategory.staticAndRuntime && confidence == Confidence.high) return 0;
    if (relation == FindingRelation.runtimeOnly) return 1;
    if (category == EvidenceCategory.staticAndRuntime && confidence == Confidence.medium) return 2;
    if (category == EvidenceCategory.staticOnly) return 3;
    if (category == EvidenceCategory.inconclusive) return 4;
    return 5;
  }
}

/// "Why is this prioritized?" -- lists only evidence that actually exists
/// on [f], in the order it was established, ending with the confidence
/// statement that determined how strongly it can be trusted. Never invents
/// a bullet for evidence that isn't there.
List<String> whyPrioritized(UnifiedFinding f) {
  final lines = <String>[];
  final staticFinding = f.staticFinding;
  if (staticFinding != null) {
    lines.add('A static issue exists at this location (${staticFinding.ruleId}).');
  }
  final impact = f.impact;
  if (impact == null) {
    lines.add('No runtime evidence is available -- the selected flow did not exercise this '
        'location.');
    return lines;
  }
  lines.add('The widget was actually exercised during the measured runtime flow '
      '(${impact.runsObservedIn}/${impact.totalRuns} run(s)).');
  if (impact.rebuildCountStats.median > 0) {
    lines.add('The widget rebuilt repeatedly (median ${impact.rebuildCountStats.median.round()} '
        'rebuilds).');
  }
  if (impact.overBudgetFrameCountStats.median > 0) {
    lines.add('Its rebuilds overlapped slow frames (median '
        '${impact.overBudgetFrameCountStats.median.round()} of '
        '${impact.framesTouchedStats.median.round()} frames touched).');
  }
  lines.add(switch (impact.confidence) {
    Confidence.high => 'Runtime evidence was stable across runs (high confidence).',
    Confidence.medium => 'Runtime evidence was moderately consistent across runs (medium '
        'confidence).',
    Confidence.low => 'Runtime evidence varied substantially across runs (low confidence) -- '
        'this lowers priority rather than raising it.',
  });
  return lines;
}

/// Everything the correlation engine produces for one multi-run
/// measurement: every [UnifiedFinding] worth printing individually
/// (sorted by [UnifiedFinding.priorityRank]), the not-exercised list, and
/// the measurement context needed for the report header. Presentation
/// (icons, wording) lives entirely in the formatter that consumes this.
class UnifiedFindingsReport {
  /// Every finding, healthy standalone widgets included -- the formatter
  /// decides what to print individually versus fold into summary counts;
  /// this layer doesn't discard evidence.
  final List<UnifiedFinding> allFindings;

  /// [allFindings] minus healthy standalone widgets, sorted by
  /// [UnifiedFinding.priorityRank] -- what a report prints as individual
  /// blocks.
  final List<UnifiedFinding> findings;

  final List<UnifiedFinding> notExercised;
  final int totalRuns;
  final Duration warmup;
  final Duration steadyStateDuration;

  /// The same trust-milestone confidence already computed for the whole
  /// run's over-budget percentage -- reused here as "overall confidence"
  /// rather than inventing a second confidence metric.
  final Confidence overallConfidence;

  const UnifiedFindingsReport({
    required this.allFindings,
    required this.findings,
    required this.notExercised,
    required this.totalRuns,
    required this.warmup,
    required this.steadyStateDuration,
    required this.overallConfidence,
  });
}

/// The correlation engine: builds [UnifiedFinding]s from already-computed
/// evidence -- [allImpacts] (every widget observed, healthy ones
/// included) and [correlation] (the existing matched/runtime-only/not-
/// exercised split, itself already an exact-source-location join). Does
/// not recompute or alter any of that evidence, and performs no
/// formatting -- see `developer_findings.dart` for that.
UnifiedFindingsReport buildUnifiedFindings(
  List<WidgetFrameImpactSummary> allImpacts,
  RebuildFrameCorrelationResult correlation, {
  required int totalRuns,
  required Duration warmup,
  required Duration steadyStateDuration,
  required Confidence overallConfidence,
}) {
  final matchedLocations = {for (final m in correlation.matched) m.impact.location};
  final runtimeOnlyLocations = {for (final r in correlation.runtimeOnly) r.impact.location};

  final all = <UnifiedFinding>[];

  for (final m in correlation.matched) {
    all.add(UnifiedFinding(
      relation: FindingRelation.matched,
      location: m.impact.location,
      impact: m.impact,
      staticFinding: m.finding,
    ));
  }

  for (final r in correlation.runtimeOnly) {
    all.add(UnifiedFinding(
      relation: FindingRelation.runtimeOnly,
      location: r.impact.location,
      impact: r.impact,
    ));
  }

  for (final impact in allImpacts) {
    if (matchedLocations.contains(impact.location) || runtimeOnlyLocations.contains(impact.location)) {
      continue;
    }
    all.add(UnifiedFinding(relation: FindingRelation.standalone, location: impact.location, impact: impact));
  }

  final notExercised = [
    for (final n in correlation.notExercised)
      UnifiedFinding(
        relation: FindingRelation.notExercised,
        location: n.finding.location,
        staticFinding: n.finding,
      ),
  ];

  final printable = all.where((f) => f.severity != FindingSeverity.healthy).toList()
    ..sort((a, b) => a.priorityRank.compareTo(b.priorityRank));

  return UnifiedFindingsReport(
    allFindings: all,
    findings: printable,
    notExercised: notExercised,
    totalRuns: totalRuns,
    warmup: warmup,
    steadyStateDuration: steadyStateDuration,
    overallConfidence: overallConfidence,
  );
}
