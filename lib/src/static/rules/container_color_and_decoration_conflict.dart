import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `Container` with both `color` and `decoration` set — Flutter
/// asserts these are mutually exclusive and throws at runtime. Put the
/// color inside the `BoxDecoration` instead.
class ContainerColorAndDecorationConflictRule extends StaticRule {
  @override
  String get id => 'container_color_and_decoration_conflict';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      final names = node.argumentList.arguments
          .whereType<NamedExpression>()
          .map((a) => a.name.label.name)
          .toSet();
      if (names.contains('color') && names.contains('decoration')) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`Container` with both `color` and `decoration` set '
              'throws an assertion error at runtime — put the color '
              'inside the `BoxDecoration` instead.',
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
    if (creationTypeName(node) == 'Container') onMatch(node);
    super.visitInstanceCreationExpression(node);
  }
}
