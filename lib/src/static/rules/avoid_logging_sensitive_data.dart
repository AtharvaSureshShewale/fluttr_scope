import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';
import '../sensitive_names.dart';

/// Flags `print`/`debugPrint` calls that reference a sensitive-named
/// value. Logs are routinely persisted (device logs, crash reporters,
/// analytics) far longer and more widely than anyone intends — printing
/// a token or password is a real, common way secrets leak.
///
/// Scope: flags based on the *name* of any identifier referenced within
/// the logged expression, not its value — Dart has no way to know a
/// String's semantic meaning at analysis time. That means a variable
/// merely named like a secret (e.g. `passwordFieldIsEmpty`) can trigger
/// this even if it never holds the actual value; the alternative (only
/// matching exact known secret shapes, like `hardcoded_secret`) would
/// miss the much more common case of logging a runtime value.
class AvoidLoggingSensitiveDataRule extends StaticRule {
  @override
  String get id => 'avoid_logging_sensitive_data';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.warning,
        message: 'This looks like it logs a sensitive value. Logs are '
            'often persisted or shipped to crash/analytics tools — avoid '
            'printing secrets, tokens, or passwords.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

const _loggingFunctions = {'print', 'debugPrint'};

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(InvocationExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && _loggingFunctions.contains(node.methodName.name)) {
      _checkArguments(node);
    }
    super.visitMethodInvocation(node);
  }

  /// Flutter's `debugPrint` is a top-level *variable* of function type, so
  /// the resolved AST represents a call to it as a function-expression
  /// invocation, not the [MethodInvocation] a real function like `print`
  /// gets -- without this, `debugPrint(token)` was never checked.
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier && _loggingFunctions.contains(function.name)) {
      _checkArguments(node);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  void _checkArguments(InvocationExpression node) {
    if (node.argumentList.arguments.isNotEmpty &&
        _looksSensitive(node.argumentList.arguments.first)) {
      onMatch(node);
    }
  }

  bool _looksSensitive(Expression expr) {
    var found = false;
    expr.accept(_IdentifierNameVisitor(() => found = true));
    return found;
  }
}

class _IdentifierNameVisitor extends RecursiveAstVisitor<void> {
  final void Function() onSensitiveName;

  _IdentifierNameVisitor(this.onSensitiveName);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (sensitiveNamePattern.hasMatch(node.name)) onSensitiveName();
    super.visitSimpleIdentifier(node);
  }
}
