import 'dart:io';

import '../config/project_config.dart';
import '../static/all_rules.dart';

/// Loads [root]'s `fluttr_scope.yaml`, printing any non-fatal warnings
/// (unknown keys, misspelled rule ids) to stderr.
ProjectConfig loadProjectConfig(String root) {
  final config = ProjectConfig.load(
    root,
    knownRuleIds: {for (final r in allRules()) r.id, ...nonDartRuleIds},
  );
  for (final warning in config.warnings) {
    stderr.writeln('warning: $configFileName: $warning');
  }
  return config;
}
