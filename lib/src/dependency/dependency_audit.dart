import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/category.dart';
import '../model/finding.dart';
import '../model/severity.dart';
import '../model/source_location.dart';
import 'osv_client.dart';
import 'pubspec_lock.dart';

/// Cross-references `pubspec.lock` against OSV.dev and returns one
/// [Finding] per (package, vulnerability) pair found for the exact locked
/// version. Returns an empty list if there's no lockfile or nothing is
/// affected.
Future<List<Finding>> auditDependencies(String root, {OsvClient? client}) async {
  final packages = parsePubspecLock(root);
  if (packages.isEmpty) return const [];

  final osv = client ?? OsvClient();
  try {
    final vulnIdsByPackage = await osv.queryBatch(packages);
    if (vulnIdsByPackage.isEmpty) return const [];

    final uniqueIds = vulnIdsByPackage.values.expand((ids) => ids).toSet();
    final vulnById = <String, OsvVulnerability>{};
    for (final id in uniqueIds) {
      vulnById[id] = await osv.getVulnerability(id);
    }

    final lockLines = File(p.join(root, 'pubspec.lock')).readAsLinesSync();
    final findings = <Finding>[];
    for (final entry in vulnIdsByPackage.entries) {
      final location = _locatePackage(lockLines, entry.key);
      for (final vulnId in entry.value) {
        final vuln = vulnById[vulnId];
        if (vuln == null) continue;
        findings.add(Finding(
          ruleId: 'dependency_vulnerability',
          category: Category.security,
          severity: Severity.error,
          message: '${entry.key}: known vulnerability ${vuln.id} — '
              '${vuln.summary}',
          location: location,
        ));
      }
    }
    return findings;
  } finally {
    if (client == null) osv.close();
  }
}

/// Finds the line in `pubspec.lock` where [packageName]'s entry starts,
/// e.g. `  http:` under the top-level `packages:` map.
SourceLocation _locatePackage(List<String> lockLines, String packageName) {
  for (var i = 0; i < lockLines.length; i++) {
    if (lockLines[i] == '  $packageName:') {
      return SourceLocation(
        file: 'pubspec.lock',
        line: i + 1,
        column: 3,
        length: packageName.length,
      );
    }
  }
  return const SourceLocation(file: 'pubspec.lock', line: 1, column: 1, length: 0);
}
