import 'package:fluttr_scope/src/config/project_config.dart';
import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:test/test.dart';

const _known = {'avoid_print', 'todo_comment', 'hardcoded_secret'};

ProjectConfig _parse(String yaml) => ProjectConfig.parse(yaml, knownRuleIds: _known);

Finding _finding(String ruleId, {String file = 'lib/main.dart', Severity? severity}) => Finding(
      ruleId: ruleId,
      category: Category.style,
      severity: severity ?? Severity.warning,
      message: 'm',
      location: SourceLocation(file: file, line: 1, column: 1, length: 1),
    );

void main() {
  test('an empty file is the empty config', () {
    final config = _parse('');
    expect(config.disabledRules, isEmpty);
    expect(config.severityOverrides, isEmpty);
    expect(config.excludes, isEmpty);
  });

  test('rules: false disables, a severity name overrides, true is a no-op', () {
    final config = _parse('''
rules:
  todo_comment: false
  avoid_print: error
  hardcoded_secret: true
''');
    expect(config.disabledRules, {'todo_comment'});
    expect(config.severityOverrides, {'avoid_print': Severity.error});
    expect(config.warnings, isEmpty);
  });

  test('unknown rule ids and top-level keys are warnings, not errors', () {
    final config = _parse('''
typo_key: 1
rules:
  avoid_prnt: false
''');
    expect(config.warnings, hasLength(2));
    expect(config.disabledRules, isEmpty);
  });

  test('an invalid rule value is an error', () {
    expect(() => _parse('rules:\n  avoid_print: loud\n'), throwsA(isA<ConfigException>()));
  });

  test('exclude must be a list of strings', () {
    expect(() => _parse('exclude: lib/**\n'), throwsA(isA<ConfigException>()));
  });

  test('invalid YAML is an error', () {
    expect(() => _parse('rules: [\n'), throwsA(isA<ConfigException>()));
  });

  test('apply drops disabled rules and excluded files, and overrides severity', () {
    final config = _parse('''
exclude:
  - lib/generated/**
rules:
  todo_comment: false
  avoid_print: error
''');
    final result = config.apply([
      _finding('todo_comment'),
      _finding('avoid_print'),
      _finding('hardcoded_secret', file: 'lib/generated/keys.dart'),
      _finding('hardcoded_secret'),
    ]);
    expect(result.map((f) => f.ruleId), ['avoid_print', 'hardcoded_secret']);
    expect(result.first.severity, Severity.error);
  });
}
