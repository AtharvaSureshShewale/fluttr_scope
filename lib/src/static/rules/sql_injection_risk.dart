import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

const _rawSqlMethods = {'rawQuery', 'rawInsert', 'rawUpdate', 'rawDelete', 'execute'};

/// Flags a `sqflite`-style raw SQL call (`rawQuery`/`rawInsert`/
/// `rawUpdate`/`rawDelete`/`execute`) whose query string is built via
/// string interpolation or `+` concatenation instead of parameterized
/// `?` placeholders — classic SQL injection shape if any part of the
/// interpolated/concatenated value ever comes from user input.
///
/// Matched by method name only, not by resolving the receiver's type to
/// `Database` — the method names are distinctive enough in practice that
/// this is a reasonable tradeoff for not requiring the `sqflite`
/// dependency to be resolvable.
class SqlInjectionRiskRule extends StaticRule {
  @override
  String get id => 'sql_injection_risk';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.error,
        message: 'This SQL query is built via string interpolation/'
            'concatenation instead of parameterized `?` placeholders, '
            'which risks SQL injection if any part comes from user input.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(Expression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_rawSqlMethods.contains(node.methodName.name) &&
        node.argumentList.arguments.isNotEmpty) {
      final query = node.argumentList.arguments.first;
      if (_isDynamicallyBuilt(query)) onMatch(query);
    }
    super.visitMethodInvocation(node);
  }

  bool _isDynamicallyBuilt(Expression expr) {
    if (expr is StringInterpolation) return true;
    if (expr is BinaryExpression && expr.operator.lexeme == '+') return true;
    return false;
  }
}
