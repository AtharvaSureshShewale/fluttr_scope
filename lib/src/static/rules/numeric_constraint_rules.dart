import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Numeric value of a literal argument, including a negated one
/// (`-1.0`) — `null` if [expr] isn't a numeric literal at all (e.g. a
/// variable or computed expression, which this rule set doesn't attempt
/// to evaluate).
double? numericValue(Expression expr) {
  if (expr is IntegerLiteral) return expr.value?.toDouble();
  if (expr is DoubleLiteral) return expr.value;
  if (expr is PrefixExpression && expr.operator.lexeme == '-') {
    final inner = numericValue(expr.operand);
    return inner == null ? null : -inner;
  }
  return null;
}

Expression? namedArgValue(InstanceCreationExpression node, String name) {
  for (final arg in node.argumentList.arguments) {
    if (arg is NamedExpression && arg.name.label.name == name) return arg.expression;
  }
  return null;
}

/// Flags `Opacity(opacity: X)` where `X` is a literal outside `[0.0, 1.0]`
/// — Flutter asserts on this at runtime.
class OpacityOutOfRangeRule extends StaticRule {
  @override
  String get id => 'opacity_out_of_range';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_TypeVisitor('Opacity', (node) {
      final arg = namedArgValue(node, 'opacity');
      final value = arg == null ? null : numericValue(arg);
      if (value != null && (value < 0 || value > 1)) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`Opacity.opacity` must be between 0.0 and 1.0; $value '
              'throws an assertion error at runtime.',
          location: locationOf(unit, arg!, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags `AspectRatio(aspectRatio: X)` where `X` is a literal `<= 0` —
/// Flutter asserts on this at runtime.
class InvalidAspectRatioRule extends StaticRule {
  @override
  String get id => 'invalid_aspect_ratio';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_TypeVisitor('AspectRatio', (node) {
      final arg = namedArgValue(node, 'aspectRatio');
      final value = arg == null ? null : numericValue(arg);
      if (value != null && value <= 0) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`AspectRatio.aspectRatio` must be greater than 0; '
              '$value throws an assertion error at runtime.',
          location: locationOf(unit, arg!, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags `Expanded(flex: X)`/`Flexible(flex: X)` where `X` is a literal
/// `<= 0` — Flutter asserts on this at runtime.
class FlexValueNonPositiveRule extends StaticRule {
  @override
  String get id => 'flex_value_non_positive';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_MultiTypeVisitor({'Expanded', 'Flexible'}, (node) {
      final arg = namedArgValue(node, 'flex');
      final value = arg == null ? null : numericValue(arg);
      if (value != null && value <= 0) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`flex` must be greater than 0; $value throws an '
              'assertion error at runtime.',
          location: locationOf(unit, arg!, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags `Slider(min: X, max: Y)` where both are literals and `X >= Y` —
/// Flutter asserts `min < max` at runtime.
class SliderInvalidRangeRule extends StaticRule {
  @override
  String get id => 'slider_invalid_range';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_TypeVisitor('Slider', (node) {
      final minArg = namedArgValue(node, 'min');
      final maxArg = namedArgValue(node, 'max');
      final min = minArg == null ? null : numericValue(minArg);
      final max = maxArg == null ? null : numericValue(maxArg);
      if (min != null && max != null && min >= max) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`Slider.min` ($min) must be less than `Slider.max` '
              '($max); this throws an assertion error at runtime.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags `BottomNavigationBar(items: [...])` with fewer than 2 items —
/// Flutter asserts `items.length >= 2` at runtime.
class BottomNavigationBarTooFewItemsRule extends StaticRule {
  @override
  String get id => 'bottom_navigation_bar_too_few_items';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_TypeVisitor('BottomNavigationBar', (node) {
      final arg = namedArgValue(node, 'items');
      if (arg is ListLiteral && arg.elements.length < 2) {
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`BottomNavigationBar` requires at least 2 `items`; '
              '${arg.elements.length} throws an assertion error at '
              'runtime.',
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

class _MultiTypeVisitor extends RecursiveAstVisitor<void> {
  final Set<String> typeNames;
  final void Function(InstanceCreationExpression node) onMatch;

  _MultiTypeVisitor(this.typeNames, this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (typeNames.contains(creationTypeName(node))) onMatch(node);
    super.visitInstanceCreationExpression(node);
  }
}
