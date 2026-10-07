import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `Scaffold(...)` with no `body:` — it renders a blank screen,
/// which is usually incomplete code rather than intentional.
class ScaffoldMissingBodyRule extends StaticRule {
  @override
  String get id => 'scaffold_missing_body';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      final hasBody = node.argumentList.arguments
          .any((a) => a is NamedExpression && a.name.label.name == 'body');
      if (!hasBody) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.info,
          message: '`Scaffold` has no `body` — likely incomplete code; it '
              'renders a blank screen.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(InstanceCreationExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Flutter's own Scaffold only: UI libraries ship their own `Scaffold`
    // with different slots (e.g. `headers:`/`child:`), and matching the
    // name alone flagged every screen of an app built on one.
    if (creationTypeName(node) == 'Scaffold' &&
        node.constructorName.name == null &&
        isFrameworkWidget(node)) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}
