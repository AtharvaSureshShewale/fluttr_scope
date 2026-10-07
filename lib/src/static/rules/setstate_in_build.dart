import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `setState(...)` called directly inside a `build()` method body —
/// not inside a nested callback like `onPressed: () => setState(...)`,
/// which is the normal, safe pattern.
///
/// It doesn't crash: the framework keeps an element dirty until its
/// `build()` returns precisely so that a rebuild requested *during* its own
/// build is ignored (see `ComponentElement.performRebuild`). The closure
/// still runs, so the call is a no-op wrapper around an assignment -- found
/// in a shipping showcase app, where it works fine. (The real "called during
/// build" crash comes from rebuilding a *different* widget, which this
/// syntactic rule can't see.)
class SetStateInBuildRule extends StaticRule {
  @override
  String get id => 'setstate_in_build';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(BuildMethodVisitor((buildMethod) {
      buildMethod.body.accept(_DirectSetStateVisitor(buildMethod.body, (node) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.info,
          message: '`setState()` inside the same widget\'s own `build()` does nothing: '
              'Flutter ignores rebuild requests while the widget is building. '
              'Assign the field directly, or move the work to `initState` or an '
              'event handler.',
          location: locationOf(unit, node, context),
        ));
      }));
    }));
    return findings;
  }
}

/// Finds `setState(...)` calls whose nearest enclosing function literal
/// (if any) is still [root] itself — i.e. not inside a nested closure.
class _DirectSetStateVisitor extends RecursiveAstVisitor<void> {
  final AstNode root;
  final void Function(MethodInvocation node) onMatch;

  _DirectSetStateVisitor(this.root, this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState' &&
        (node.target == null || node.target is ThisExpression) &&
        !isInsideNestedClosure(node, root)) {
      onMatch(node);
    }
    super.visitMethodInvocation(node);
  }
}
