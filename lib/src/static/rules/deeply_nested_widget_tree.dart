import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags a `build()` method whose widget tree nests more than
/// [_threshold] `InstanceCreationExpression`s deep — a maintainability
/// smell, and a sign the tree should be broken into sub-widgets.
class DeeplyNestedWidgetTreeRule extends StaticRule {
  static const _threshold = 8;

  @override
  String get id => 'deeply_nested_widget_tree';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(BuildMethodVisitor((buildMethod) {
      var maxDepth = 0;
      buildMethod.body.accept(_DepthVisitor(buildMethod.body, (depth) {
        if (depth > maxDepth) maxDepth = depth;
      }));
      if (maxDepth > _threshold) {
        findings.add(Finding(
          ruleId: id,
          category: Category.style,
          severity: Severity.info,
          message: 'This `build()` nests widgets $maxDepth levels deep '
              '(over $_threshold). Consider extracting sub-trees into '
              'their own widgets for readability.',
          location: locationOfToken(unit, buildMethod.name, context, end: buildMethod.end),
        ));
      }
    }));
    return findings;
  }
}

class _DepthVisitor extends RecursiveAstVisitor<void> {
  final AstNode root;
  final void Function(int depth) onNode;

  _DepthVisitor(this.root, this.onNode);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    var depth = 0;
    for (var current = node.parent;
        current != null && current != root;
        current = current.parent) {
      if (current is InstanceCreationExpression) depth++;
    }
    onNode(depth);
    super.visitInstanceCreationExpression(node);
  }
}
