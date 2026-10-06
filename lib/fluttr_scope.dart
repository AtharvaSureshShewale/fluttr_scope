/// Static and runtime-correlated analysis for Flutter apps.
///
/// Most people use fluttr_scope from the command line
/// (`dart run fluttr_scope analyze`). This library is for building on top
/// of it: running the static rules from your own tool, writing a rule of
/// your own, or rendering findings in another format.
library;

export 'src/baseline/baseline.dart' show Baseline, defaultBaselineFileName;
export 'src/config/project_config.dart'
    show ConfigException, ProjectConfig, configFileName, nonDartRuleIds;
export 'src/coverage/file_coverage.dart';
export 'src/coverage/lcov_parser.dart' show parseLcov;
export 'src/dependency/dependency_audit.dart' show auditDependencies;
export 'src/model/category.dart';
export 'src/model/finding.dart';
export 'src/model/severity.dart';
export 'src/model/source_location.dart';
export 'src/report/json_report.dart' show toJsonReport;
export 'src/report/sarif_report.dart' show toSarifReport;
export 'src/security/manifest_scanner.dart' show scanManifests;
export 'src/static/all_rules.dart' show allRules;
export 'src/static/engine.dart' show AnalysisEngine;
export 'src/static/rule.dart' show RuleContext, StaticRule, locationAt, locationOf;
export 'src/static/suppression.dart' show Suppressions, ignorePrefix;
export 'src/version.dart' show packageVersion;
