import 'dart:convert';

import 'package:fluttr_scope/src/coverage/file_coverage.dart';
import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/report/json_report.dart';
import 'package:test/test.dart';

void main() {
  test('serializes findings and coverage into the {findings, coverage} shape', () {
    final finding = Finding(
      ruleId: 'avoid_print',
      category: Category.style,
      severity: Severity.warning,
      message: 'Avoid print.',
      location: const SourceLocation(file: 'lib/main.dart', line: 1, column: 2, length: 3),
    );
    const coverage = [
      FileCoverage(
        file: 'lib/main.dart',
        linesFound: 10,
        linesHit: 5,
        uncoveredLines: [6, 7, 8, 9, 10],
      ),
    ];

    final report = jsonDecode(toJsonReport([finding], coverage)) as Map<String, Object?>;

    expect(report.keys, unorderedEquals(['findings', 'coverage']));

    final findingsJson = report['findings'] as List;
    expect(findingsJson.single, {
      'ruleId': 'avoid_print',
      'category': 'style',
      'severity': 'warning',
      'message': 'Avoid print.',
      'location': {'file': 'lib/main.dart', 'line': 1, 'column': 2, 'length': 3},
      'evidence': [],
    });

    final coverageJson = report['coverage'] as List;
    expect(coverageJson.single, {
      'file': 'lib/main.dart',
      'linesFound': 10,
      'linesHit': 5,
      'percentage': 50.0,
      'uncoveredLines': [6, 7, 8, 9, 10],
    });
  });

  test('empty findings and coverage serialize to empty arrays, not null', () {
    final report = jsonDecode(toJsonReport(const [], const [])) as Map<String, Object?>;
    expect(report['findings'], isEmpty);
    expect(report['coverage'], isEmpty);
  });
}
