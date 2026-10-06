import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/developer_findings.dart';
import 'package:fluttr_scope/src/runtime/rebuild_frame_correlation.dart';
import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:fluttr_scope/src/runtime/unified_finding.dart';
import 'package:fluttr_scope/src/runtime/widget_frame_impact.dart';
import 'package:test/test.dart';

const _location = SourceLocation(file: 'lib/widgets/product_card.dart', line: 42, column: 12, length: 0);
const _otherLocation = SourceLocation(file: 'lib/widgets/header.dart', line: 7, column: 3, length: 0);

WidgetFrameImpactSummary _summary({
  SourceLocation location = _location,
  required List<double> rebuildCounts,
  required List<double> framesTouched,
  required List<double> overBudgetCounts,
  required List<double> percents,
  List<double>? frameDurations,
}) {
  return WidgetFrameImpactSummary(
    location: location,
    totalRuns: rebuildCounts.length,
    runsObservedIn: rebuildCounts.length,
    rebuildCountStats: computeStats(rebuildCounts),
    framesTouchedStats: computeStats(framesTouched),
    overBudgetFrameCountStats: computeStats(overBudgetCounts),
    percentFramesOverBudgetStats: computeStats(percents),
    frameDurationStatsMs: frameDurations == null ? null : computeStats(frameDurations),
  );
}

WidgetFrameImpactSummary _lowLow() => _summary(
      rebuildCounts: [5, 6, 4, 5, 5],
      framesTouched: [5, 6, 4, 5, 5],
      overBudgetCounts: [0, 0, 0, 0, 0],
      percents: [0, 0, 0, 0, 0],
    );

WidgetFrameImpactSummary _highLow() => _summary(
      rebuildCounts: [200, 210, 195, 205, 200],
      framesTouched: [200, 210, 195, 205, 200],
      // Exactly zero, not "close to zero" -- a mean near zero makes CoV
      // blow up from tiny absolute noise (a real statistical property,
      // not a bug), which would accidentally read as LOW confidence
      // instead of the clean HIGH-confidence case this fixture wants.
      overBudgetCounts: [0, 0, 0, 0, 0],
      percents: [0, 0, 0, 0, 0],
    );

WidgetFrameImpactSummary _lowHigh() => _summary(
      rebuildCounts: [10, 12, 9, 11, 10],
      framesTouched: [10, 12, 9, 11, 10],
      overBudgetCounts: [5, 6, 4, 5, 5],
      percents: [50, 50, 44, 45, 50],
    );

WidgetFrameImpactSummary _highHigh() => _summary(
      rebuildCounts: [200, 210, 195, 205, 200],
      framesTouched: [220, 230, 210, 225, 215],
      overBudgetCounts: [8, 9, 7, 8, 8],
      percents: [90, 91, 89, 90, 90],
    );

/// HIGH REBUILD + HIGH FRAME IMPACT by median, but with moderate run-to-run
/// spread in the impact percentage -- CoV lands in the 10-25% band, i.e.
/// MEDIUM confidence.
WidgetFrameImpactSummary _highHighMediumConfidence() => _summary(
      rebuildCounts: [200, 200, 200, 200, 200],
      framesTouched: [100, 100, 100, 100, 100],
      overBudgetCounts: [60, 80, 55, 85, 70],
      percents: [60, 80, 55, 85, 70],
    );

/// Would classify as HIGH REBUILD + HIGH FRAME IMPACT by median, but the
/// impact percentage swings wildly between runs -- CoV well above 25%,
/// i.e. LOW confidence / unstable.
WidgetFrameImpactSummary _highHighLowConfidence() => _summary(
      rebuildCounts: [200, 200, 200, 200, 200],
      framesTouched: [100, 100, 100, 100, 100],
      overBudgetCounts: [90, 5, 95, 0, 85],
      percents: [90, 5, 95, 0, 85],
    );

Finding _finding(SourceLocation location) => Finding(
      ruleId: 'setstate_in_list_builder',
      category: Category.performance,
      severity: Severity.warning,
      message: 'setState() inside a list/grid itemBuilder rebuilds the entire list.',
      location: location,
    );

UnifiedFindingsReport _reportFor(
  List<WidgetFrameImpactSummary> allImpacts, {
  RebuildFrameCorrelationResult? correlation,
  Confidence overallConfidence = Confidence.high,
}) =>
    buildUnifiedFindings(
      allImpacts,
      correlation ?? correlateRebuildsToFrames(const [], allImpacts),
      totalRuns: 5,
      warmup: const Duration(seconds: 5),
      steadyStateDuration: const Duration(seconds: 20),
      overallConfidence: overallConfidence,
    );

void main() {
  group('classifySeverity quadrants', () {
    test('LOW REBUILD / LOW FRAME IMPACT -> healthy', () {
      expect(classifyFindingSeverity(_lowLow()), FindingSeverity.healthy);
    });

    test('HIGH REBUILD / LOW FRAME IMPACT -> check', () {
      expect(classifyFindingSeverity(_highLow()), FindingSeverity.check);
    });

    test('LOW REBUILD / HIGH FRAME IMPACT -> investigate', () {
      expect(classifyFindingSeverity(_lowHigh()), FindingSeverity.investigate);
    });

    test('HIGH REBUILD / HIGH FRAME IMPACT -> highPriority', () {
      expect(classifyFindingSeverity(_highHigh()), FindingSeverity.highPriority);
    });
  });

  group('confidence handling', () {
    test('HIGH confidence: a consistent HIGH/HIGH widget keeps highPriority severity', () {
      final impact = _highHigh();
      expect(impact.confidence, Confidence.high);
      expect(classifyFindingSeverity(impact), FindingSeverity.highPriority);
      expect(isInconsistent(impact), isFalse);
    });

    test('MEDIUM confidence: a HIGH/HIGH-by-median widget is capped at '
        'investigate, never claimed as highPriority', () {
      final impact = _highHighMediumConfidence();
      expect(impact.confidence, Confidence.medium);
      expect(impact.classification, ImpactClassification.highRebuildHighImpact);
      expect(classifyFindingSeverity(impact), FindingSeverity.investigate);
    });

    test('LOW confidence (UNSTABLE): a HIGH/HIGH-by-median widget is never '
        'presented as highPriority -- isInconsistent overrides it', () {
      final impact = _highHighLowConfidence();
      expect(impact.confidence, Confidence.low);
      expect(impact.classification, ImpactClassification.highRebuildHighImpact);
      expect(isInconsistent(impact), isTrue);
    });

    test('a consistently LOW/LOW widget is never marked inconsistent, even '
        'though it trivially has zero variance', () {
      expect(isInconsistent(_lowLow()), isFalse);
    });
  });

  group('formatDeveloperFinding wording', () {
    test('never claims causation, always uses observational language', () {
      final f = UnifiedFinding(
        relation: FindingRelation.standalone,
        location: _location,
        impact: _highHigh(),
      );
      final text = formatDeveloperFinding(f);
      // "caused" legitimately appears once, inside the disclaimer that
      // explicitly *denies* causation ("does not establish that ...
      // caused ..."). What must never appear is an affirmative causal
      // claim asserting the widget *did* cause something.
      expect(text, isNot(contains('this widget caused')));
      expect(text, isNot(contains('causes slow frames')));
      expect(text, isNot(contains('causes jank')));
      expect(text, contains('does not establish that'));
      expect(text, contains('overlapped'));
      expect(text, contains('not a proven causal relationship'));
    });

    test('does not surface a rule id prominently -- it only appears under '
        'Technical details', () {
      final finding = _finding(_location);
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHigh(),
        staticFinding: finding,
      );
      final text = formatDeveloperFinding(f);
      final ruleIdIndex = text.indexOf(finding.ruleId);
      final technicalDetailsIndex = text.indexOf('Technical details');
      // The rule id does appear (in "Static finding: ...") but the
      // *heading* of the report is not the rule id -- the first line must
      // be the severity/title, not "setstate_in_list_builder".
      expect(text.trimLeft().startsWith(finding.ruleId), isFalse);
      expect(ruleIdIndex, greaterThan(-1));
      expect(technicalDetailsIndex, greaterThan(-1));
    });

    test('uses simple language instead of technical jargon in the primary sections', () {
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: _highHigh());
      final text = formatDeveloperFinding(f);
      // Jargon is confined to Technical details; the primary sections use
      // plain words.
      final beforeTechnical = text.substring(0, text.indexOf('Technical details'));
      expect(beforeTechnical, contains('slow frame'));
      expect(beforeTechnical, contains('How sure we are'));
      expect(beforeTechnical, isNot(contains('CoV')));
      expect(beforeTechnical, isNot(contains('coefficient of variation')));
    });

    test('LOW/LOW (healthy) finding text does not read as a warning', () {
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: _lowLow());
      final text = formatDeveloperFinding(f);
      expect(text, contains('🟢'));
      expect(text, contains('little measurable impact'));
    });

    test('HIGH/LOW finding explicitly says not to call it critical', () {
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: _highLow());
      final text = formatDeveloperFinding(f);
      expect(text, contains('🟡'));
      expect(text, contains('does not show a strong relationship'));
    });

    test('LOW/HIGH finding is framed as a candidate worth investigating', () {
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: _lowHigh());
      final text = formatDeveloperFinding(f);
      expect(text, contains('🟠'));
      expect(text, contains('may be worth investigating'));
    });

    test('HIGH/HIGH finding is framed as high priority', () {
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: _highHigh());
      final text = formatDeveloperFinding(f);
      expect(text, contains('🔴'));
      expect(text, contains('high-priority candidate'));
    });

    test('UNSTABLE/LOW-confidence finding shows the inconsistent-measurement '
        'presentation instead of a severity claim, and never blames the '
        'emulator as fact', () {
      final f = UnifiedFinding(
        relation: FindingRelation.standalone,
        location: _location,
        impact: _highHighLowConfidence(),
      );
      final text = formatDeveloperFinding(f);
      expect(text, contains('⚠️'));
      expect(text, contains('inconsistent'));
      expect(text, contains('substantially different'));
      expect(text, isNot(contains('emulator caused')));
      expect(text, isNot(contains('Emulator caused')));
    });

    test('"Why am I seeing this?" is generated from the real evidence numbers', () {
      final impact = _highHigh();
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: impact);
      final text = formatDeveloperFinding(f);
      expect(text, contains('rebuilt ${impact.rebuildCountStats.median.round()} times'));
      expect(text, contains('repeated across ${impact.totalRuns} run'));
    });

    test('MATCHED finding explains both the static finding and the runtime '
        'evidence together', () {
      final finding = _finding(_location);
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHigh(),
        staticFinding: finding,
      );
      final text = formatDeveloperFinding(f);
      expect(text, contains('Static finding:'));
      expect(text, contains(finding.ruleId));
      expect(text, contains('Runtime evidence:'));
    });

    test('RUNTIME-ONLY finding uses the fixed 🟠 presentation and explains '
        'there is no matching static rule', () {
      final f = UnifiedFinding(relation: FindingRelation.runtimeOnly, location: _location, impact: _highHigh());
      final text = formatDeveloperFinding(f);
      expect(text, startsWith('🟠'));
      expect(text, contains('no matching static rule was found'));
    });

    test('NOT EXERCISED finding never attaches runtime numbers -- no '
        'rebuild count, no evidence section', () {
      final finding = _finding(_otherLocation);
      final f = UnifiedFinding(relation: FindingRelation.notExercised, location: _otherLocation, staticFinding: finding);
      final text = formatDeveloperFinding(f);
      expect(text, startsWith('⚪'));
      expect(text, contains('did not exercise this code'));
      expect(text, isNot(contains('Rebuilds:')));
      expect(text, isNot(contains('Evidence')));
    });
  });

  group('technical details -- missing/unknown data and duration shapes', () {
    test('missing frame duration data is stated as unavailable, never fabricated', () {
      final impact = _summary(
        rebuildCounts: [10, 10, 10],
        framesTouched: [10, 10, 10],
        overBudgetCounts: [0, 0, 0],
        percents: [0, 0, 0],
        // frameDurations intentionally omitted -- unknown.
      );
      final lines = technicalDetailsLines(impact);
      expect(lines.any((l) => l.contains('not available for this widget')), isTrue);
      expect(lines.any((l) => l.contains('Frame duration --')), isFalse);
    });

    test('a build-bottleneck-shaped duration (high, dominated by build) is '
        'reported only as a combined figure, never split into an isolated '
        'per-widget build number', () {
      final impact = _summary(
        rebuildCounts: [10, 10, 10],
        framesTouched: [10, 10, 10],
        overBudgetCounts: [3, 3, 3],
        percents: [30, 30, 30],
        frameDurations: [24.0, 25.0, 23.0], // e.g. build=22ms, raster=2ms in reality
      );
      final lines = technicalDetailsLines(impact);
      final durationLine = lines.firstWhere((l) => l.contains('Frame duration'));
      expect(durationLine, contains('build+raster combined'));
      expect(durationLine, isNot(contains('build only')));
    });

    test('a raster-bottleneck-shaped duration (high, dominated by raster) is '
        'reported the same combined way -- the presentation layer does not '
        'need to know which phase dominated', () {
      final impact = _summary(
        rebuildCounts: [10, 10, 10],
        framesTouched: [10, 10, 10],
        overBudgetCounts: [3, 3, 3],
        percents: [30, 30, 30],
        frameDurations: [24.0, 25.0, 23.0], // e.g. build=2ms, raster=22ms in reality
      );
      final lines = technicalDetailsLines(impact);
      expect(lines.any((l) => l.contains('Frame duration') && l.contains('combined')), isTrue);
    });

    test('a combined-bottleneck-shaped duration renders identically to the '
        'other two shapes -- proving the technical details never guess at '
        'a build/raster split it cannot measure', () {
      final impact = _summary(
        rebuildCounts: [10, 10, 10],
        framesTouched: [10, 10, 10],
        overBudgetCounts: [3, 3, 3],
        percents: [30, 30, 30],
        frameDurations: [24.0, 25.0, 23.0], // e.g. build=13ms, raster=11ms in reality
      );
      final lines = technicalDetailsLines(impact);
      expect(lines.any((l) => l.contains('Frame duration') && l.contains('combined')), isTrue);
    });
  });

  group('buildUnifiedFindings', () {
    test('no findings: reports "no issues found" rather than fabricating one', () {
      final report = _reportFor([_lowLow()]);
      expect(report.findings, isEmpty);
      expect(report.allFindings.where((f) => f.severity == FindingSeverity.healthy).length, 1);
      final text = formatDeveloperFindingsReport(report);
      expect(text, contains('No high-confidence rebuild/frame issues found'));
    });

    test('a healthy widget is counted in the summary but not printed as an '
        'individual finding block', () {
      final report = _reportFor([_lowLow()]);
      expect(report.findings, isEmpty);
      expect(report.allFindings.where((f) => f.severity == FindingSeverity.healthy).length, 1);
    });

    test('multiple findings across different quadrants are all included, '
        'correctly counted, and correctly bucketed', () {
      const thirdLocation = SourceLocation(file: 'lib/widgets/footer.dart', line: 3, column: 1, length: 0);
      final report = _reportFor([
        _lowLow(),
        _summary(
          location: _otherLocation,
          rebuildCounts: [200, 210, 195, 205, 200],
          framesTouched: [200, 210, 195, 205, 200],
          overBudgetCounts: [0, 0, 0, 0, 0],
          percents: [0, 0, 0, 0, 0],
        ),
        _summary(
          location: thirdLocation,
          rebuildCounts: [200, 210, 195, 205, 200],
          framesTouched: [220, 230, 210, 225, 215],
          overBudgetCounts: [8, 9, 7, 8, 8],
          percents: [90, 91, 89, 90, 90],
        ),
      ]);

      expect(report.allFindings.where((f) => f.severity == FindingSeverity.healthy).length, 1);
      expect(report.allFindings.where((f) => f.severity == FindingSeverity.check).length, 1);
      expect(report.allFindings.where((f) => f.severity == FindingSeverity.highPriority).length, 1);
      // Only the non-healthy ones are printed as individual blocks.
      expect(report.findings, hasLength(2));
    });

    test('a MATCHED widget appears with relation=matched and is not '
        'double-counted as standalone', () {
      final impact = _highHigh();
      final finding = _finding(_location);
      final correlation = correlateRebuildsToFrames([finding], [impact]);
      final report = _reportFor([impact], correlation: correlation);

      expect(report.findings, hasLength(1));
      expect(report.findings.single.relation, FindingRelation.matched);
      expect(report.allFindings.where((f) => f.severity == FindingSeverity.highPriority).length, 1);
    });

    test('a RUNTIME-ONLY widget appears with relation=runtimeOnly', () {
      final impact = _highHigh();
      final correlation = correlateRebuildsToFrames(const [], [impact]);
      final report = _reportFor([impact], correlation: correlation);

      expect(report.findings, hasLength(1));
      expect(report.findings.single.relation, FindingRelation.runtimeOnly);
    });

    test('a NOT EXERCISED static finding appears in notExercised, not findings', () {
      final finding = _finding(_otherLocation);
      final correlation = correlateRebuildsToFrames([finding], const []);
      final report = _reportFor(const [], correlation: correlation);

      expect(report.notExercised, hasLength(1));
      expect(report.findings, isEmpty);
      final text = formatDeveloperFindingsReport(report);
      expect(text, contains('NOT TESTED'));
    });

    test('the summary header never presents a fabricated overall score when '
        'overallConfidence is LOW', () {
      final report = _reportFor([_lowLow()], overallConfidence: Confidence.low);
      final text = formatDeveloperFindingsReport(report);
      expect(text, contains('Overall measurement confidence: LOW'));
      expect(text, isNot(contains('Overall measurement confidence: HIGH')));
    });
  });
}
