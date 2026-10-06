import 'dart:io';

import 'package:fluttr_scope/src/baseline/baseline.dart';
import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Finding _finding(String ruleId, int line, {String file = 'lib/main.dart'}) => Finding(
      ruleId: ruleId,
      category: Category.style,
      severity: Severity.warning,
      message: 'msg',
      location: SourceLocation(file: file, line: line, column: 1, length: 1),
    );

void main() {
  test('a finding recorded in the baseline is hidden even after its line moves', () {
    final baseline = Baseline.fromFindings([_finding('avoid_print', 10)]);
    expect(baseline.filterNew([_finding('avoid_print', 25)]), isEmpty);
  });

  test('matching is by count: extra findings of the same kind are reported', () {
    final baseline = Baseline.fromFindings([_finding('avoid_print', 1), _finding('avoid_print', 2)]);
    final result = baseline.filterNew([
      _finding('avoid_print', 1),
      _finding('avoid_print', 2),
      _finding('avoid_print', 3),
    ]);
    expect(result, hasLength(1));
  });

  test('a different file or rule is new', () {
    final baseline = Baseline.fromFindings([_finding('avoid_print', 1)]);
    final result = baseline.filterNew([
      _finding('avoid_print', 1, file: 'lib/other.dart'),
      _finding('todo_comment', 1),
    ]);
    expect(result, hasLength(2));
  });

  test('round-trips through a file', () async {
    final dir = await Directory.systemTemp.createTemp('fluttr_scope_baseline');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, defaultBaselineFileName);

    await Baseline.fromFindings([_finding('avoid_print', 1), _finding('avoid_print', 2)]).save(path);
    final loaded = Baseline.load(path);
    expect(loaded.length, 2);
    expect(loaded.filterNew([_finding('avoid_print', 9), _finding('avoid_print', 8)]), isEmpty);
  });
}
