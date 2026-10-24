import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

/// Flags Flutter widget constructions that could be `const` but aren't.
///
/// This is the flagship rule the runtime correlator (a later milestone)
/// attaches rebuild evidence to, so its span must be exact and its
/// eligibility check must never produce a false positive — a widget it
/// flags that genuinely cannot be made `const` would undermine the whole
/// "missing const -> N rebuilds" demo. Scope is deliberately conservative:
/// only literal and recursively const-eligible constructor arguments are
/// accepted, so some legitimately const-able calls (e.g. those passing a
/// reference to a `const` field) are missed rather than risking a false
/// positive.
class MissingConstConstructorRule extends StaticRule {
  @override
  String get id => 'missing_const_constructor';

  @override
  Category get category => Category.performance;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.warning,
        message:
            'This widget could be `const`, which would let Flutter skip '
            'rebuilding it when its parent rebuilds.',
        location: locationOf(unit, node, context),
        evidenceLocations: rerunEvidence(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(InstanceCreationExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!node.isConst &&
        _isFlutterWidgetType(node.staticType) &&
        _isConstCapable(node)) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}

bool _isFlutterWidgetType(DartType? type) {
  if (type is! InterfaceType) return false;
  if (_isWidgetElement(type.element)) return true;
  return type.allSupertypes.any((t) => _isWidgetElement(t.element));
}

bool _isWidgetElement(InterfaceElement element) {
  return element.name == 'Widget' &&
      element.library.uri.toString().startsWith('package:flutter/');
}

/// Whether every argument in [node] is a literal or a nested constructor
/// call that is itself const-capable, recursively.
bool _isConstCapable(InstanceCreationExpression node) {
  final constructor = node.constructorName.element;
  if (constructor == null || !constructor.isConst) return false;
  return node.argumentList.arguments.every(_isPotentiallyConstArg);
}

bool _isPotentiallyConstArg(Expression expr) {
  if (expr is NamedExpression) return _isPotentiallyConstArg(expr.expression);
  if (expr is InstanceCreationExpression) return _isConstCapable(expr);
  if (expr is PrefixExpression) return _isPotentiallyConstArg(expr.operand);
  // A StringLiteral is only actually constant if it has no interpolated
  // non-const parts — `stringValue` is null for any string interpolation
  // (even a fully-const one, e.g. `'${1 + 1}'`), regardless of the fact
  // that StringInterpolation itself still satisfies `is Literal` below.
  if (expr is StringLiteral) return expr.stringValue != null;
  if (expr is ListLiteral || expr is SetOrMapLiteral) return false;
  return expr is Literal;
}
