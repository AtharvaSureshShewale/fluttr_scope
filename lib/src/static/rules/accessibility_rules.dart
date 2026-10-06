import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

bool _hasNamedArg(InstanceCreationExpression node, String name) => node.argumentList.arguments
    .any((a) => a is NamedExpression && a.name.label.name == name);

/// Flags `IconButton` without a `tooltip`. A screen reader has nothing to
/// announce for an icon-only button otherwise.
class MissingTooltipForIconButtonRule extends StaticRule {
  @override
  String get id => 'missing_tooltip_for_iconbutton';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_TypeVisitor('IconButton', (node) {
      if (!_hasNamedArg(node, 'tooltip')) {
        findings.add(Finding(
          ruleId: id,
          category: Category.accessibility,
          severity: Severity.warning,
          message: '`IconButton` without a `tooltip` has no accessible '
              'label for screen readers.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags `Image.network`/`.asset`/`.file`/`.memory` without a
/// `semanticLabel`. A screen reader has nothing to describe the image
/// with otherwise.
class ImageMissingSemanticLabelRule extends StaticRule {
  static const _namedConstructors = {'network', 'asset', 'file', 'memory'};

  @override
  String get id => 'image_missing_semantic_label';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      if (creationTypeName(node) == 'Image' &&
          _namedConstructors.contains(node.constructorName.name?.name) &&
          !_hasNamedArg(node, 'semanticLabel')) {
        findings.add(Finding(
          ruleId: id,
          category: Category.accessibility,
          severity: Severity.info,
          message: '`Image` without `semanticLabel` has no accessible '
              'description for screen readers.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

class _TypeVisitor extends RecursiveAstVisitor<void> {
  final String typeName;
  final void Function(InstanceCreationExpression node) onMatch;

  _TypeVisitor(this.typeName, this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (creationTypeName(node) == typeName) onMatch(node);
    super.visitInstanceCreationExpression(node);
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(InstanceCreationExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    onMatch(node);
    super.visitInstanceCreationExpression(node);
  }
}
