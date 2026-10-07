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

  group('with line text', () {
    // file -> lines, 1-based via the reader below.
    LineTextReader reader(Map<String, List<String>> files) =>
        (file, line) => files[file]?[line - 1];

    test('a new finding with the same message as a known one is the one reported', () {
      // Found on a real app: the old count-only matching hid the *new*
      // setState (it came first in the file) and reported the known one.
      final before = {'lib/main.dart': ['x', 'setState(() => a = 1);']};
      final baseline = Baseline.fromFindings(
        [_finding('missing_mounted_check', 2)],
        lineText: reader(before),
      );

      final after = {
        'lib/main.dart': ['x', '  setState(() {});', 'y', '  setState(() => a = 1);'],
      };
      final result = baseline.filterNew(
        [_finding('missing_mounted_check', 2), _finding('missing_mounted_check', 4)],
        lineText: reader(after),
      );
      expect(result.map((f) => f.location.line), [2]);
    });

    test('a known finding whose line was edited still counts as known', () {
      final baseline = Baseline.fromFindings(
        [_finding('avoid_print', 1)],
        lineText: reader({'lib/main.dart': ["print('a');"]}),
      );
      final result = baseline.filterNew(
        [_finding('avoid_print', 1)],
        lineText: reader({'lib/main.dart': ["print('a, edited');"]}),
      );
      expect(result, isEmpty);
    });

    test('a version-1 baseline without line text still loads and matches by count', () {
      final v1 = Baseline.fromJson({
        'version': 1,
        'entries': [
          {'ruleId': 'avoid_print', 'file': 'lib/main.dart', 'message': 'msg', 'count': 1},
        ],
      });
      final result = v1.filterNew(
        [_finding('avoid_print', 7), _finding('avoid_print', 9)],
        lineText: reader({'lib/main.dart': List.filled(10, "print('x');")}),
      );
      expect(result, hasLength(1));
    });
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
