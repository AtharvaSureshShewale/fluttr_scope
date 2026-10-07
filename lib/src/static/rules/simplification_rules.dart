import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags an empty `Container()` used purely for spacing. `SizedBox` has
/// far less overhead (`Container` resolves decoration, padding, margin,
/// and alignment even when none are set) and is the idiomatic choice when
/// none of that is needed.
class EmptyContainerInsteadOfSizedboxRule extends StaticRule {
  @override
  String get id => 'empty_container_instead_of_sizedbox';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor('Container', (node) {
      if (node.argumentList.arguments.isEmpty) {
        findings.add(Finding(
          ruleId: id,
          category: Category.performance,
          severity: Severity.info,
          message: 'An empty `Container()` has more overhead than '
              '`SizedBox()` for pure spacing.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags a `Column`/`Row` with exactly one plain child and nothing else
/// configured — usually leftover structure that `Align` (or the child
/// itself) expresses more directly and cheaply.
///
/// A single-child flex can still do real layout work, so these are left
/// alone: any argument besides `key`/`children` (alignment, sizing,
/// direction), a `Flexible`/`Expanded`/`Spacer` child (bounded by the
/// flex), and `if`/`for`/spread elements (which may produce zero or many
/// children).
class UnnecessaryColumnOrRowRule extends StaticRule {
  @override
  String get id => 'unnecessary_column_or_row';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_ChildrenCountVisitor({'Column', 'Row'}, (node, count) {
      if (count == 1 && _isPlainSingleChild(node)) {
        findings.add(Finding(
          ruleId: id,
          category: Category.style,
          severity: Severity.info,
          message: '`${creationTypeName(node)}` has a single child and no '
              'alignment or sizing set. If it only positions the child, '
              '`Align` (or the child directly) is simpler.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

const _flexChildTypes = {'Flexible', 'Expanded', 'Spacer'};

bool _isPlainSingleChild(InstanceCreationExpression flex) {
  Expression? child;
  for (final arg in flex.argumentList.arguments) {
    if (arg is! NamedExpression) return false;
    final name = arg.name.label.name;
    if (name == 'key') continue;
    if (name != 'children') return false;
    final element = (arg.expression as ListLiteral).elements.single;
    if (element is! Expression) return false; // if / for / spread
    child = element;
  }
  final type = child?.staticType;
  if (type is! InterfaceType) return true;
  final names = {type.element.name, for (final t in type.allSupertypes) t.element.name};
  return !names.any(_flexChildTypes.contains);
}

/// Flags `Column`/`Row` with an empty `children:` list — most likely
/// leftover placeholder code, since it renders nothing.
class EmptyFlexChildrenRule extends StaticRule {
  @override
  String get id => 'empty_flex_children';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_ChildrenCountVisitor({'Column', 'Row'}, (node, count) {
      if (count == 0) {
        findings.add(Finding(
          ruleId: id,
          category: Category.style,
          severity: Severity.info,
          message: '`${creationTypeName(node)}` has no children, so it '
              'renders nothing. If that is intended, `SizedBox.shrink()` says so '
              'more directly; otherwise it may be leftover placeholder code.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags an instance method or getter on a widget or `State` class that
/// returns `Widget` but isn't the `build` override. Unlike a real widget
/// class, it doesn't get its own `Element`, so Flutter can't skip
/// rebuilding it independently of its caller — a common source of
/// larger-than-necessary rebuild scopes. Static helpers and methods on
/// non-widget classes (factories, utility classes) aren't part of any
/// widget's rebuild, so they're out of scope.
class WidgetReturningMethodRule extends StaticRule {
  @override
  String get id => 'widget_returning_method';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_WidgetMethodVisitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.performance,
        severity: Severity.info,
        message: 'A method/getter returning `Widget` doesn\'t get its own '
            '`Element`, so Flutter can\'t skip rebuilding it '
            'independently — extract it to its own widget class instead.',
        location: locationOfToken(unit, node.name, context, end: node.end),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final String typeName;
  final void Function(InstanceCreationExpression node) onMatch;

  _Visitor(this.typeName, this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (creationTypeName(node) == typeName &&
        node.constructorName.name == null) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}

class _ChildrenCountVisitor extends RecursiveAstVisitor<void> {
  final Set<String> types;
  final void Function(InstanceCreationExpression node, int count) onMatch;

  _ChildrenCountVisitor(this.types, this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (types.contains(creationTypeName(node))) {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression &&
            arg.name.label.name == 'children' &&
            arg.expression is ListLiteral) {
          onMatch(node, (arg.expression as ListLiteral).elements.length);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

class _WidgetMethodVisitor extends RecursiveAstVisitor<void> {
  final void Function(MethodDeclaration node) onMatch;

  _WidgetMethodVisitor(this.onMatch);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Not `.toSource()`: a nullable return type (`Widget?`) would include
    // the `?` and never match — same class of bug as creationTypeName.
    final returnType = node.returnType;
    final returnTypeName = returnType is NamedType ? returnType.name.lexeme : null;
    // A member's parent is the class *body*; the declaration is above it.
    final enclosing = node.parent?.parent;
    if (node.name.lexeme != 'build' &&
        returnTypeName == 'Widget' &&
        !node.isStatic &&
        enclosing is ClassDeclaration &&
        (extendsClassNamed(enclosing, 'Widget') || extendsClassNamed(enclosing, 'State'))) {
      onMatch(node);
    }
    super.visitMethodDeclaration(node);
  }
}
