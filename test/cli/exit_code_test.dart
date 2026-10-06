import 'package:fluttr_scope/src/cli/analyze_command.dart';
import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:test/test.dart';

Finding _f(Severity s) => Finding(
      ruleId: 'r',
      category: Category.style,
      severity: s,
      message: 'm',
      location: const SourceLocation(file: 'f', line: 1, column: 1, length: 1),
    );

void main() {
  int code(List<Finding> f, {bool warnings = true, bool infos = false}) =>
      exitCodeFor(f, fatalWarnings: warnings, fatalInfos: infos);

  test('no findings is 0', () => expect(code([]), 0));
  test('errors always fail', () => expect(code([_f(Severity.error)], warnings: false), 1));
  test('warnings fail by default', () => expect(code([_f(Severity.warning)]), 1));
  test('--no-fatal-warnings lets warnings pass',
      () => expect(code([_f(Severity.warning)], warnings: false), 0));
  test('infos pass by default', () => expect(code([_f(Severity.info)]), 0));
  test('--fatal-infos fails on infos', () => expect(code([_f(Severity.info)], infos: true), 1));
}
