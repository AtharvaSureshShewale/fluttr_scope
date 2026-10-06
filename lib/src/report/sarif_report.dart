import 'dart:convert';

import '../model/finding.dart';
import '../model/severity.dart';

/// Renders [findings] as SARIF 2.1.0 — the format GitHub Code Scanning,
/// Azure DevOps, and most enterprise consoles ingest natively.
String toSarifReport(List<Finding> findings) {
  final rules = <String, Map<String, Object?>>{};
  for (final finding in findings) {
    rules.putIfAbsent(
      finding.ruleId,
      () => {
        'id': finding.ruleId,
        'shortDescription': {'text': finding.message},
      },
    );
  }

  final report = {
    r'$schema':
        'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'fluttr_scope',
            'informationUri': 'https://github.com/AtharvaSureshShewale/fluttr_scope',
            'rules': rules.values.toList(),
          },
        },
        'results': findings.map(_toSarifResult).toList(),
      },
    ],
  };

  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(report);
}

Map<String, Object?> _toSarifResult(Finding finding) => {
      'ruleId': finding.ruleId,
      'level': _sarifLevel(finding.severity),
      'message': {'text': finding.message},
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': {'uri': finding.location.file},
            'region': {
              'startLine': finding.location.line,
              'startColumn': finding.location.column,
            },
          },
        },
      ],
    };

String _sarifLevel(Severity severity) => switch (severity) {
      Severity.info => 'note',
      Severity.warning => 'warning',
      Severity.error => 'error',
    };
