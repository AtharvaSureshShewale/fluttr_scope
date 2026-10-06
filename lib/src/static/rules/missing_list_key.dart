import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

/// Flags widgets generated via `xs.map((item) => Widget(...)).toList()`
/// fed to a `children:` list without a `key:` on the generated widget.
/// Without one, Flutter may misattribute state to the wrong item when the
/// underlying list is reordered or changes length.
///
/// Scope: only the `.map(...).toList()` shape is recognized — a `for` loop
/// or `List.generate` used to build `children:` isn't checked.
class MissingListKeyRule extends StaticRule {
  @override
  String get id => 'missing_list_key';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.warning,
        message: 'A widget generated for `children:` has no `key:`. '
            'Without one, Flutter may misattribute state to the wrong '
            'item when the list changes.',
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
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'children') {
      final generated = _generatedWidget(node.expression);
      if (generated != null && !_hasKeyArg(generated)) {
        onMatch(generated);
      }
    }
    super.visitNamedExpression(node);
  }

  /// If [expr] is `xs.map((item) => Widget(...)).toList()`, returns the
  /// `Widget(...)` the closure returns.
  InstanceCreationExpression? _generatedWidget(Expression expr) {
    if (expr is! MethodInvocation || expr.methodName.name != 'toList') return null;
    final target = expr.target;
    if (target is! MethodInvocation || target.methodName.name != 'map') return null;

    final args = target.argumentList.arguments;
    if (args.isEmpty || args.first is! FunctionExpression) return null;
    final body = (args.first as FunctionExpression).body;

    final Expression? returned;
    if (body is ExpressionFunctionBody) {
      returned = body.expression;
    } else if (body is BlockFunctionBody &&
        body.block.statements.length == 1 &&
        body.block.statements.first is ReturnStatement) {
      returned = (body.block.statements.first as ReturnStatement).expression;
    } else {
      returned = null;
    }

    return returned is InstanceCreationExpression ? returned : null;
  }

  bool _hasKeyArg(InstanceCreationExpression node) => node.argumentList.arguments
      .any((a) => a is NamedExpression && a.name.label.name == 'key');
}
