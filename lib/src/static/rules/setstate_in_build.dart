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
/// which is the normal, safe pattern. Calling it directly during build
/// throws `setState() or markNeedsBuild() called during build` at runtime.
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
          severity: Severity.error,
          message: '`setState()` called directly during `build()`; this '
              'throws at runtime. Move it into an event handler, '
              '`initState`, or a post-frame callback.',
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
