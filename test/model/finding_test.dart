import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:test/test.dart';

const _location = SourceLocation(file: 'lib/main.dart', line: 1, column: 1, length: 1);

void main() {
  test('toJson omits widgetPath and fix when absent, but always includes evidence', () {
    final finding = Finding(
      ruleId: 'x',
      category: Category.correctness,
      severity: Severity.error,
      message: 'm',
      location: _location,
    );

    final json = finding.toJson();
    expect(json.containsKey('widgetPath'), isFalse);
    expect(json.containsKey('fix'), isFalse);
    expect(json['evidence'], isEmpty);
    expect(json['ruleId'], 'x');
    expect(json['category'], 'correctness');
    expect(json['severity'], 'error');
  });

  test('toJson includes widgetPath and fix when present', () {
    final finding = Finding(
      ruleId: 'x',
      category: Category.correctness,
      severity: Severity.error,
      message: 'm',
      location: _location,
      widgetPath: 'App>Home',
      fix: const Fix(kind: 'add_const', description: 'Add const'),
    );

    final json = finding.toJson();
    expect(json['widgetPath'], 'App>Home');
    expect(json['fix'], {'kind': 'add_const', 'description': 'Add const'});
  });
}
