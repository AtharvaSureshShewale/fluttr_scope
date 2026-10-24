import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

/// Flags `badCertificateCallback` set to a function that unconditionally
/// returns `true` — accepting any TLS certificate, including a forged
/// one. This completely disables certificate validation and opens the
/// connection to man-in-the-middle attacks; it's a common pattern for
/// working around a cert error during development that then ships.
///
/// Scope: only the two literal always-true shapes are matched —
/// `(cert, host, port) => true` and `{ return true; }` — a callback with
/// any actual logic (even flawed logic) isn't flagged, since this rule
/// specifically targets the "validation is switched off entirely" case,
/// not general callback-logic review.
class InsecureCertificateValidationRule extends StaticRule {
  @override
  String get id => 'insecure_certificate_validation';

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
        message: '`badCertificateCallback` unconditionally returns `true`, '
            'accepting any TLS certificate — including a forged one. This '
            'disables certificate validation entirely and enables '
            'man-in-the-middle attacks.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(AssignmentExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_targetsBadCertificateCallback(node.leftHandSide) &&
        _alwaysReturnsTrue(node.rightHandSide)) {
      onMatch(node);
    }
    super.visitAssignmentExpression(node);
  }

  /// `client.badCertificateCallback = ...` parses as `PrefixedIdentifier`
  /// when the target is a bare identifier (the common case — a local
  /// variable or parameter), and as `PropertyAccess` for anything more
  /// complex (`foo().badCertificateCallback`, `this.client...`). Both
  /// need checking — same gotcha as elsewhere in this rule set where a
  /// `<identifier>.<identifier>` write target is syntactic, not semantic.
  bool _targetsBadCertificateCallback(Expression lhs) {
    if (lhs is PrefixedIdentifier) return lhs.identifier.name == 'badCertificateCallback';
    if (lhs is PropertyAccess) return lhs.propertyName.name == 'badCertificateCallback';
    return false;
  }

  bool _alwaysReturnsTrue(Expression expr) {
    if (expr is! FunctionExpression) return false;
    final body = expr.body;
    if (body is ExpressionFunctionBody) return _isTrueLiteral(body.expression);
    if (body is BlockFunctionBody) {
      final statements = body.block.statements;
      return statements.length == 1 &&
          statements.first is ReturnStatement &&
          _isTrueLiteral((statements.first as ReturnStatement).expression);
    }
    return false;
  }

  bool _isTrueLiteral(Expression? expr) => expr is BooleanLiteral && expr.value;
}
