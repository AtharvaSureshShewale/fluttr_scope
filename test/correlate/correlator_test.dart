import 'package:fluttr_scope/src/correlate/correlator.dart';
import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/rebuild_record.dart';
import 'package:test/test.dart';

const _matchedLocation = SourceLocation(file: 'lib/main.dart', line: 22, column: 12, length: 13);
const _unmatchedFindingLocation =
    SourceLocation(file: 'lib/main.dart', line: 40, column: 1, length: 5);
const _unmatchedRuntimeLocation =
    SourceLocation(file: 'lib/other.dart', line: 5, column: 3, length: 8);

Finding _finding(SourceLocation location, {String ruleId = 'missing_const_constructor'}) =>
    Finding(
      ruleId: ruleId,
      category: Category.performance,
      severity: Severity.warning,
      message: 'test finding',
      location: location,
    );

void main() {
  test('attaches evidence to a finding whose location matches a runtime record', () {
    final result = Correlator().correlate(
      [_finding(_matchedLocation)],
      [const RebuildRecord(location: _matchedLocation, rebuildCount: 487)],
    );

    expect(result.findings, hasLength(1));
    expect(result.findings.single.evidence, hasLength(1));
    expect(result.findings.single.evidence.single.rebuildCount, 487);
    expect(result.unexplainedRebuilds, isEmpty);
  });

  test('leaves a finding with no matching runtime record untouched', () {
    final result = Correlator().correlate(
      [_finding(_unmatchedFindingLocation)],
      [const RebuildRecord(location: _matchedLocation, rebuildCount: 487)],
    );

    expect(result.findings.single.evidence, isEmpty);
    // The runtime record found no matching finding, so it surfaces as
    // unexplained rather than being silently dropped.
    expect(result.unexplainedRebuilds, hasLength(1));
    expect(result.unexplainedRebuilds.single.location, _matchedLocation);
  });

  test('a runtime record with no matching finding is reported as unexplained', () {
    final result = Correlator().correlate(
      [_finding(_matchedLocation)],
      [
        const RebuildRecord(location: _matchedLocation, rebuildCount: 3),
        const RebuildRecord(location: _unmatchedRuntimeLocation, rebuildCount: 99),
      ],
    );

    expect(result.findings.single.evidence.single.rebuildCount, 3);
    expect(result.unexplainedRebuilds, hasLength(1));
    expect(result.unexplainedRebuilds.single.location, _unmatchedRuntimeLocation);
  });

  test('multiple findings sharing one location all get evidence from the same record', () {
    final result = Correlator().correlate(
      [
        _finding(_matchedLocation, ruleId: 'missing_const_constructor'),
        _finding(_matchedLocation, ruleId: 'widget_returning_method'),
      ],
      [const RebuildRecord(location: _matchedLocation, rebuildCount: 10)],
    );

    expect(result.findings, hasLength(2));
    expect(result.findings.every((f) => f.evidence.single.rebuildCount == 10), isTrue);
    expect(result.unexplainedRebuilds, isEmpty);
  });

  test('does not fabricate evidence or severity changes for an unmatched finding', () {
    final original = _finding(_unmatchedFindingLocation);
    final result = Correlator().correlate([original], const []);

    expect(result.findings.single.severity, original.severity);
    expect(result.findings.single.evidence, isEmpty);
  });
}
