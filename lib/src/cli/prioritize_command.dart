import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../dependency/dependency_audit.dart';
import '../dependency/osv_client.dart';
import '../model/finding.dart';
import '../runtime/device_detection.dart';
import '../runtime/multi_run.dart';
import '../runtime/rebuild_frame_correlation.dart';
import '../security/manifest_scanner.dart';
import '../static/all_rules.dart';
import '../static/engine.dart';
import '../triage/triage.dart';
import '../triage/triage_report.dart';
import 'load_config.dart';

class PrioritizeCommand extends Command<int> {
  @override
  final name = 'prioritize';

  @override
  final description = 'Run the app, then rank every static finding by runtime evidence: '
      'code that ran during slow frames first, code that never ran last.';

  PrioritizeCommand() {
    argParser
      ..addOption(
        'device',
        help: 'flutter run -d <device>. If omitted, the only connected device is used.',
      )
      ..addOption('runs', defaultsTo: '3', help: 'Number of app launches to measure.')
      ..addOption('seconds', defaultsTo: '15', help: 'How long to capture each run for.')
      ..addOption(
        'warmup',
        defaultsTo: '2',
        help: 'Seconds at the start of each run excluded from frame-timing stats.',
      )
      ..addOption(
        'format',
        allowed: ['console', 'json'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption('out', help: 'Write the report to this file instead of stdout.')
      ..addOption(
        'flow',
        help: 'An integration_test file that drives the app during each run '
            '(e.g. integration_test/flow_test.dart), so every run does the same '
            'thing. Recording starts when the flow is ready and stops when it '
            'finishes; --seconds becomes the time limit. See README.',
      )
      ..addFlag('all', negatable: false, help: 'Also list info-level findings.')
      ..addFlag(
        'dependency-audit',
        defaultsTo: true,
        help: 'Also check pubspec.lock against OSV.dev for known vulnerabilities.',
      )
      ..addFlag('verbose', negatable: false, help: 'Stream flutter run\'s own output.');
  }

  @override
  Future<int> run() async {
    final targetArg = argResults!.rest.isEmpty ? '.' : argResults!.rest.first;
    final root = p.normalize(p.absolute(targetArg));
    final runs = int.parse(argResults!['runs'] as String);
    final seconds = Duration(seconds: int.parse(argResults!['seconds'] as String));
    final warmup = Duration(seconds: int.parse(argResults!['warmup'] as String));

    final String device;
    try {
      device = (argResults!['device'] as String?) ?? await detectDevice();
    } on StateError catch (e) {
      stderr.writeln(e.message);
      return 2;
    }

    final findings = await _staticFindings(targetArg);
    stderr.writeln('${findings.length} static finding(s). Measuring $runs run(s) of '
        '${seconds.inSeconds}s on $device (debug mode)...');

    final summary = await measureMultipleRuns(
      targetPath: targetArg,
      runs: runs,
      duration: seconds,
      warmup: warmup,
      device: device,
      onLaunchOutput:
          argResults!['verbose'] as bool ? (line) => stderr.writeln('  $line') : null,
      onRunStart: (i, total) => stderr.writeln('Run $i/$total...'),
      flow: argResults!['flow'] as String?,
    );
    for (final invalid in summary.invalidRuns) {
      stderr.writeln('warning: run #${invalid.runIndex} invalid: ${invalid.reason}');
    }
    if (summary.validRuns.isEmpty && summary.executedLines == null) {
      stderr.writeln('No run completed -- nothing to rank findings with.');
      return 1;
    }
    if (summary.validRuns.isEmpty) {
      stderr.writeln('note: too few frames rendered for frame timing (interact with the app '
          'while it is measured); ranking by which code ran only.');
    }

    final impacts = aggregateWidgetFrameImpactsAcrossRuns(
      [for (final r in summary.validRuns) r.widgetFrameImpacts],
    );
    final linesCache = <String, List<String>?>{};
    final triaged = triageFindings(
      findings,
      impacts: impacts,
      executedLines: summary.executedLines,
      sourceLines: (file) => linesCache.putIfAbsent(file, () {
        final f = File(p.join(root, file));
        return f.existsSync() ? f.readAsLinesSync() : null;
      }),
    );

    final output = switch (argResults!['format']) {
      'json' => const JsonEncoder.withIndent('  ').convert({
          'device': device,
          'validRuns': summary.validRuns.length,
          'requestedRuns': runs,
          if (summary.flow != null) 'flow': summary.flow,
          'findings': [for (final t in triaged) t.toJson()],
        }),
      _ => formatTriageReport(
          triaged,
          TriageContext(
            device: device,
            validRuns: summary.validRuns.length,
            requestedRuns: runs,
            captureDuration: seconds,
            warmup: warmup,
            overallConfidence: summary.overBudgetPercent?.confidence,
            flow: summary.flow,
          ),
          showAll: argResults!['all'] as bool,
        ),
    };

    final outPath = argResults!['out'] as String?;
    if (outPath != null) {
      await File(outPath).writeAsString(output);
    } else {
      stdout.writeln(output);
    }
    return 0;
  }

  /// Every static finding `analyze` and `security` would report.
  Future<List<Finding>> _staticFindings(String target) async {
    final config = loadProjectConfig(target);
    final findings = await AnalysisEngine(allRules(), config: config).analyze(target);
    findings.addAll(config.apply(scanManifests(target)));
    if (argResults!['dependency-audit'] as bool) {
      try {
        findings.addAll(config.apply(await auditDependencies(target)));
      } on OsvQueryException catch (e) {
        stderr.writeln('warning: dependency audit skipped ($e)');
      } on SocketException catch (e) {
        stderr.writeln('warning: dependency audit skipped (no network? $e)');
      }
    }
    return findings;
  }
}
