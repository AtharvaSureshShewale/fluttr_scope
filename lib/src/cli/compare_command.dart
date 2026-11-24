import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../compare/compare.dart';

class CompareCommand extends Command<int> {
  @override
  final name = 'compare';

  @override
  final description = 'Compare two `measure --runs N --format json` results: what got '
      'better, what got worse, and what changed by less than the runs vary.';

  @override
  String get invocation => '${runner!.executableName} $name <before.json> <after.json>';

  CompareCommand() {
    argParser
      ..addOption(
        'format',
        allowed: ['console', 'json'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption('out', help: 'Write the report to this file instead of stdout.')
      ..addFlag(
        'fail-on-regression',
        negatable: false,
        help: 'Exit 1 if frame timing or total rebuilds got clearly worse (for CI).',
      );
  }

  @override
  Future<int> run() async {
    final paths = argResults!.rest;
    if (paths.length != 2) usageException('Give two files: <before.json> <after.json>.');

    final Comparison comparison;
    try {
      comparison = compareMeasurements(
        _load(paths[0]),
        _load(paths[1]),
        beforeLabel: paths[0],
        afterLabel: paths[1],
      );
    } on CompareInputException catch (e) {
      stderr.writeln(e.message);
      return 2;
    }

    final output = switch (argResults!['format']) {
      'json' => const JsonEncoder.withIndent('  ').convert(comparison.toJson()),
      _ => formatComparison(comparison),
    };
    final outPath = argResults!['out'] as String?;
    if (outPath != null) {
      await File(outPath).writeAsString(output);
    } else {
      stdout.writeln(output);
    }

    return argResults!['fail-on-regression'] as bool && comparison.hasRegression ? 1 : 0;
  }
}

Map<String, Object?> _load(String path) {
  final file = File(path);
  if (!file.existsSync()) throw CompareInputException('$path: no such file.');
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is Map<String, Object?>) return json;
  } on FormatException {
    // reported below
  }
  throw CompareInputException('$path is not JSON from `fluttr_scope measure --format json`.');
}
