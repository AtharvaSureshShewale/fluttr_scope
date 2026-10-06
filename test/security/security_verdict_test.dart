import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/security/security_verdict.dart';
import 'package:test/test.dart';

const _location = SourceLocation(file: 'lib/main.dart', line: 1, column: 1, length: 1);

Finding _finding(Severity severity) => Finding(
      ruleId: 'x',
      category: Category.security,
      severity: severity,
      message: 'm',
      location: _location,
    );

void main() {
  test('no findings is SECURE with all counts zero', () {
    final summary = summarizeSecurity(const []);
    expect(summary.verdict, SecurityVerdict.secure);
    expect(summary.totalCount, 0);
  });

  test('any error-severity finding makes the verdict critical, regardless of other findings', () {
    final summary = summarizeSecurity([
      _finding(Severity.info),
      _finding(Severity.warning),
      _finding(Severity.error),
    ]);
    expect(summary.verdict, SecurityVerdict.critical);
    expect(summary.criticalCount, 1);
    expect(summary.warningCount, 1);
    expect(summary.infoCount, 1);
  });

  test('only warning/info findings is needsAttention, not critical', () {
    final summary = summarizeSecurity([
      _finding(Severity.warning),
      _finding(Severity.info),
    ]);
    expect(summary.verdict, SecurityVerdict.needsAttention);
    expect(summary.criticalCount, 0);
  });

  test('a single info-only finding still triggers needsAttention, not secure', () {
    final summary = summarizeSecurity([_finding(Severity.info)]);
    expect(summary.verdict, SecurityVerdict.needsAttention);
  });
}
