import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../model/category.dart';
import '../runtime/developer_findings.dart';
import '../runtime/device_detection.dart';
import '../runtime/frame_budget.dart';
import '../runtime/measurement_result.dart';
import '../runtime/multi_run.dart';
import '../runtime/rebuild_frame_correlation.dart';
import '../runtime/runtime_driver.dart';
import '../runtime/unified_finding.dart';
import '../runtime/variance_diagnosis.dart';
import '../static/all_rules.dart';
import '../static/engine.dart';
import 'format_bytes.dart';
import 'load_config.dart';

class MeasureCommand extends Command<int> {
  @override
  final name = 'measure';

  @override
  final description =
      'Launch a Flutter app in debug mode and measure widget rebuild counts '
      'by creation location, per-frame build/raster timing, and '
      'retained-heap growth.';

  MeasureCommand() {
    argParser
      ..addOption(
        'seconds',
        defaultsTo: '10',
        help: 'How long to capture rebuilds for.',
      )
      ..addOption(
        'device',
        help: 'flutter run -d <device>. If omitted, the only connected device '
            'is used; with several connected, you must pick one.',
      )
      ..addOption(
        'format',
        allowed: ['console', 'json'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption('out', help: 'Write the report to this file instead of stdout.')
      ..addOption(
        'runs',
        defaultsTo: '5',
        help: 'Number of complete measurement runs (each a full app '
            'launch/relaunch) to average across for a statistically '
            'trustworthy result. --runs=1 reproduces the original single-run '
            'report exactly (no statistics section).',
      )
      ..addOption(
        'warmup',
        defaultsTo: '0',
        help: 'Seconds of frame data (from the start of the capture) to report '
            'separately as STARTUP, excluded from the steady-state frame-budget '
            'stats -- e.g. heavy first-frame asset loading otherwise blends '
            'into and inflates the steady-state numbers. 0 (default) reports '
            'a single unsplit block, matching prior behavior. Does not affect '
            'the rebuild-count list, only the frame-budget report.',
      )
      ..addFlag(
        'verbose',
        help: 'Stream flutter run\'s own output while launching (useful while '
            'a build is slow, e.g. the first Gradle/CMake run).',
      )
      ..addFlag(
        'technical',
        help: 'Show the raw technical rebuild-to-frame report (rule ids, exact '
            'stats, no plain-language framing) instead of the default '
            'developer-friendly findings report. Console format only -- '
            '--format=json is unaffected either way and always includes the '
            'full raw data.',
      );
  }

  @override
  Future<int> run() async {
    final targetArg = argResults!.rest.isEmpty ? '.' : argResults!.rest.first;
    final seconds = int.parse(argResults!['seconds'] as String);
    final String device;
    try {
      device = (argResults!['device'] as String?) ?? await detectDevice();
    } on StateError catch (e) {
      stderr.writeln(e.message);
      return 2;
    }
    final verbose = argResults!['verbose'] as bool;
    final warmup = Duration(seconds: int.parse(argResults!['warmup'] as String));
    final runs = int.parse(argResults!['runs'] as String);
    final onLaunchOutput = verbose ? (String line) => stderr.writeln('  $line') : null;

    if (runs <= 1) {
      // Unchanged from before --runs existed: exactly the original
      // single-run path, reachable via --runs=1.
      stderr.writeln(
        'Launching on $device (debug mode) and capturing rebuilds for ${seconds}s...',
      );

      final result = await RuntimeDriver().measure(
        targetArg,
        duration: Duration(seconds: seconds),
        device: device,
        onLaunchOutput: onLaunchOutput,
      );
      result.rebuilds.sort((a, b) => b.rebuildCount.compareTo(a.rebuildCount));
      result.frames.sort((a, b) => a.frameNumber.compareTo(b.frameNumber));

      final output = switch (argResults!['format']) {
        'json' => _toJsonReport(result),
        _ => _toConsoleReport(result, warmup),
      };
      await _write(output);
      return 0;
    }

    stderr.writeln(
      'Running $runs measurement runs on $device (debug mode), '
      '${seconds}s each, ${warmup.inSeconds}s warm-up...',
    );
    final summary = await measureMultipleRuns(
      targetPath: targetArg,
      runs: runs,
      duration: Duration(seconds: seconds),
      warmup: warmup,
      device: device,
      onLaunchOutput: onLaunchOutput,
      onRunStart: (i, total) => stderr.writeln('Run $i/$total...'),
    );

    final diagnosis = diagnoseVariance(summary);
    final technical = argResults!['technical'] as bool;

    RebuildFrameCorrelationResult? correlation;
    List<WidgetFrameImpactSummary>? widgetImpacts;
    if (summary.validRuns.isNotEmpty) {
      final staticFindings =
          await AnalysisEngine(allRules(), config: loadProjectConfig(targetArg))
              .analyze(targetArg);
      final performanceFindings =
          staticFindings.where((f) => f.category == Category.performance).toList();
      widgetImpacts = aggregateWidgetFrameImpactsAcrossRuns(
        [for (final r in summary.validRuns) r.widgetFrameImpacts],
      );
      correlation = correlateRebuildsToFrames(performanceFindings, widgetImpacts);
    }

    final output = switch (argResults!['format']) {
      // JSON is unaffected by --technical: it's always the full raw data,
      // which is what a machine-readable consumer wants regardless of how
      // the console happens to render it for a human.
      'json' => const JsonEncoder.withIndent('  ').convert({
          ...summary.toJson(),
          if (diagnosis != null) 'varianceDiagnosis': diagnosis.toJson(),
          if (correlation != null)
            'rebuildFrameCorrelation': {
              'matched': [
                for (final m in correlation.matched)
                  {'finding': m.finding.toJson(), 'impact': m.impact.toJson()},
              ],
              'runtimeOnly': [for (final r in correlation.runtimeOnly) r.impact.toJson()],
              'notExercised': [
                for (final n in correlation.notExercised) n.finding.toJson(),
              ],
            },
        }),
      _ => [
          formatMultiRunReport(summary),
          if (diagnosis != null) formatVarianceDiagnosis(diagnosis),
          if (correlation != null)
            technical
                ? formatRebuildFrameCorrelation(correlation)
                : formatDeveloperFindingsReport(buildUnifiedFindings(
                    widgetImpacts!,
                    correlation,
                    totalRuns: summary.validRuns.length,
                    warmup: warmup,
                    steadyStateDuration: Duration(seconds: seconds),
                    overallConfidence: summary.overBudgetPercent!.confidence,
                  )),
        ].join('\n'),
    };
    await _write(output);
    return summary.validRuns.isEmpty ? 1 : 0;
  }

  Future<void> _write(String output) async {
    final outPath = argResults!['out'] as String?;
    if (outPath != null) {
      await File(outPath).writeAsString(output);
    } else {
      stdout.writeln(output);
    }
  }
}

String _toJsonReport(MeasurementResult result) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(result.toJson());
}

String _toConsoleReport(MeasurementResult result, Duration warmup) {
  final buffer = StringBuffer();

  if (result.rebuilds.isEmpty) {
    buffer.writeln('No rebuilds captured.');
  } else {
    for (final record in result.rebuilds) {
      buffer.writeln('  ${record.rebuildCount.toString().padLeft(5)}  ${record.location}');
    }
    buffer.writeln();
    buffer.writeln('${result.rebuilds.length} location(s) rebuilt.');
  }

  final heap = result.heapUsage;
  buffer.writeln();
  buffer.writeln(
    'Retained heap: ${formatBytes(heap.beforeBytes)} -> ${formatBytes(heap.afterBytes)} '
    '(${heap.deltaBytes >= 0 ? '+' : ''}${formatBytes(heap.deltaBytes)})',
  );

  buffer.writeln();
  buffer.write(formatFrameCapture(splitByWarmup(result.frames, warmup)));

  return buffer.toString();
}
