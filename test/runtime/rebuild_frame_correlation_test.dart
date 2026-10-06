import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/rebuild_frame_correlation.dart';
import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:fluttr_scope/src/runtime/widget_frame_impact.dart';
import 'package:test/test.dart';

const _location = SourceLocation(file: 'lib/widgets/product_card.dart', line: 42, column: 12, length: 0);
const _otherLocation = SourceLocation(file: 'lib/widgets/header.dart', line: 7, column: 3, length: 0);

FrameMetrics _f({required int buildUs}) => FrameMetrics(
      frameNumber: 1,
      build: Duration(microseconds: buildUs),
      raster: Duration.zero,
      elapsed: Duration(microseconds: buildUs),
      startTimeMicros: 0,
    );

/// A synthetic per-run [WidgetFrameImpact] with directly controlled
/// rebuild count and over-budget frame count/percent.
WidgetFrameImpact _impact({
  SourceLocation location = _location,
  required int rebuildCount,
  required int overBudgetFrameCount,
  required int framesTouched,
}) {
  final frames = <int>{for (var i = 1; i <= framesTouched; i++) i};
  final overBudget = frames.take(overBudgetFrameCount).toSet();
  return WidgetFrameImpact(
    location: location,
    rebuildCount: rebuildCount,
    framesRebuiltIn: frames,
    overBudgetFramesRebuiltIn: overBudget,
    frameBuildStatsMs: computeStats([_f(buildUs: 5000).build.inMicroseconds / 1000]),
  );
}

Finding _finding(SourceLocation location, {String ruleId = 'setstate_in_list_builder'}) => Finding(
      ruleId: ruleId,
      category: Category.performance,
      severity: Severity.warning,
      message: 'test finding',
      location: location,
    );

void main() {
  group('aggregateWidgetFrameImpactsAcrossRuns', () {
    test('a widget high-rebuild + high-impact consistently across all runs '
        'aggregates to HIGH confidence', () {
      final perRun = List.generate(
        5,
        (_) => [_impact(rebuildCount: 400, overBudgetFrameCount: 8, framesTouched: 20)],
      );
      final summaries = aggregateWidgetFrameImpactsAcrossRuns(perRun);
      final summary = summaries.single;

      expect(summary.classification, ImpactClassification.highRebuildHighImpact);
      expect(summary.confidence, Confidence.high);
      expect(summary.runsObservedIn, 5);
    });

    test('a widget observed in only 1 of 5 runs is padded with zeros for '
        'the missing runs, so it does not become a HIGH-confidence '
        'finding merely because one run was bad', () {
      final perRun = [
        [_impact(rebuildCount: 900, overBudgetFrameCount: 15, framesTouched: 20)],
        <WidgetFrameImpact>[],
        <WidgetFrameImpact>[],
        <WidgetFrameImpact>[],
        <WidgetFrameImpact>[],
      ];
      final summary = aggregateWidgetFrameImpactsAcrossRuns(perRun).single;

      expect(summary.runsObservedIn, 1);
      // Median across [900,0,0,0,0] is 0 -- nowhere near the high-rebuild
      // threshold, and confidence must not read as trustworthy either.
      expect(summary.rebuildCountStats.median, 0);
      expect(summary.classification, isNot(ImpactClassification.highRebuildHighImpact));
      expect(summary.confidence, isNot(Confidence.high));
    });

    test('a widget with consistently low activity across runs classifies '
        'as low/low', () {
      final perRun = List.generate(
        3,
        (_) => [_impact(rebuildCount: 5, overBudgetFrameCount: 0, framesTouched: 20)],
      );
      final summary = aggregateWidgetFrameImpactsAcrossRuns(perRun).single;
      expect(summary.classification, ImpactClassification.lowRebuildLowImpact);
    });

    test('confidence aggregation: high run-to-run variance in the impact '
        'percentage yields low confidence even if every run individually '
        'looked bad', () {
      final perRun = [
        [_impact(rebuildCount: 900, overBudgetFrameCount: 18, framesTouched: 20)], // 90%
        [_impact(rebuildCount: 900, overBudgetFrameCount: 1, framesTouched: 20)], // 5%
        [_impact(rebuildCount: 900, overBudgetFrameCount: 19, framesTouched: 20)], // 95%
        [_impact(rebuildCount: 900, overBudgetFrameCount: 0, framesTouched: 20)], // 0%
        [_impact(rebuildCount: 900, overBudgetFrameCount: 17, framesTouched: 20)], // 85%
      ];
      final summary = aggregateWidgetFrameImpactsAcrossRuns(perRun).single;
      expect(summary.confidence, isNot(Confidence.high));
    });

    test('duplicate source locations across runs merge into one summary, '
        'not one per run', () {
      final perRun = [
        [_impact(rebuildCount: 10, overBudgetFrameCount: 0, framesTouched: 20)],
        [_impact(rebuildCount: 20, overBudgetFrameCount: 0, framesTouched: 20)],
      ];
      final summaries = aggregateWidgetFrameImpactsAcrossRuns(perRun);
      expect(summaries, hasLength(1));
    });

    test('distinct source locations across runs each get their own summary', () {
      final perRun = [
        [
          _impact(location: _location, rebuildCount: 10, overBudgetFrameCount: 0, framesTouched: 20),
          _impact(
            location: _otherLocation,
            rebuildCount: 60,
            overBudgetFrameCount: 5,
            framesTouched: 10,
          ),
        ],
      ];
      final summaries = aggregateWidgetFrameImpactsAcrossRuns(perRun);
      expect(summaries.map((s) => s.location).toSet(), {_location, _otherLocation});
    });

    test('empty input produces no summaries', () {
      expect(aggregateWidgetFrameImpactsAcrossRuns(const []), isEmpty);
    });
  });

  group('correlateRebuildsToFrames', () {
    test('a static finding with matching runtime impact becomes a matched finding', () {
      final findings = [_finding(_location)];
      final impacts = aggregateWidgetFrameImpactsAcrossRuns([
        [_impact(rebuildCount: 400, overBudgetFrameCount: 8, framesTouched: 20)],
      ]);

      final result = correlateRebuildsToFrames(findings, impacts);
      expect(result.matched, hasLength(1));
      expect(result.matched.single.finding.location, _location);
      expect(result.notExercised, isEmpty);
    });

    test('a static finding whose location was never observed rebuilding is '
        'reported as NOT EXERCISED with no runtime evidence attached', () {
      final findings = [_finding(_otherLocation)];
      final impacts = aggregateWidgetFrameImpactsAcrossRuns([
        [_impact(location: _location, rebuildCount: 400, overBudgetFrameCount: 8, framesTouched: 20)],
      ]);

      final result = correlateRebuildsToFrames(findings, impacts);
      expect(result.notExercised, hasLength(1));
      expect(result.notExercised.single.finding.location, _otherLocation);
      expect(result.matched, isEmpty);
    });

    test('a high-rebuild/high-impact widget with no matching static finding '
        'is reported as a runtime-only finding', () {
      final impacts = aggregateWidgetFrameImpactsAcrossRuns([
        [_impact(rebuildCount: 400, overBudgetFrameCount: 8, framesTouched: 20)],
      ]);

      final result = correlateRebuildsToFrames(const [], impacts);
      expect(result.runtimeOnly, hasLength(1));
      expect(result.runtimeOnly.single.impact.location, _location);
    });

    test('a low-impact widget with no matching static finding does NOT '
        'become a runtime-only finding -- only high/high widgets are '
        '"findings"', () {
      final impacts = aggregateWidgetFrameImpactsAcrossRuns([
        [_impact(rebuildCount: 5, overBudgetFrameCount: 0, framesTouched: 20)],
      ]);

      final result = correlateRebuildsToFrames(const [], impacts);
      expect(result.runtimeOnly, isEmpty);
    });

    test('no static rule is invented for a runtime-only finding -- the '
        'result carries only the impact data, no synthetic Finding/ruleId', () {
      final impacts = aggregateWidgetFrameImpactsAcrossRuns([
        [_impact(rebuildCount: 400, overBudgetFrameCount: 8, framesTouched: 20)],
      ]);
      final result = correlateRebuildsToFrames(const [], impacts);
      // RuntimeOnlyFinding only exposes the WidgetFrameImpactSummary --
      // there's no Finding/ruleId field to have fabricated one into.
      expect(result.runtimeOnly.single.impact.location, _location);
    });

    test('empty findings and empty impacts correlate to nothing, without error', () {
      final result = correlateRebuildsToFrames(const [], const []);
      expect(result.matched, isEmpty);
      expect(result.notExercised, isEmpty);
      expect(result.runtimeOnly, isEmpty);
    });
  });

  group('formatWidgetFrameImpact / formatRebuildFrameCorrelation', () {
    test('never states causation -- always uses "overlapped"/"associated '
        'with", and always includes the causation disclaimer', () {
      final impacts = aggregateWidgetFrameImpactsAcrossRuns([
        [_impact(rebuildCount: 400, overBudgetFrameCount: 8, framesTouched: 20)],
      ]);
      final result = correlateRebuildsToFrames([_finding(_location)], impacts);
      final report = formatRebuildFrameCorrelation(result);

      expect(report, isNot(contains('caused')));
      expect(report, contains('overlapped'));
      expect(report, contains('not a proven causal relationship'));
    });

    test('NOT EXERCISED findings are listed without any runtime numbers attached', () {
      final result = correlateRebuildsToFrames([_finding(_otherLocation)], const []);
      final report = formatRebuildFrameCorrelation(result);
      expect(report, contains('NOT EXERCISED'));
      expect(report, contains(_otherLocation.toString()));
    });

    test('an empty correlation result reports plainly rather than an empty block', () {
      final result = correlateRebuildsToFrames(const [], const []);
      final report = formatRebuildFrameCorrelation(result);
      expect(report, contains('No performance findings'));
    });
  });
}
