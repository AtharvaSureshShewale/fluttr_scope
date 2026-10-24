import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

const _scrollableTypes = {'ListView', 'GridView', 'CustomScrollView'};

/// Flags `shrinkWrap: true` on a scrolling widget. It forces the widget to
/// lay out and measure every child eagerly instead of lazily, defeating
/// the point of a lazy-building list for anything but a short, known-size
/// child count.
class ShrinkwrapListviewRule extends StaticRule {
  @override
  String get id => 'shrinkwrap_listview';

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
        message: '`shrinkWrap: true` forces this list to lay out all of '
            'its children eagerly instead of lazily. Fine for a short, '
            'fixed-size list; a performance smell for anything larger.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(NamedExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_scrollableTypes.contains(creationTypeName(node))) {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression &&
            arg.name.label.name == 'shrinkWrap' &&
            arg.expression is BooleanLiteral &&
            (arg.expression as BooleanLiteral).value) {
          onMatch(arg);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}
