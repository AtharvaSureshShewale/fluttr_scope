import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../baseline/baseline.dart';
import '../coverage/file_coverage.dart';
import '../coverage/lcov_parser.dart';
import '../dependency/dependency_audit.dart';
import '../dependency/osv_client.dart';
import '../model/finding.dart';
import '../model/severity.dart';
import '../report/json_report.dart';
import '../report/sarif_report.dart';
import '../static/all_rules.dart';
import '../static/engine.dart';
import 'load_config.dart';

class AnalyzeCommand extends Command<int> {
  @override
  final name = 'analyze';

  @override
  final description = 'Run static rules against a Flutter/Dart project.';

  AnalyzeCommand() {
    argParser
      ..addOption(
        'format',
        allowed: ['console', 'json', 'sarif'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption('out', help: 'Write the report to this file instead of stdout.')
      ..addFlag(
        'dependency-audit',
        defaultsTo: true,
        help: 'Check pubspec.lock against OSV.dev for known vulnerabilities.',
      )
      ..addOption(
        'coverage',
        help: 'Path to an lcov.info file (default: <target>/coverage/lcov.info). '
            'Silently skipped if not found.',
      )
      ..addFlag(
        'fatal-warnings',
        defaultsTo: true,
        help: 'Exit with a non-zero code when there are warnings (errors always do).',
      )
      ..addFlag(
        'fatal-infos',
        help: 'Exit with a non-zero code when there are infos.',
      )
      ..addOption(
        'baseline',
        help: 'Hide findings already recorded in this baseline file, reporting '
            'only new ones. Default with --write-baseline: '
            '<target>/$defaultBaselineFileName.',
      )
      ..addFlag(
        'write-baseline',
        negatable: false,
        help: 'Record every current finding to the baseline file and exit 0.',
      );
  }

  @override
  Future<int> run() async {
    final targetArg = argResults!.rest.isEmpty ? '.' : argResults!.rest.first;
    final config = loadProjectConfig(targetArg);
    final engine = AnalysisEngine(allRules(), config: config);

    var findings = await engine.analyze(targetArg);

    if (argResults!['dependency-audit'] as bool) {
      try {
        findings.addAll(config.apply(await auditDependencies(targetArg)));
      } on OsvQueryException catch (e) {
        stderr.writeln('warning: dependency audit skipped ($e)');
      } on SocketException catch (e) {
        stderr.writeln('warning: dependency audit skipped (no network? $e)');
      }
    }

    final baselineArg = argResults!['baseline'] as String?;
    if (argResults!['write-baseline'] as bool) {
      final path = baselineArg ?? p.join(targetArg, defaultBaselineFileName);
      await Baseline.fromFindings(findings, lineText: projectLineReader(targetArg)).save(path);
      stderr.writeln('Wrote ${findings.length} finding(s) to $path.');
      return 0;
    }
    if (baselineArg != null) {
      final before = findings.length;
      findings = Baseline.load(baselineArg)
          .filterNew(findings, lineText: projectLineReader(targetArg));
      stderr.writeln('${before - findings.length} finding(s) hidden by baseline $baselineArg.');
    }

    findings.sort((a, b) {
      final byFile = a.location.file.compareTo(b.location.file);
      if (byFile != 0) return byFile;
      return a.location.line.compareTo(b.location.line);
    });

    final coveragePath = (argResults!['coverage'] as String?) ??
        p.join(targetArg, 'coverage', 'lcov.info');
    final coverageFile = File(coveragePath);
    final coverage = coverageFile.existsSync()
        ? parseLcov(await coverageFile.readAsString())
        : const <FileCoverage>[];

    final output = switch (argResults!['format']) {
      'json' => toJsonReport(findings, coverage),
      'sarif' => toSarifReport(findings),
      _ => _toConsoleReport(findings, coverage),
    };

    final outPath = argResults!['out'] as String?;
    if (outPath != null) {
      await File(outPath).writeAsString(output);
    } else {
      stdout.writeln(output);
    }

    return exitCodeFor(
      findings,
      fatalWarnings: argResults!['fatal-warnings'] as bool,
      fatalInfos: argResults!['fatal-infos'] as bool,
    );
  }
}

/// Mirrors `dart analyze`: errors always fail, warnings fail unless
/// `--no-fatal-warnings`, infos fail only with `--fatal-infos`.
int exitCodeFor(
  List<Finding> findings, {
  required bool fatalWarnings,
  required bool fatalInfos,
}) {
  bool any(Severity s) => findings.any((f) => f.severity == s);
  if (any(Severity.error)) return 1;
  if (fatalWarnings && any(Severity.warning)) return 1;
  if (fatalInfos && any(Severity.info)) return 1;
  return 0;
}

String _toConsoleReport(List<Finding> findings, List<FileCoverage> coverage) {
  final buffer = StringBuffer();

  if (findings.isEmpty) {
    buffer.writeln('No findings.');
  } else {
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
    buffer.writeln();
    buffer.writeln('${findings.length} finding(s).');
  }

  if (coverage.isNotEmpty) {
    final totalFound = coverage.fold(0, (sum, f) => sum + f.linesFound);
    final totalHit = coverage.fold(0, (sum, f) => sum + f.linesHit);
    final overall = totalFound == 0 ? 100.0 : (totalHit / totalFound) * 100;

    buffer.writeln();
    buffer.writeln('Coverage: ${overall.toStringAsFixed(1)}% '
        '($totalHit/$totalFound lines)');

    final worst = [...coverage]..sort((a, b) => a.percentage.compareTo(b.percentage));
    for (final file in worst.take(5)) {
      buffer.writeln(
        '  ${file.percentage.toStringAsFixed(1)}%  ${file.file} '
        '(${file.linesHit}/${file.linesFound})',
      );
    }
  }

  return buffer.toString();
}
