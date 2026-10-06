import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `Expanded`/`Flexible` used somewhere other than directly inside a
/// `Column`/`Row`/`Flex`'s `children:` list. Flutter throws `Incorrect use
/// of ParentDataWidget` at runtime otherwise.
///
/// Scope: only flags when the wrong parent is visible at the construction
/// site (see [_RequiredParentVisitor]). An `Expanded` returned from a
/// helper or a `.map(...)` closure is never flagged, right or wrong,
/// since its real parent isn't knowable from there.
class ExpandedOutsideFlexRule extends StaticRule {
  @override
  String get id => 'expanded_outside_flex';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_RequiredParentVisitor(
      targetTypes: const {'Expanded', 'Flexible'},
      requiredParents: const {'Column', 'Row', 'Flex'},
      onMatch: (node) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`${creationTypeName(node)}` must be a '
              'direct child of a `Column`/`Row`/`Flex`; used elsewhere it '
              'throws `Incorrect use of ParentDataWidget` at runtime.',
          location: locationOf(unit, node, context),
        ));
      },
    ));
    return findings;
  }
}

/// Flags `Positioned` used somewhere other than directly inside a
/// `Stack`'s `children:` list — the same failure mode as
/// [ExpandedOutsideFlexRule] but for `Stack`.
class PositionedOutsideStackRule extends StaticRule {
  @override
  String get id => 'positioned_outside_stack';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_RequiredParentVisitor(
      targetTypes: const {'Positioned'},
      requiredParents: const {'Stack'},
      onMatch: (node) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`Positioned` must be a direct child of a `Stack`; used '
              'elsewhere it throws `Incorrect use of ParentDataWidget` at '
              'runtime.',
          location: locationOf(unit, node, context),
        ));
      },
    ));
    return findings;
  }
}

/// Flags a [targetTypes] widget only when the widget it's handed to is
/// *visible* in the source (see [visibleParentWidget]) and is provably the
/// wrong parent: a Flutter framework widget that isn't (a subtype of) one
/// of [requiredParents].
///
/// Anything whose parent isn't visible -- returned from a helper or a
/// closure (`.map((t) => Expanded(...))`, `List.generate`), stored in a
/// variable -- is not flagged: the caller may well put it in the right
/// place, and guessing "wrong" there produced dozens of false errors per
/// real app. Custom (non-framework) parents are not flagged either: a user
/// widget's `children:` may well be forwarded straight into a `Row`.
class _RequiredParentVisitor extends RecursiveAstVisitor<void> {
  final Set<String> targetTypes;
  final Set<String> requiredParents;
  final void Function(InstanceCreationExpression node) onMatch;

  _RequiredParentVisitor({
    required this.targetTypes,
    required this.requiredParents,
    required this.onMatch,
  });

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (targetTypes.contains(creationTypeName(node))) {
      final parent = visibleParentWidget(node);
      if (parent != null && isFrameworkWidget(parent) && !_isRequiredParent(parent)) {
        onMatch(node);
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  bool _isRequiredParent(InstanceCreationExpression creation) {
    final type = creation.staticType;
    if (type is! InterfaceType) return requiredParents.contains(creationTypeName(creation));
    return requiredParents.contains(type.element3.name3) ||
        type.allSupertypes.any((t) => requiredParents.contains(t.element3.name3));
  }
}
