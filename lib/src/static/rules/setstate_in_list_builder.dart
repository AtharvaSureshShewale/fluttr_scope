import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

const _builderCallbackParams = {'itemBuilder', 'separatorBuilder'};

/// Flags `setState(...)` called anywhere inside a list/grid's
/// `itemBuilder`/`separatorBuilder` callback -- directly, or nested inside
/// a tap handler within it (`ListView.builder(itemBuilder: (_, i) =>
/// GestureDetector(onTap: () => setState(...)))`, the shape this was
/// written after finding in practice via a runtime rebuild capture).
///
/// `setState()` rebuilds the entire enclosing `State`, which re-runs the
/// builder callback for every visible item, not just the one interacted
/// with -- tapping one item silently costs a full-list rebuild.
///
/// Scope and false-positive risk, stated plainly: whether this actually
/// matters depends on how many items there are and how expensive each one
/// is to build, which isn't visible from source alone. Plenty of
/// `setState` calls in a builder callback are genuinely fine (short lists,
/// cheap cells, or a change that legitimately needs the whole list to
/// react). This rule flags the *shape*, not a proven problem -- pair it
/// with a runtime `measure` capture (rebuild counts at this exact
/// location) before treating it as something to fix.
class SetstateInListBuilderRule extends StaticRule {
  @override
  String get id => 'setstate_in_list_builder';

  @override
  Category get category => Category.performance;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.info,
        message: '`setState()` inside a list/grid `itemBuilder` rebuilds '
            'the entire list, not just this item -- every visible item\'s '
            'builder re-runs on a single tap. If only this item\'s own '
            'appearance needs to change, scope the state to the item '
            'instead (e.g. a `ValueNotifier`/`ValueListenableBuilder` per '
            'item) so unrelated items don\'t rebuild too.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState' &&
        node.target == null &&
        _isInsideBuilderCallback(node)) {
      onMatch(node);
    }
    super.visitMethodInvocation(node);
  }

  /// Walks up from [node] looking for an enclosing `itemBuilder:`/
  /// `separatorBuilder:` argument -- at any nesting depth, since `setState`
  /// is typically inside a further nested tap-handler closure, not the
  /// builder closure directly. Stops at the nearest enclosing method/
  /// function declaration so this can't escape past the current `build()`.
  bool _isInsideBuilderCallback(MethodInvocation node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is MethodDeclaration || current is FunctionDeclaration) return false;
      if (current is NamedExpression &&
          _builderCallbackParams.contains(current.name.label.name) &&
          current.expression is FunctionExpression) {
        return true;
      }
    }
    return false;
  }
}
