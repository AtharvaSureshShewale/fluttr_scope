import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Viewport-based scrollables, with the axis each scrolls along when no
/// `scrollDirection:` is given. `SingleChildScrollView` is deliberately
/// absent: it sizes itself to its child under unbounded constraints and
/// never throws.
const _defaultScrollAxis = {
  'ListView': _Axis.vertical,
  'GridView': _Axis.vertical,
  'CustomScrollView': _Axis.vertical,
  'PageView': _Axis.horizontal,
};

/// The axis along which each flex gives its non-flex children unbounded
/// space.
const _unboundedAxisOfFlex = {
  'Column': _Axis.vertical,
  'Row': _Axis.horizontal,
};

enum _Axis { vertical, horizontal }

/// Flags a viewport-based scrollable (`ListView`, `GridView`,
/// `CustomScrollView`, `PageView`) placed in a `Column`/`Row` where it is
/// guaranteed to throw. A `Column`/`Row` gives non-flex children unbounded
/// space along its main axis, and the framework's viewports assert:
///
/// - a normal viewport needs *both* axes bounded, so it throws in a
///   `Column`/`Row` whichever way it scrolls;
/// - a `shrinkWrap: true` viewport only needs its *cross* axis bounded, so
///   it throws only when it scrolls across the flex (a horizontal list in
///   a `Column`).
///
/// Only flagged when that's certain: the parent is visible (see
/// [visibleParentWidget]) and `shrinkWrap:`/`scrollDirection:` are absent
/// or literal. A value computed at runtime is not guessed at.
class UnboundedScrollableInFlexRule extends StaticRule {
  @override
  String get id => 'unbounded_scrollable_in_flex';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node, flexName, scrollAxis, unboundedAxis) {
      final scrollable = creationTypeName(node);
      final orientation = scrollAxis == _Axis.vertical ? 'Vertical' : 'Horizontal';
      final dimension = unboundedAxis == _Axis.vertical ? 'height' : 'width';
      final fix = scrollAxis == unboundedAxis
          ? 'Wrap it in `Expanded`/`Flexible`, or set `shrinkWrap: true` for a short list.'
          : 'Give it a bounded $dimension, e.g. wrap it in `SizedBox($dimension: ...)`.';
      findings.add(Finding(
        ruleId: id,
        category: Category.correctness,
        severity: Severity.error,
        message: '`$scrollable` directly inside a `$flexName` throws '
            '"$orientation viewport was given unbounded $dimension" at runtime. $fix',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(
    InstanceCreationExpression node,
    String flexName,
    _Axis scrollAxis,
    _Axis unboundedAxis,
  ) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  void _check(InstanceCreationExpression node) {
    final defaultAxis = _defaultScrollAxis[creationTypeName(node)];
    if (defaultAxis == null || !isFrameworkWidget(node)) return;

    final parent = visibleParentWidget(node);
    if (parent == null || !isFrameworkWidget(parent)) return;
    final flexName = creationTypeName(parent);
    final unboundedAxis = _unboundedAxisOfFlex[flexName];
    if (unboundedAxis == null) return;

    final scrollAxis = _literalAxis(_argument(node, 'scrollDirection'), defaultAxis);
    final shrinkWrap = _literalBool(_argument(node, 'shrinkWrap'), false);
    if (scrollAxis == null || shrinkWrap == null) return; // computed at runtime

    final throws = !shrinkWrap || scrollAxis != unboundedAxis;
    if (throws) onMatch(node, flexName, scrollAxis, unboundedAxis);
  }
}

Expression? _argument(InstanceCreationExpression node, String name) {
  for (final arg in node.argumentList.arguments) {
    if (arg is NamedExpression && arg.name.label.name == name) return arg.expression;
  }
  return null;
}

/// [fallback] if [expr] is absent, the axis if it's a literal
/// `Axis.vertical`/`Axis.horizontal`, `null` if it's anything else.
_Axis? _literalAxis(Expression? expr, _Axis fallback) {
  if (expr == null) return fallback;
  final source = expr.toSource();
  if (source == 'Axis.vertical') return _Axis.vertical;
  if (source == 'Axis.horizontal') return _Axis.horizontal;
  return null;
}

bool? _literalBool(Expression? expr, bool fallback) {
  if (expr == null) return fallback;
  return expr is BooleanLiteral ? expr.value : null;
}
