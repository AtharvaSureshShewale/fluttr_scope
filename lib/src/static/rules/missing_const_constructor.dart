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
        fix: _isInsideFlagged(node) ? null : _addConst(node),
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

/// `const` before the call (or in place of `new`).
Fix _addConst(InstanceCreationExpression node) {
  final keyword = node.keyword;
  return Fix(
    kind: 'add_const',
    description: 'Add `const`',
    edits: [
      if (keyword != null)
        SourceEdit(offset: keyword.offset, length: keyword.length, replacement: 'const')
      else
        SourceEdit(offset: node.offset, length: 0, replacement: 'const '),
    ],
  );
}

/// Whether [node] is an argument of a call this rule flags too. Its fix
/// makes [node] const already (an argument of a `const` call is
/// implicitly const), so a second `const` would only be redundant.
bool _isInsideFlagged(InstanceCreationExpression node) {
  for (AstNode? n = node.parent; n != null; n = n.parent) {
    if (n is InstanceCreationExpression) {
      return !n.isConst && _isFlutterWidgetType(n.staticType) && _isConstCapable(n);
    }
    if (n is! ArgumentList && n is! NamedExpression) return false;
  }
  return false;
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
  // `const Box<T>()` doesn't compile when T is a type parameter, whether
  // written or inferred.
  final type = node.staticType;
  if (type is InterfaceType && type.typeArguments.any(_mentionsTypeParameter)) return false;
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
  if (expr is ListLiteral || expr is SetOrMapLiteral || expr is RecordLiteral) return false;
  return expr is Literal;
}

bool _mentionsTypeParameter(DartType type) => switch (type) {
      TypeParameterType() => true,
      InterfaceType(:final typeArguments) => typeArguments.any(_mentionsTypeParameter),
      FunctionType() => true, // its parameter types may mention one; stay safe
      RecordType(:final positionalFields, :final namedFields) =>
        positionalFields.any((f) => _mentionsTypeParameter(f.type)) ||
            namedFields.any((f) => _mentionsTypeParameter(f.type)),
      _ => false,
    };
