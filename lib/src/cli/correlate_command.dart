import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../correlate/correlator.dart';
import '../runtime/frame_budget.dart';
import '../runtime/frame_metrics.dart';
import '../runtime/measurement_result.dart';
import '../static/all_rules.dart';
import '../static/engine.dart';
import 'format_bytes.dart';
import 'load_config.dart';

class CorrelateCommand extends Command<int> {
  @override
  final name = 'correlate';

  @override
  final description =
      'Run static analysis fresh and join it against a previously captured '
      '`measure --format=json` output, by exact source location.';

  CorrelateCommand() {
    argParser
      ..addOption(
        'runtime',
        mandatory: true,
        help: 'Path to a JSON file produced by `measure --format=json`.',
      )
      ..addOption(
        'format',
        allowed: ['console', 'json'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption('out', help: 'Write the report to this file instead of stdout.')
      ..addOption(
        'warmup',
        defaultsTo: '0',
        help: 'Seconds of frame data (from the start of the capture) to report '
            'separately as STARTUP, excluded from the steady-state frame-budget '
            'stats. See `measure --help` for the same option.',
      );
  }

  @override
  Future<int> run() async {
    final targetArg = argResults!.rest.isEmpty ? '.' : argResults!.rest.first;
    final runtimePath = argResults!['runtime'] as String;
    final warmup = Duration(seconds: int.parse(argResults!['warmup'] as String));

    final findings =
        await AnalysisEngine(allRules(), config: loadProjectConfig(targetArg)).analyze(targetArg);
    final runtimeJson = jsonDecode(await File(runtimePath).readAsString()) as Map<String, Object?>;
    final measurement = MeasurementResult.fromJson(runtimeJson);

    final result = Correlator().correlate(findings, measurement.rebuilds);
    result.findings.sort((a, b) {
      final byFile = a.location.file.compareTo(b.location.file);
      if (byFile != 0) return byFile;
      return a.location.line.compareTo(b.location.line);
    });

    final output = switch (argResults!['format']) {
      'json' => _toJsonReport(result, measurement.heapUsage, measurement.frames),
      _ => _toConsoleReport(result, measurement.heapUsage, measurement.frames, warmup),
    };

    final outPath = argResults!['out'] as String?;
    if (outPath != null) {
      await File(outPath).writeAsString(output);
    } else {
      stdout.writeln(output);
    }

    return 0;
  }
}

String _toJsonReport(
  CorrelationResult result,
  HeapUsage heapUsage,
  List<FrameMetrics> frames,
) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'findings': result.findings.map((f) => f.toJson()).toList(),
    'unexplainedRebuilds': result.unexplainedRebuilds.map((r) => r.toJson()).toList(),
    'heapUsage': heapUsage.toJson(),
    'frames': frames.map((f) => f.toJson()).toList(),
  });
}

String _toConsoleReport(
  CorrelationResult result,
  HeapUsage heapUsage,
  List<FrameMetrics> frames,
  Duration warmup,
) {
  final buffer = StringBuffer();

  if (result.findings.isEmpty) {
    buffer.writeln('No findings.');
  } else {
    String? currentFile;
    for (final finding in result.findings) {
      if (finding.location.file != currentFile) {
        currentFile = finding.location.file;
        buffer.writeln(currentFile);
      }
      final evidence =
          finding.evidence.isEmpty ? '' : '  [${finding.evidence.single.rebuildCount} rebuilds]';
      buffer.writeln(
        '  ${finding.location.line}:${finding.location.column}  '
        '${finding.severity.name.padRight(7)} ${finding.message} '
        '(${finding.ruleId})$evidence',
      );
    }
    buffer.writeln();
    final withEvidence = result.findings.where((f) => f.evidence.isNotEmpty).length;
    buffer.writeln(
      '${result.findings.length} finding(s), $withEvidence with runtime evidence.',
    );
  }

  if (result.unexplainedRebuilds.isNotEmpty) {
    buffer.writeln();
    buffer.writeln(
      'Rebuilt with no matching static finding (no rule explains why):',
    );
    for (final record in result.unexplainedRebuilds) {
      buffer.writeln('  ${record.rebuildCount.toString().padLeft(5)}  ${record.location}');
    }
  }

  buffer.writeln();
  buffer.writeln(
    'Retained heap: ${formatBytes(heapUsage.beforeBytes)} -> '
    '${formatBytes(heapUsage.afterBytes)} '
    '(${heapUsage.deltaBytes >= 0 ? '+' : ''}${formatBytes(heapUsage.deltaBytes)})',
  );

  buffer.writeln();
  buffer.write(formatFrameCapture(splitByWarmup(frames, warmup)));

  return buffer.toString();
}
