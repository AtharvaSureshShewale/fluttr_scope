import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `Image.network(...)` without `errorBuilder`. On a failed load
/// this shows Flutter's default broken-image icon instead of a
/// UI-appropriate fallback.
class ImageNetworkWithoutErrorBuilderRule extends StaticRule {
  @override
  String get id => 'image_network_without_error_builder';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.correctness,
        severity: Severity.info,
        message: '`Image.network` without `errorBuilder` shows a broken '
            'default icon on a failed load instead of a UI-aware '
            'fallback.',
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
    if (creationTypeName(node) == 'Image' &&
        node.constructorName.name?.name == 'network' &&
        !node.argumentList.arguments
            .any((a) => a is NamedExpression && a.name.label.name == 'errorBuilder')) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}
