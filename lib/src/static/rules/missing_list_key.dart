import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags widgets generated via `xs.map((item) => Widget(...)).toList()`
/// fed to a `children:` list without a `key:` on the generated widget.
/// Without one, Flutter may misattribute state to the wrong item when the
/// underlying list is reordered or changes length.
///
/// Scope: only the `.map(...).toList()` shape is recognized — a `for` loop
/// or `List.generate` used to build `children:` isn't checked — and only
/// items that hold state (see [_Visitor._holdsState]) are flagged.
class MissingListKeyRule extends StaticRule {
  @override
  String get id => 'missing_list_key';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.correctness,
        severity: Severity.warning,
        message: 'This generated item holds state (e.g. typed text or an '
            'expanded tile) but has no `key:`. When the list is reordered or '
            'an item is removed, that state can stay with the wrong item.',
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
      if (generated != null && !_hasKeyArg(generated) && _holdsState(generated)) {
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

  /// Whether [item]'s subtree creates a widget whose state can end up on
  /// the wrong item after a reorder: an app-defined `StatefulWidget` (its
  /// state is unknowable), or a framework widget that keeps user input or
  /// UI state (`TextField`, form fields, `ExpansionTile`). Stateless items,
  /// and framework widgets that rebuild from their configuration, don't
  /// need a key -- flagging them was most of this rule's real-world noise.
  bool _holdsState(InstanceCreationExpression item) {
    var found = false;
    item.accept(_StatefulCreationFinder(() => found = true));
    return found;
  }
}

const _statefulFrameworkWidgets = {'EditableText', 'TextField', 'FormField', 'ExpansionTile'};

class _StatefulCreationFinder extends RecursiveAstVisitor<void> {
  final void Function() onFound;

  _StatefulCreationFinder(this.onFound);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    if (type is InterfaceType) {
      final names = {type.element.name, for (final t in type.allSupertypes) t.element.name};
      final isStateful = names.contains('StatefulWidget');
      if (isStateful &&
          (!isFrameworkWidget(node) || names.any(_statefulFrameworkWidgets.contains))) {
        onFound();
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}
