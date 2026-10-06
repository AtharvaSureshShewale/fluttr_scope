import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

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

/// Flags `Column`/`Row` wrapping a single child — the wrapper serves no
/// layout purpose and can be replaced with the child directly.
class UnnecessaryColumnOrRowRule extends StaticRule {
  @override
  String get id => 'unnecessary_column_or_row';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_ChildrenCountVisitor({'Column', 'Row'}, (node, count) {
      if (count == 1) {
        findings.add(Finding(
          ruleId: id,
          category: Category.style,
          severity: Severity.info,
          message: '`${creationTypeName(node)}` wraps a '
              'single child for no layout purpose — use the child '
              'directly.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
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
          message: '`${creationTypeName(node)}` has no '
              'children — likely leftover placeholder code.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

/// Flags a method or getter that returns `Widget` but isn't the `build`
/// override. Unlike a real widget class, it doesn't get its own
/// `Element`, so Flutter can't skip rebuilding it independently of its
/// caller — a common source of larger-than-necessary rebuild scopes.
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
        location: locationOf(unit, node, context),
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
    final returnTypeName = returnType is NamedType ? returnType.name2.lexeme : null;
    if (node.name.lexeme != 'build' && returnTypeName == 'Widget') {
      onMatch(node);
    }
    super.visitMethodDeclaration(node);
  }
}
