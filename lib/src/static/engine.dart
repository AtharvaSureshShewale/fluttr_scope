import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../model/finding.dart';
import 'rule.dart';
import 'suppression.dart';

/// Generated-code globs excluded from analysis so build_runner output
/// (freezed, json_serializable, mockito, ...) doesn't drown real findings.
final _excludedGlobs = [
  Glob('**/*.g.dart'),
  Glob('**/*.freezed.dart'),
  Glob('**/*.mocks.dart'),
];

class AnalysisEngine {
  final List<StaticRule> rules;

  /// Per-project settings (excluded paths, disabled rules, severity
  /// overrides). Defaults to [ProjectConfig.empty]: every rule, every file.
  final ProjectConfig config;

  AnalysisEngine(this.rules, {this.config = ProjectConfig.empty});

  /// Analyzes every Dart file under [rootPath], returning findings from all
  /// registered [rules] that aren't disabled, excluded, or suppressed by an
  /// `// ignore: fluttr_scope/<rule_id>` comment.
  Future<List<Finding>> analyze(String rootPath) async {
    final root = p.normalize(p.absolute(rootPath));
    final collection = AnalysisContextCollection(
      includedPaths: [root],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final ruleContext = RuleContext(root: root);
    final activeRules = rules.where((r) => config.isRuleEnabled(r.id)).toList();
    final findings = <Finding>[];
    try {
      for (final context in collection.contexts) {
        for (final filePath in context.contextRoot.analyzedFiles()) {
          if (!filePath.endsWith('.dart')) continue;
          if (_isExcluded(root, filePath)) continue;

          final result = await context.currentSession.getResolvedUnit(filePath);
          if (result is! ResolvedUnitResult) continue;

          final suppressions = Suppressions.parse(result.content);
          for (final rule in activeRules) {
            findings.addAll(rule
                .check(result, ruleContext)
                .where((f) => !suppressions.isSuppressed(f.ruleId, f.location.line)));
          }
        }
      }
    } finally {
      await collection.dispose();
    }

    return config.apply(findings);
  }

  bool _isExcluded(String root, String filePath) {
    final relative = p.relative(filePath, from: root).replaceAll('\\', '/');
    return _excludedGlobs.any((g) => g.matches(relative)) || config.isExcluded(relative);
  }
}
