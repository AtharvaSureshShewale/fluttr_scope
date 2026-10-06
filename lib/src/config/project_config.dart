import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../model/finding.dart';
import '../model/severity.dart';

/// The per-project config file name, looked up at the analyzed project's
/// root.
const configFileName = 'fluttr_scope.yaml';

/// Rule ids produced outside the static engine (platform manifest scans and
/// the dependency audit) -- valid in [ProjectConfig] alongside the static
/// rule ids, even though no [StaticRule] reports them.
const nonDartRuleIds = {
  'android_cleartext_traffic_enabled',
  'ios_arbitrary_loads_enabled',
  'dependency_vulnerability',
};

/// Thrown when `fluttr_scope.yaml` exists but isn't shaped the way
/// [ProjectConfig.parse] expects.
class ConfigException implements Exception {
  final String message;

  const ConfigException(this.message);

  @override
  String toString() => '$configFileName: $message';
}

/// A project's `fluttr_scope.yaml`:
///
/// ```yaml
/// exclude:
///   - lib/generated/**
/// rules:
///   todo_comment: false        # disable
///   avoid_print: error         # override severity (info/warning/error)
/// ```
///
/// Every key is optional; a missing file is the same as an empty one.
class ProjectConfig {
  final List<Glob> excludes;
  final Set<String> disabledRules;
  final Map<String, Severity> severityOverrides;

  /// Non-fatal problems found while parsing (e.g. an unknown rule id) --
  /// worth surfacing, but not worth refusing to run over.
  final List<String> warnings;

  const ProjectConfig({
    this.excludes = const [],
    this.disabledRules = const {},
    this.severityOverrides = const {},
    this.warnings = const [],
  });

  static const empty = ProjectConfig();

  /// Loads `fluttr_scope.yaml` from [root], or returns [empty] if there's
  /// none. [knownRuleIds] is used only to warn about typos.
  static ProjectConfig load(String root, {required Set<String> knownRuleIds}) {
    final file = File(p.join(root, configFileName));
    if (!file.existsSync()) return empty;
    return parse(file.readAsStringSync(), knownRuleIds: knownRuleIds);
  }

  static ProjectConfig parse(String content, {required Set<String> knownRuleIds}) {
    final Object? doc;
    try {
      doc = loadYaml(content);
    } on YamlException catch (e) {
      throw ConfigException('invalid YAML: ${e.message}');
    }
    if (doc == null) return empty;
    if (doc is! YamlMap) throw const ConfigException('expected a map at the top level');

    final warnings = <String>[];
    for (final key in doc.keys) {
      if (key != 'exclude' && key != 'rules') {
        warnings.add('unknown key "$key" ignored');
      }
    }

    final excludes = <Glob>[];
    final rawExclude = doc['exclude'];
    if (rawExclude != null) {
      if (rawExclude is! YamlList || rawExclude.any((e) => e is! String)) {
        throw const ConfigException('"exclude" must be a list of glob strings');
      }
      excludes.addAll(rawExclude.cast<String>().map(Glob.new));
    }

    final disabled = <String>{};
    final overrides = <String, Severity>{};
    final rawRules = doc['rules'];
    if (rawRules != null) {
      if (rawRules is! YamlMap) {
        throw const ConfigException('"rules" must be a map of rule id to true/false/severity');
      }
      for (final entry in rawRules.entries) {
        final id = entry.key.toString();
        if (!knownRuleIds.contains(id)) {
          warnings.add('unknown rule "$id" ignored');
          continue;
        }
        final value = entry.value;
        if (value == false) {
          disabled.add(id);
        } else if (value == true) {
          // Explicitly enabled -- the default, nothing to record.
        } else if (value is String && Severity.values.any((s) => s.name == value)) {
          overrides[id] = Severity.values.byName(value);
        } else {
          throw ConfigException(
            'rule "$id": expected true, false, info, warning, or error, got "$value"',
          );
        }
      }
    }

    return ProjectConfig(
      excludes: excludes,
      disabledRules: disabled,
      severityOverrides: overrides,
      warnings: warnings,
    );
  }

  /// Whether [relativePath] (root-relative, forward slashes) matches an
  /// `exclude` glob.
  bool isExcluded(String relativePath) => excludes.any((g) => g.matches(relativePath));

  bool isRuleEnabled(String ruleId) => !disabledRules.contains(ruleId);

  /// Drops findings from disabled rules or excluded files and applies
  /// severity overrides. Safe to call on findings that already went through
  /// [AnalysisEngine] (which applies the same config) -- it's idempotent --
  /// and needed for findings from outside it (manifests, dependency audit).
  List<Finding> apply(List<Finding> findings) => [
        for (final f in findings)
          if (isRuleEnabled(f.ruleId) && !isExcluded(f.location.file))
            switch (severityOverrides[f.ruleId]) {
              final severity? => f.copyWith(severity: severity),
              null => f,
            },
      ];
}
