import 'dart:convert';

import '../coverage/file_coverage.dart';
import '../model/finding.dart';

String toJsonReport(List<Finding> findings, List<FileCoverage> coverage) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'findings': findings.map((f) => f.toJson()).toList(),
    'coverage': coverage.map((c) => c.toJson()).toList(),
  });
}
