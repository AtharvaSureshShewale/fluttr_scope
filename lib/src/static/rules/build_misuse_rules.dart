import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `GlobalKey`/`UniqueKey` constructed directly inside `build()`. A
/// new key every rebuild defeats the point of a stable key (or, for
/// `GlobalKey`, throws a duplicate-key error once the old one is still
/// attached to the tree). It should be created once and stored in a field.
class KeyCreatedInBuildRule extends StaticRule {
  @override
  String get id => 'key_created_in_build';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(BuildMethodVisitor((buildMethod) {
      buildMethod.body.accept(_KeyCreationVisitor(buildMethod.body, (node) {
        final typeName = creationTypeName(node);
        findings.add(Finding(
          ruleId: id,
          category: Category.performance,
          severity: Severity.warning,
          message: 'A new `$typeName` is created every time `build()` '
              'runs; move it to a field so it stays stable across '
              'rebuilds.',
          location: locationOf(unit, node, context),
        ));
      }));
    }));
    return findings;
  }
}

class _KeyCreationVisitor extends RecursiveAstVisitor<void> {
  final AstNode root;
  final void Function(InstanceCreationExpression node) onMatch;

  _KeyCreationVisitor(this.root, this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = creationTypeName(node);
    if ((typeName == 'GlobalKey' || typeName == 'UniqueKey') &&
        !isInsideNestedClosure(node, root)) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// Flags `Theme.of(context)`/`MediaQuery.of(context)`/
/// `Localizations.of(context)` called directly in `initState()`.
/// `InheritedWidget` dependencies aren't established until after the first
/// `build()`, so this throws at runtime — the fix is
/// `didChangeDependencies()`.
class InheritedWidgetOfInInitStateRule extends StaticRule {
  static const _inheritedLookups = {'Theme', 'MediaQuery', 'Localizations'};

  @override
  String get id => 'inherited_widget_of_in_initstate';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_InitStateVisitor((initState) {
      initState.body.accept(_OfCallVisitor(initState.body, (node) {
        final target = node.target as SimpleIdentifier;
        findings.add(Finding(
          ruleId: id,
          category: Category.correctness,
          severity: Severity.error,
          message: '`${target.name}.of(context)` called directly in '
              '`initState()` throws — InheritedWidget dependencies aren\'t '
              'established yet. Use `didChangeDependencies()` instead.',
          location: locationOf(unit, node, context),
        ));
      }));
    }));
    return findings;
  }

  static bool _isInheritedLookup(SimpleIdentifier target) =>
      _inheritedLookups.contains(target.name);
}

class _InitStateVisitor extends RecursiveAstVisitor<void> {
  final void Function(MethodDeclaration node) onMatch;

  _InitStateVisitor(this.onMatch);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'initState' &&
        (node.parameters?.parameters.isEmpty ?? false)) {
      onMatch(node);
    }
    super.visitMethodDeclaration(node);
  }
}

class _OfCallVisitor extends RecursiveAstVisitor<void> {
  final AstNode root;
  final void Function(MethodInvocation node) onMatch;

  _OfCallVisitor(this.root, this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (node.methodName.name == 'of' &&
        target is SimpleIdentifier &&
        InheritedWidgetOfInInitStateRule._isInheritedLookup(target) &&
        !isInsideNestedClosure(node, root)) {
      onMatch(node);
    }
    super.visitMethodInvocation(node);
  }
}

/// Flags a `BuildContext` assigned to a class field. A stored context can
/// go stale after the widget rebuilds or unmounts, and using it later
/// risks acting on a disposed element — the context should be passed
/// through method parameters instead, fresh each time.
class BuildContextStoredInFieldRule extends StaticRule {
  @override
  String get id => 'build_context_stored_in_field';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.correctness,
        severity: Severity.warning,
        message: 'Storing `BuildContext` in a field risks using a stale '
            'or disposed context later. Pass it through method parameters '
            'instead.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(AssignmentExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_isBuildContextType(node.rightHandSide) && _isFieldTarget(node)) {
      onMatch(node);
    }
    super.visitAssignmentExpression(node);
  }

  bool _isBuildContextType(Expression expr) {
    final type = expr.staticType;
    return type is InterfaceType && type.element3.name3 == 'BuildContext';
  }

  /// Whether [node]'s left-hand side names a field declared on the
  /// enclosing class. Checked structurally (matching the assignment
  /// target's name against the class's declared fields) rather than via
  /// element resolution, since a write-target identifier's resolved
  /// element isn't reliably the `FieldElement` itself across analyzer
  /// versions — it may resolve through a setter accessor instead.
  bool _isFieldTarget(AssignmentExpression node) {
    final lhs = node.leftHandSide;
    final String name;
    if (lhs is SimpleIdentifier) {
      name = lhs.name;
    } else if (lhs is PropertyAccess && lhs.target is ThisExpression) {
      name = lhs.propertyName.name;
    } else {
      return false;
    }

    for (var current = node.parent; current != null; current = current.parent) {
      if (current is ClassDeclaration) {
        return current.members
            .whereType<FieldDeclaration>()
            .any((f) => f.fields.variables.any((v) => v.name.lexeme == name));
      }
    }
    return false;
  }
}
