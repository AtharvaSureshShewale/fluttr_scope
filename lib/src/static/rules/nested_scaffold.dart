import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags a `Scaffold` constructed inside another `Scaffold`'s subtree
/// within the same method — a common beginner mistake (nesting `Scaffold`
/// instead of just its body/content) that produces duplicate app bars,
/// broken back-button behavior, and confusing `Navigator` context.
///
/// Scope: only catches `Scaffold`s nested inline in the same build
/// method. A `Scaffold` returned from a separate widget's `build()` and
/// used as a child isn't visible in the same AST subtree, so that case
/// is missed rather than risking a false positive from cross-widget
/// inference this rule doesn't attempt.
class NestedScaffoldRule extends StaticRule {
  @override
  String get id => 'nested_scaffold';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.correctness,
        severity: Severity.warning,
        message: 'A `Scaffold` nested inside another `Scaffold` causes '
            'duplicate app bars and confusing `Navigator` behavior. Nest '
            'the body content, not another `Scaffold`.',
        location: locationOf(unit, node, context),
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
    if (_isScaffold(node) && _hasScaffoldAncestor(node)) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  bool _isScaffold(InstanceCreationExpression node) =>
      creationTypeName(node) == 'Scaffold' &&
      node.constructorName.name == null;

  bool _hasScaffoldAncestor(AstNode node) {
    for (var current = node.parent; current != null; current = current.parent) {
      if (current is InstanceCreationExpression && _isScaffold(current)) {
        return true;
      }
      if (current is MethodDeclaration) break;
    }
    return false;
  }
}
