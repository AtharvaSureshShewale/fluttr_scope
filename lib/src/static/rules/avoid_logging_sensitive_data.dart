import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

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
/// Scope: flags a logged *String* value (interpolated, concatenated, or
/// passed directly) whose name looks like a secret — Dart has no way to
/// know a String's semantic meaning at analysis time, so the name is the
/// signal. Requiring a String keeps out names that merely mention a secret
/// (`authError`, `isPasswordValid`, `token.length`), and names that
/// describe one (`tokenPreview`, `passwordHash`) are excluded too.
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

  /// Whether [arg] logs a String value whose name looks secret: `$token`,
  /// `'x' + password`, `_passwordController.text`. Only String-typed values
  /// count -- `$authError` (an exception), `$isPasswordValid` (a bool), and
  /// `${token.length}` (an int) don't leak the secret itself.
  bool _looksSensitive(Expression arg) => _loggedValues(arg).any(
        (e) => _isString(e.staticType) && _isSensitiveName(_nameOf(e)),
      );

  /// The values [expr] renders into the log line.
  Iterable<Expression> _loggedValues(Expression expr) sync* {
    switch (expr.unParenthesized) {
      case StringInterpolation(:final elements):
        for (final e in elements) {
          if (e is InterpolationExpression) yield* _loggedValues(e.expression);
        }
      case BinaryExpression(operator: Token(lexeme: '+'), :final leftOperand, :final rightOperand):
        yield* _loggedValues(leftOperand);
        yield* _loggedValues(rightOperand);
      case StringLiteral():
        break;
      case final e:
        yield e;
    }
  }
}

/// Names that describe a secret without being one: a masked preview, a
/// hash, a length, an expiry.
final _metadataName = RegExp(
  r'(preview|mask|redact|hash|length|count|type|expir|status|valid|visible|obscure|enabled)',
  caseSensitive: false,
);

bool _isSensitiveName(String? name) =>
    name != null && sensitiveNamePattern.hasMatch(name) && !_metadataName.hasMatch(name);

bool _isString(DartType? type) => type != null && type.isDartCoreString;

/// The name a logged value is known by: `token` for `token` / `this.token` /
/// `auth.token`, and the controller's name for `_passwordController.text`.
String? _nameOf(Expression e) {
  final (String? target, String? property) = switch (e) {
    SimpleIdentifier(:final name) => (null, name),
    PrefixedIdentifier(:final prefix, :final identifier) => (prefix.name, identifier.name),
    PropertyAccess(:final target?, :final propertyName) => (_nameOf(target), propertyName.name),
    _ => (null, null),
  };
  if ((property == 'text' || property == 'value') && target != null) return target;
  return property;
}
