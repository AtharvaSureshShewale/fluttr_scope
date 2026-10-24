import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

final _createTablePattern = RegExp(r'^\s*CREATE\s+TABLE', caseSensitive: false);
final _constraintKeywords = RegExp(
  r'PRIMARY\s+KEY|NOT\s+NULL|UNIQUE|CHECK\s*\(|FOREIGN\s+KEY|REFERENCES',
  caseSensitive: false,
);

/// Flags a `CREATE TABLE` statement with no constraints — no
/// `PRIMARY KEY`, `NOT NULL`, `UNIQUE`, `CHECK`, or `FOREIGN KEY`.
/// Without at least one of these, the database itself enforces nothing:
/// duplicate rows, missing required fields, and invalid foreign
/// references are all accepted silently. Whatever validation exists is
/// entirely up to whichever Dart code happens to call `insert`, which is
/// easy to bypass by simply calling `insert` from somewhere else later.
///
/// Matched on the string literal's content, not gated to any particular
/// method call — a `CREATE TABLE` string is unambiguous wherever it
/// appears, including when it's defined as a separate constant and
/// passed to `execute()` elsewhere.
class SqlTableMissingConstraintsRule extends StaticRule {
  @override
  String get id => 'sql_table_missing_constraints';

  @override
  Category get category => Category.security;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.warning,
        message: 'This `CREATE TABLE` statement has no constraints (no '
            'PRIMARY KEY, NOT NULL, UNIQUE, CHECK, or FOREIGN KEY). '
            'Without them, the database accepts any row — duplicates, '
            'missing required fields, invalid references — with no '
            'validation at the storage layer.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(SimpleStringLiteral node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (_createTablePattern.hasMatch(value) && !_constraintKeywords.hasMatch(value)) {
      onMatch(node);
    }
    super.visitSimpleStringLiteral(node);
  }
}
