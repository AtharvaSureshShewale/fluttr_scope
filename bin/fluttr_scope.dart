import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:fluttr_scope/src/cli/analyze_command.dart';
import 'package:fluttr_scope/src/cli/correlate_command.dart';
import 'package:fluttr_scope/src/cli/measure_command.dart';
import 'package:fluttr_scope/src/cli/security_command.dart';
import 'package:fluttr_scope/src/config/project_config.dart';
import 'package:fluttr_scope/src/version.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'fluttr_scope',
    'Runtime-correlated static analysis for Flutter.',
  )
    ..addCommand(AnalyzeCommand())
    ..addCommand(MeasureCommand())
    ..addCommand(CorrelateCommand())
    ..addCommand(SecurityCommand());
  runner.argParser.addFlag('version', negatable: false, help: 'Print the version and exit.');

  int exitCode;
  try {
    final topLevel = runner.parse(arguments);
    if (topLevel['version'] as bool) {
      stdout.writeln('fluttr_scope $packageVersion');
      exitCode = 0;
    } else {
      exitCode = await runner.runCommand(topLevel) ?? 0;
    }
  } on UsageException catch (e) {
    stderr.writeln('${e.message}\n\n${e.usage}');
    exitCode = 64; // EX_USAGE, same as `dart analyze`.
  } on ConfigException catch (e) {
    stderr.writeln('error: $e');
    exitCode = 2;
  }
  exit(exitCode);
}
