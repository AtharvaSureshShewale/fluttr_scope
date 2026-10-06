import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/rebuild_frame_correlation.dart';
import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:fluttr_scope/src/runtime/unified_finding.dart';
import 'package:test/test.dart';

const _location = SourceLocation(file: 'lib/widgets/product_card.dart', line: 42, column: 12, length: 0);

WidgetFrameImpactSummary _summary({
  SourceLocation location = _location,
  required List<double> rebuildCounts,
  required List<double> framesTouched,
  required List<double> overBudgetCounts,
  required List<double> percents,
}) =>
    WidgetFrameImpactSummary(
      location: location,
      totalRuns: rebuildCounts.length,
      runsObservedIn: rebuildCounts.length,
      rebuildCountStats: computeStats(rebuildCounts),
      framesTouchedStats: computeStats(framesTouched),
      overBudgetFrameCountStats: computeStats(overBudgetCounts),
      percentFramesOverBudgetStats: computeStats(percents),
    );

WidgetFrameImpactSummary _highHighHighConfidence({SourceLocation location = _location}) => _summary(
      location: location,
      rebuildCounts: [200, 210, 195, 205, 200],
      framesTouched: [220, 230, 210, 225, 215],
      overBudgetCounts: [8, 9, 7, 8, 8],
      percents: [90, 91, 89, 90, 90],
    );

WidgetFrameImpactSummary _highHighMediumConfidence({SourceLocation location = _location}) => _summary(
      location: location,
      rebuildCounts: [200, 200, 200, 200, 200],
      framesTouched: [100, 100, 100, 100, 100],
      overBudgetCounts: [60, 80, 55, 85, 70],
      percents: [60, 80, 55, 85, 70],
    );

WidgetFrameImpactSummary _highHighLowConfidence({SourceLocation location = _location}) => _summary(
      location: location,
      rebuildCounts: [200, 200, 200, 200, 200],
      framesTouched: [100, 100, 100, 100, 100],
      overBudgetCounts: [90, 5, 95, 0, 85],
      percents: [90, 5, 95, 0, 85],
    );

Finding _finding(SourceLocation location, {String ruleId = 'missing_const_constructor'}) => Finding(
      ruleId: ruleId,
      category: Category.performance,
      severity: Severity.warning,
      message: 'This widget could be const.',
      location: location,
    );

void main() {
  group('EvidenceCategory classification', () {
    test('static + high-confidence runtime -> staticAndRuntime', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighHighConfidence(),
        staticFinding: _finding(_location),
      );
      expect(f.evidenceCategory, EvidenceCategory.staticAndRuntime);
    });

    test('static + medium-confidence runtime -> still staticAndRuntime '
        '(medium is trustworthy enough to combine, just capped in severity)', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighMediumConfidence(),
        staticFinding: _finding(_location),
      );
      expect(f.evidenceCategory, EvidenceCategory.staticAndRuntime);
    });

    test('static + low-confidence runtime -> inconclusive, NOT staticAndRuntime '
        '-- confidence overrides relation', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighLowConfidence(),
        staticFinding: _finding(_location),
      );
      expect(f.evidenceCategory, EvidenceCategory.inconclusive);
    });

    test('static + not exercised -> staticOnly', () {
      final f = UnifiedFinding(
        relation: FindingRelation.notExercised,
        location: _location,
        staticFinding: _finding(_location),
      );
      expect(f.evidenceCategory, EvidenceCategory.staticOnly);
    });

    test('runtime evidence, no static finding -> runtimeOnly', () {
      final f = UnifiedFinding(
        relation: FindingRelation.runtimeOnly,
        location: _location,
        impact: _highHighHighConfidence(),
      );
      expect(f.evidenceCategory, EvidenceCategory.runtimeOnly);
    });

    test('runtime-only with low confidence is also inconclusive, not runtimeOnly', () {
      final f = UnifiedFinding(
        relation: FindingRelation.runtimeOnly,
        location: _location,
        impact: _highHighLowConfidence(),
      );
      expect(f.evidenceCategory, EvidenceCategory.inconclusive);
    });
  });

  group('confidenceStatement', () {
    test('HIGH confidence produces the exact supportive wording', () {
      expect(confidenceStatement(Confidence.high), 'Runtime evidence supports this finding.');
    });

    test('MEDIUM confidence produces the exact hedged wording', () {
      expect(
        confidenceStatement(Confidence.medium),
        'Runtime evidence suggests this may be affecting performance.',
      );
    });

    test('LOW confidence never produces a strong claim -- it explicitly '
        'declines to connect the finding to a performance problem', () {
      final statement = confidenceStatement(Confidence.low);
      expect(statement, contains('cannot confidently connect'));
      expect(statement, isNot(contains('supports')));
      expect(statement, isNot(contains('affecting performance')));
    });
  });

  group('priorityRank ordering', () {
    test('high-confidence static+runtime ranks first (0)', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighHighConfidence(),
        staticFinding: _finding(_location),
      );
      expect(f.priorityRank, 0);
    });

    test('runtime-only ranks second (1), even without any static finding', () {
      final f = UnifiedFinding(
        relation: FindingRelation.runtimeOnly,
        location: _location,
        impact: _highHighHighConfidence(),
      );
      expect(f.priorityRank, 1);
    });

    test('medium-confidence static+runtime ranks third (2)', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighMediumConfidence(),
        staticFinding: _finding(_location),
      );
      expect(f.priorityRank, 2);
    });

    test('static-only (not exercised) ranks fourth (3)', () {
      final f = UnifiedFinding(
        relation: FindingRelation.notExercised,
        location: _location,
        staticFinding: _finding(_location),
      );
      expect(f.priorityRank, 3);
    });

    test('inconclusive (low-confidence) ranks last among real findings (4)', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighLowConfidence(),
        staticFinding: _finding(_location),
      );
      expect(f.priorityRank, 4);
    });

    test('buildUnifiedFindings sorts findings by priority rank end to end, '
        'independent of the order they were discovered in', () {
      const locHigh = _location;
      const locMedium = SourceLocation(file: 'lib/b.dart', line: 1, column: 1, length: 0);
      const locNotExercised = SourceLocation(file: 'lib/c.dart', line: 1, column: 1, length: 0);
      const locInconclusive = SourceLocation(file: 'lib/d.dart', line: 1, column: 1, length: 0);
      const locRuntimeOnly = SourceLocation(file: 'lib/e.dart', line: 1, column: 1, length: 0);

      // Findings supplied in a deliberately "wrong" order.
      final findings = [
        _finding(locNotExercised),
        _finding(locMedium),
        _finding(locHigh),
        _finding(locInconclusive),
      ];
      final impacts = [
        _highHighMediumConfidence(location: locMedium),
        _highHighHighConfidence(location: locHigh),
        _highHighLowConfidence(location: locInconclusive),
        _highHighHighConfidence(location: locRuntimeOnly),
      ];
      final correlation = correlateRebuildsToFrames(findings, impacts);
      final report = buildUnifiedFindings(
        impacts,
        correlation,
        totalRuns: 5,
        warmup: Duration.zero,
        steadyStateDuration: const Duration(seconds: 10),
        overallConfidence: Confidence.medium,
      );

      // Not-exercised findings live in their own list (a separate,
      // compact "not tested" section), not interleaved into the ranked
      // findings list -- so only the 4 locations with runtime evidence
      // participate in this ranking.
      final ranks = report.findings.map((f) => f.priorityRank).toList();
      expect(ranks, [0, 1, 2, 4]); // strictly non-decreasing by construction
      expect(report.findings.first.location, locHigh);
      expect(report.findings.last.location, locInconclusive);

      expect(report.notExercised, hasLength(1));
      expect(report.notExercised.single.location, locNotExercised);
    });
  });

  group('whyPrioritized', () {
    test('lists only evidence that actually exists -- no static line when '
        'there is no static finding', () {
      final f = UnifiedFinding(
        relation: FindingRelation.runtimeOnly,
        location: _location,
        impact: _highHighHighConfidence(),
      );
      final lines = whyPrioritized(f);
      expect(lines.any((l) => l.contains('static issue')), isFalse);
      expect(lines.any((l) => l.contains('actually exercised')), isTrue);
      expect(lines.any((l) => l.contains('stable across runs')), isTrue);
    });

    test('includes the static-issue line when a static finding is present', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighHighConfidence(),
        staticFinding: _finding(_location, ruleId: 'missing_const_constructor'),
      );
      final lines = whyPrioritized(f);
      expect(lines.first, contains('missing_const_constructor'));
    });

    test('for a not-exercised finding, states plainly that no runtime '
        'evidence is available -- never fabricates rebuild/frame numbers', () {
      final f = UnifiedFinding(
        relation: FindingRelation.notExercised,
        location: _location,
        staticFinding: _finding(_location),
      );
      final lines = whyPrioritized(f);
      expect(lines, hasLength(2)); // static line + "no runtime evidence" line
      expect(lines.last, contains('No runtime evidence is available'));
      expect(lines.any((l) => l.contains('rebuilt')), isFalse);
    });

    test('low confidence lowers priority in its own wording, rather than '
        'silently omitting the confidence line', () {
      final f = UnifiedFinding(
        relation: FindingRelation.matched,
        location: _location,
        impact: _highHighLowConfidence(),
        staticFinding: _finding(_location),
      );
      final lines = whyPrioritized(f);
      expect(lines.last, contains('lowers priority rather than raising it'));
    });

    test('does not mention overlapping slow frames when the widget had zero '
        'over-budget frames -- only real evidence is listed', () {
      final impact = _summary(
        rebuildCounts: [10, 10, 10],
        framesTouched: [10, 10, 10],
        overBudgetCounts: [0, 0, 0],
        percents: [0, 0, 0],
      );
      final f = UnifiedFinding(relation: FindingRelation.standalone, location: _location, impact: impact);
      final lines = whyPrioritized(f);
      expect(lines.any((l) => l.contains('overlapped slow frames')), isFalse);
    });
  });

  group('source-location matching is exact, never fuzzy', () {
    test('a static finding and runtime impact at different locations do '
        'not match, even in the same file', () {
      const nearbyLocation = SourceLocation(file: 'lib/widgets/product_card.dart', line: 43, column: 12, length: 0);
      final findings = [_finding(_location)];
      final impacts = [_highHighHighConfidence(location: nearbyLocation)];
      final correlation = correlateRebuildsToFrames(findings, impacts);

      expect(correlation.matched, isEmpty);
      expect(correlation.notExercised, hasLength(1));
      expect(correlation.notExercised.single.finding.location, _location);
    });

    test('same line, different column -- still not matched (column is part '
        'of the join key)', () {
      const sameLine = SourceLocation(file: 'lib/widgets/product_card.dart', line: 42, column: 99, length: 0);
      final findings = [_finding(_location)];
      final impacts = [_highHighHighConfidence(location: sameLine)];
      final correlation = correlateRebuildsToFrames(findings, impacts);

      expect(correlation.matched, isEmpty);
    });

    test('two different locations in the same file are tracked completely '
        'independently -- no merging by file alone, and each keeps its own '
        'confidence-driven classification downstream', () {
      const secondLocation = SourceLocation(file: 'lib/widgets/product_card.dart', line: 200, column: 5, length: 0);
      final impacts = [
        _highHighHighConfidence(),
        _highHighLowConfidence(location: secondLocation),
      ];
      // The (unchanged) correlation layer classifies by median rebuild/
      // impact shape only -- both independently qualify as "high impact"
      // candidates at this layer; confidence differentiates them one
      // layer up, in the UnifiedFinding this milestone adds.
      final correlation = correlateRebuildsToFrames(const [], impacts);
      expect(correlation.runtimeOnly, hasLength(2));
      expect(
        correlation.runtimeOnly.map((r) => r.impact.location).toSet(),
        {_location, secondLocation},
      );

      final report = buildUnifiedFindings(
        impacts,
        correlation,
        totalRuns: 5,
        warmup: Duration.zero,
        steadyStateDuration: const Duration(seconds: 10),
        overallConfidence: Confidence.high,
      );
      final highConfidenceFinding = report.findings.firstWhere((f) => f.location == _location);
      final lowConfidenceFinding = report.findings.firstWhere((f) => f.location == secondLocation);
      expect(highConfidenceFinding.evidenceCategory, EvidenceCategory.runtimeOnly);
      expect(lowConfidenceFinding.evidenceCategory, EvidenceCategory.inconclusive);
    });
  });

  group('same source location, multiple static findings', () {
    test('two different rules flagging the same location both produce '
        'independent matched findings against the same runtime evidence', () {
      final findings = [
        _finding(_location, ruleId: 'missing_const_constructor'),
        _finding(_location, ruleId: 'setstate_in_list_builder'),
      ];
      final impact = _highHighHighConfidence();
      final correlation = correlateRebuildsToFrames(findings, [impact]);

      expect(correlation.matched, hasLength(2));
      expect(
        correlation.matched.map((m) => m.finding.ruleId).toSet(),
        {'missing_const_constructor', 'setstate_in_list_builder'},
      );
      // Both reference the same runtime evidence -- not two different
      // (fabricated) impact records.
      expect(correlation.matched[0].impact.location, correlation.matched[1].impact.location);
    });
  });

  group('no fabricated evidence', () {
    test('a UnifiedFinding with no impact and no static finding is not '
        'constructed by the correlation engine at all', () {
      final report = buildUnifiedFindings(
        const [],
        correlateRebuildsToFrames(const [], const []),
        totalRuns: 3,
        warmup: Duration.zero,
        steadyStateDuration: const Duration(seconds: 10),
        overallConfidence: Confidence.high,
      );
      expect(report.allFindings, isEmpty);
      expect(report.findings, isEmpty);
      expect(report.notExercised, isEmpty);
    });

    test('evidenceCategory never claims staticAndRuntime when either side is missing', () {
      final staticOnlyFinding = UnifiedFinding(
        relation: FindingRelation.notExercised,
        location: _location,
        staticFinding: _finding(_location),
      );
      final runtimeOnlyFinding = UnifiedFinding(
        relation: FindingRelation.runtimeOnly,
        location: _location,
        impact: _highHighHighConfidence(),
      );
      expect(staticOnlyFinding.evidenceCategory, isNot(EvidenceCategory.staticAndRuntime));
      expect(runtimeOnlyFinding.evidenceCategory, isNot(EvidenceCategory.staticAndRuntime));
    });
  });
}
