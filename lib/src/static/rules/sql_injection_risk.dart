import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

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
  Category get category => Category.security;

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

  /// Whether [expr] splices in a value that could carry user input. A
  /// query interpolating only schema names (`'DELETE FROM $_usersTable'`),
  /// constants, or numbers can't be injected into, and flagging those was
  /// nearly all of this rule's hits on a real app with a large database
  /// layer. A plain literal or a lone variable isn't "built" here at all.
  bool _isDynamicallyBuilt(Expression expr) => switch (expr.unParenthesized) {
        StringInterpolation() || BinaryExpression() => _containsUnsafePart(expr),
        _ => false,
      };
}

/// Whether any piece spliced into [expr] could carry user input.
bool _containsUnsafePart(Expression expr) => switch (expr.unParenthesized) {
      SimpleStringLiteral() => false,
      StringInterpolation(:final elements) => elements
          .whereType<InterpolationExpression>()
          .any((e) => _containsUnsafePart(e.expression)),
      BinaryExpression(operator: Token(lexeme: '+'), :final leftOperand, :final rightOperand) =>
        _containsUnsafePart(leftOperand) || _containsUnsafePart(rightOperand),
      final value => !_isSafeValue(value),
    };

/// Names a schema identifier is given: `usersTable`, `_tableName`,
/// `columnLocalID`, `idColumn`.
final _schemaName = RegExp(r'^_*(table|column|col|tbl)|(table|column|col|tbl|fields?)s?$', caseSensitive: false);

/// Names for a run of `?` placeholders -- `IN ($placeholders)` is how a
/// parameterized IN-list is written, the opposite of an injection.
final _placeholderName = RegExp(r'placeholders?$', caseSensitive: false);

/// `List.filled(n, '?').join(...)`: building `?, ?, ?` for an IN-list.
bool _isPlaceholderList(Expression e) => switch (e) {
      MethodInvocation(
        methodName: SimpleIdentifier(name: 'join'),
        target: MethodInvocation(
          methodName: SimpleIdentifier(name: 'filled'),
          argumentList: ArgumentList(:final arguments),
        ) ||
            InstanceCreationExpression(argumentList: ArgumentList(:final arguments)),
      ) =>
        arguments.length >= 2 &&
            arguments[1] is SimpleStringLiteral &&
            (arguments[1] as SimpleStringLiteral).value.trim() == '?',
      _ => false,
    };

/// A value that can't carry an injection: a number or boolean (no quotes
/// to break out of), a `const`, or a schema name.
bool _isSafeValue(Expression e) {
  if (_isPlaceholderList(e.unParenthesized)) return true;
  final type = e.staticType;
  if (type != null && (type.isDartCoreInt || type.isDartCoreDouble || type.isDartCoreNum || type.isDartCoreBool)) {
    return true;
  }
  final (Element? element, String? name) = switch (e.unParenthesized) {
    Identifier(:final element, :final name) => (element, name.split('.').last),
    PropertyAccess(:final propertyName) => (propertyName.element, propertyName.name),
    _ => (null, null),
  };
  if (name == null) return false;
  final isConst = switch (element) {
    PropertyAccessorElement(:final variable) => variable.isConst,
    VariableElement(:final isConst) => isConst,
    _ => false,
  };
  return isConst || _schemaName.hasMatch(name) || _placeholderName.hasMatch(name);
}
