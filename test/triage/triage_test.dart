import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/executed_lines.dart';
import 'package:fluttr_scope/src/runtime/rebuild_frame_correlation.dart';
import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:fluttr_scope/src/triage/triage.dart';
import 'package:test/test.dart';

Finding _finding(
  String ruleId, {
  String file = 'lib/a.dart',
  int line = 1,
  int column = 1,
  int length = 1,
  Severity severity = Severity.warning,
}) =>
    Finding(
      ruleId: ruleId,
      category: Category.performance,
      severity: severity,
      message: 'm',
      location: SourceLocation(file: file, line: line, column: column, length: length),
    );

/// An impact summary with the same values in every one of 3 runs (so
/// confidence is HIGH), [overBudget] of [touched] frames slow.
WidgetFrameImpactSummary _impact(
  SourceLocation location, {
  required double rebuilds,
  required double overBudget,
  double touched = 10,
}) {
  Stats same(double v) => computeStats([v, v, v]);
  return WidgetFrameImpactSummary(
    location: location,
    totalRuns: 3,
    runsObservedIn: 3,
    rebuildCountStats: same(rebuilds),
    framesTouchedStats: same(touched),
    overBudgetFrameCountStats: same(overBudget),
    percentFramesOverBudgetStats: same(overBudget / touched * 100),
  );
}

void main() {
  group('ExecutedLines.merge', () {
    test('a line hit in any run counts as hit, and is no longer missed', () {
      const a = ExecutedLines(hits: {'lib/a.dart': {1}}, misses: {'lib/a.dart': {2, 3}});
      const b = ExecutedLines(hits: {'lib/a.dart': {2}}, misses: {'lib/b.dart': {9}});
      final merged = a.merge(b);
      expect(merged.hits['lib/a.dart'], {1, 2});
      expect(merged.misses['lib/a.dart'], {3});
      expect(merged.wasMissed('lib/b.dart', 9), isTrue);
    });

    test('round-trips through JSON', () {
      const lines = ExecutedLines(hits: {'lib/a.dart': {3, 1}}, misses: {'lib/a.dart': {2}});
      final back = ExecutedLines.fromJson(lines.toJson());
      expect(back.hits, lines.hits);
      expect(back.misses, lines.misses);
    });
  });

  group('triageFindings', () {
    List<TriagedFinding> triage(
      List<Finding> findings, {
      List<WidgetFrameImpactSummary> impacts = const [],
      ExecutedLines? executed = ExecutedLines.empty,
      Map<String, List<String>> sources = const {},
    }) =>
        triageFindings(
          findings,
          impacts: impacts,
          executedLines: executed,
          sourceLines: (file) => sources[file],
        );

    test('a widget rebuilding during slow frames is hot; one that merely rebuilt ran', () {
      final hot = _finding('missing_const_constructor', line: 5);
      final calm = _finding('missing_const_constructor', line: 9);
      final result = triage([calm, hot], impacts: [
        _impact(hot.location, rebuilds: 400, overBudget: 8),
        _impact(calm.location, rebuilds: 400, overBudget: 0),
      ]);
      expect(result.map((t) => (t.finding.location.line, t.evidence)), [
        (5, RuntimeEvidence.hot),
        (9, RuntimeEvidence.ran),
      ]);
    });

    test('coverage decides ran / not run / no signal for any rule', () {
      const executed = ExecutedLines(
        hits: {'lib/a.dart': {10}},
        misses: {'lib/a.dart': {20}},
      );
      final result = triage([
        _finding('missing_mounted_check', line: 10),
        _finding('avoid_print', line: 20),
        _finding('hardcoded_secret', line: 30), // a constant: neither hit nor missed
      ], executed: executed);
      expect(result.map((t) => (t.finding.ruleId, t.evidence)), [
        ('missing_mounted_check', RuntimeEvidence.ran),
        ('avoid_print', RuntimeEvidence.notRun),
        ('hardcoded_secret', RuntimeEvidence.noSignal),
      ]);
    });

    test('a multi-line finding ran if any line in its span ran', () {
      // A finding spanning lines 1-3 (e.g. a whole method); only line 3 ran.
      final sources = {
        'lib/a.dart': ['void f() {', '  g();', '  h();', '}'],
      };
      final finding = _finding('widget_returning_method', line: 1, length: 'void f() {\n  g();\n  h();'.length);
      final result = triage(
        [finding],
        executed: const ExecutedLines(hits: {'lib/a.dart': {3}}, misses: {'lib/a.dart': {2}}),
        sources: sources,
      );
      expect(result.single.evidence, RuntimeEvidence.ran);
    });

    test('an app library that never loaded never ran; tests and config have no signal', () {
      const executed = ExecutedLines(hits: {'lib/a.dart': {1}}, misses: {});
      final result = triage([
        _finding('avoid_print', file: 'lib/unused.dart'),
        _finding('avoid_print', file: 'test/a_test.dart'),
        _finding('android_cleartext_traffic_enabled', file: 'android/app/src/main/AndroidManifest.xml'),
      ], executed: executed);
      expect(result.map((t) => (t.finding.location.file, t.evidence)), [
        ('lib/unused.dart', RuntimeEvidence.notRun),
        ('test/a_test.dart', RuntimeEvidence.noSignal),
        ('android/app/src/main/AndroidManifest.xml', RuntimeEvidence.noSignal),
      ]);
    });

    test('without any coverage, nothing is claimed to have not run', () {
      final result = triage([_finding('avoid_print')], executed: null);
      expect(result.single.evidence, RuntimeEvidence.noSignal);
    });

    test('within a group, higher severity first', () {
      const executed = ExecutedLines(hits: {'lib/a.dart': {1, 2}}, misses: {});
      final result = triage([
        _finding('a', line: 1, severity: Severity.info),
        _finding('b', line: 2, severity: Severity.error),
      ], executed: executed);
      expect(result.map((t) => t.finding.ruleId), ['b', 'a']);
    });
  });
}
