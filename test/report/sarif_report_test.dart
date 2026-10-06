import 'dart:convert';

import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/report/sarif_report.dart';
import 'package:test/test.dart';

Finding _finding(Severity severity) => Finding(
      ruleId: 'avoid_print',
      category: Category.style,
      severity: severity,
      message: 'Avoid print.',
      location: const SourceLocation(file: 'lib/main.dart', line: 5, column: 3, length: 5),
    );

void main() {
  test('produces a SARIF 2.1.0 envelope with one rule and one result', () {
    final sarif =
        jsonDecode(toSarifReport([_finding(Severity.warning)])) as Map<String, Object?>;

    expect(sarif['version'], '2.1.0');
    final runs = sarif['runs'] as List;
    expect(runs, hasLength(1));
    final run = (runs.single) as Map<String, Object?>;

    final driver = (run['tool'] as Map<String, Object?>)['driver'] as Map<String, Object?>;
    expect(driver['rules'], [
      {
        'id': 'avoid_print',
        'shortDescription': {'text': 'Avoid print.'},
      },
    ]);

    expect(run['results'], [
      {
        'ruleId': 'avoid_print',
        'level': 'warning',
        'message': {'text': 'Avoid print.'},
        'locations': [
          {
            'physicalLocation': {
              'artifactLocation': {'uri': 'lib/main.dart'},
              'region': {'startLine': 5, 'startColumn': 3},
            },
          },
        ],
      },
    ]);
  });

  test('maps each Severity to the matching SARIF level', () {
    final sarif = jsonDecode(toSarifReport([
      _finding(Severity.info),
      _finding(Severity.warning),
      _finding(Severity.error),
    ])) as Map<String, Object?>;

    final results = ((sarif['runs'] as List).single as Map<String, Object?>)['results'] as List;
    expect(results.map((r) => (r as Map)['level']), ['note', 'warning', 'error']);
  });

  test('one rules entry per distinct ruleId, not per finding', () {
    final sarif = jsonDecode(toSarifReport([
      _finding(Severity.warning),
      _finding(Severity.error),
    ])) as Map<String, Object?>;

    final run = ((sarif['runs'] as List).single) as Map<String, Object?>;
    final driver = (run['tool'] as Map<String, Object?>)['driver'] as Map<String, Object?>;
    expect(driver['rules'], hasLength(1), reason: 'both findings share ruleId avoid_print');
    expect(run['results'], hasLength(2), reason: 'but each finding still gets its own result');
  });
}
