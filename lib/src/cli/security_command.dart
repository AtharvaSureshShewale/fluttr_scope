import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../dependency/dependency_audit.dart';
import '../dependency/osv_client.dart';
import '../model/category.dart';
import '../model/finding.dart';
import '../security/manifest_scanner.dart';
import '../security/security_verdict.dart';
import '../static/all_rules.dart';
import '../static/engine.dart';
import 'load_config.dart';

class SecurityCommand extends Command<int> {
  @override
  final name = 'security';

  @override
  final description =
      'Check whether the project is secure: hardcoded secrets, insecure '
      'transport, unsafe randomness, and known CVEs in dependencies at '
      'their exact locked versions.';

  SecurityCommand() {
    argParser
      ..addOption(
        'format',
        allowed: ['console', 'json'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption('out', help: 'Write the report to this file instead of stdout.')
      ..addFlag(
        'dependency-audit',
        defaultsTo: true,
        help: 'Also check pubspec.lock against OSV.dev for known vulnerabilities.',
      );
  }

  @override
  Future<int> run() async {
    final targetArg = argResults!.rest.isEmpty ? '.' : argResults!.rest.first;

    final config = loadProjectConfig(targetArg);
    final allFindings = await AnalysisEngine(allRules(), config: config).analyze(targetArg);
    final findings = allFindings.where((f) => f.category == Category.security).toList();
    findings.addAll(config.apply(scanManifests(targetArg)));

    if (argResults!['dependency-audit'] as bool) {
      try {
        findings.addAll(config.apply(await auditDependencies(targetArg)));
      } on OsvQueryException catch (e) {
        stderr.writeln('warning: dependency audit skipped ($e)');
      } on SocketException catch (e) {
        stderr.writeln('warning: dependency audit skipped (no network? $e)');
      }
    }

    findings.sort((a, b) {
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      if (bySeverity != 0) return bySeverity;
      return a.location.file.compareTo(b.location.file);
    });

    final summary = summarizeSecurity(findings);

    final output = switch (argResults!['format']) {
      'json' => _toJsonReport(summary, findings),
      _ => _toConsoleReport(summary, findings),
    };

    final outPath = argResults!['out'] as String?;
    if (outPath != null) {
      await File(outPath).writeAsString(output);
    } else {
      stdout.writeln(output);
    }

    return summary.verdict == SecurityVerdict.critical ? 1 : 0;
  }
}

String _toJsonReport(SecuritySummary summary, List<Finding> findings) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'verdict': summary.verdict.name,
    'criticalCount': summary.criticalCount,
    'warningCount': summary.warningCount,
    'infoCount': summary.infoCount,
    'findings': findings.map((f) => f.toJson()).toList(),
  });
}

String _toConsoleReport(SecuritySummary summary, List<Finding> findings) {
  final buffer = StringBuffer();

  buffer.writeln('Verdict: ${summary.verdict.label}');
  buffer.writeln(
    '${summary.totalCount} finding(s) — ${summary.criticalCount} critical, '
    '${summary.warningCount} warning, ${summary.infoCount} info.',
  );

  if (findings.isNotEmpty) {
    buffer.writeln();
    String? currentFile;
    for (final finding in findings) {
      if (finding.location.file != currentFile) {
        currentFile = finding.location.file;
        buffer.writeln(currentFile);
      }
      buffer.writeln(
        '  ${finding.location.line}:${finding.location.column}  '
        '${finding.severity.name.padRight(7)} ${finding.message} '
        '(${finding.ruleId})',
      );
    }
  }

  return buffer.toString();
}
