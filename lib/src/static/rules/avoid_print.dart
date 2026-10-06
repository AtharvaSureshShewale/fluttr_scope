import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

/// Flags bare calls to `print(...)`, which are easy to leave in by accident
/// and produce no useful output in a release build.
class AvoidPrintRule extends StaticRule {
  @override
  String get id => 'avoid_print';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.style,
        severity: Severity.warning,
        message: 'Avoid `print` calls; use a logger instead.',
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
    if (node.target == null && node.methodName.name == 'print') {
      onMatch(node);
    }
    super.visitMethodInvocation(node);
  }
}
