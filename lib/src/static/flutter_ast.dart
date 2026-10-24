import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

/// Whether [classNode] transitively extends/implements a class named
/// [className] — good enough to identify Flutter framework types like
/// `State` without needing an exact package match.
bool extendsClassNamed(ClassDeclaration classNode, String className) {
  final element = classNode.declaredFragment?.element;
  if (element == null) return false;
  return element.allSupertypes.any((t) => t.element.name == className);
}

/// The members of [classNode]. Works across the analyzer versions this
/// package supports: in analyzer 10.0 the member list lives on
/// `BlockClassBody` (a body in braces) only, later on every `ClassBody`.
List<ClassMember> classMembers(ClassDeclaration classNode) => switch (classNode.body) {
      BlockClassBody(:final members) => members,
      _ => const [],
    };

class ClassVisitor extends RecursiveAstVisitor<void> {
  final void Function(ClassDeclaration node) onClass;

  ClassVisitor(this.onClass);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    onClass(node);
    super.visitClassDeclaration(node);
  }
}

/// Visits every widget `build` method: Flutter's `Widget build(BuildContext
/// context)`, and Riverpod's `Widget build(BuildContext context, WidgetRef
/// ref)` (`ConsumerWidget`), which a one-parameter check missed entirely.
class BuildMethodVisitor extends RecursiveAstVisitor<void> {
  final void Function(MethodDeclaration node) onBuildMethod;

  BuildMethodVisitor(this.onBuildMethod);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (isWidgetBuildMethod(node)) onBuildMethod(node);
    super.visitMethodDeclaration(node);
  }
}

/// Whether [node] is a widget's `build` method: named `build`, taking a
/// `BuildContext` first (plus at most one more parameter, e.g. Riverpod's
/// `WidgetRef`). An untyped single parameter (`build(context)`) also counts.
/// Unrelated methods that happen to be called `build` -- a query builder's
/// `build(String sql, int limit)` -- don't.
bool isWidgetBuildMethod(MethodDeclaration node) {
  if (node.name.lexeme != 'build') return false;
  final params = node.parameters?.parameters ?? const <FormalParameter>[];
  if (params.isEmpty || params.length > 2) return false;
  final first = params.first;
  final type = switch (first) {
    SimpleFormalParameter(:final type) => type,
    DefaultFormalParameter(parameter: SimpleFormalParameter(:final type)) => type,
    _ => null,
  };
  if (type is NamedType) return type.name.lexeme == 'BuildContext';
  return params.length == 1;
}

/// The base type name a constructor call invokes — e.g. `FutureBuilder`
/// for both `FutureBuilder(...)` and a generic `FutureBuilder<String>(...)`.
///
/// `node.constructorName.type.toSource()` looks equivalent but isn't: for
/// a generic instantiation it includes the type arguments in the source
/// text (`"FutureBuilder<String>"`), which silently breaks any `==`
/// comparison against a plain type name.
String creationTypeName(InstanceCreationExpression node) =>
    node.constructorName.type.name.lexeme;

/// The widget creation [node] is passed to as an argument (`child:`,
/// `children: [...]`, ...), or `null` if that isn't visible from [node]'s
/// position -- returned from a helper or closure, assigned to a variable,
/// passed to a plain method.
///
/// Collection `if`/`for`, spreads, `?:`, and parentheses are seen through,
/// since none of them change which widget ends up the parent.
InstanceCreationExpression? visibleParentWidget(AstNode node) {
  var current = node.parent;
  while (current != null) {
    switch (current) {
      case ParenthesizedExpression():
      case ConditionalExpression():
      case IfElement():
      case ForElement():
      case SpreadElement():
      case ListLiteral():
      case NamedExpression():
        current = current.parent;
      case ArgumentList(:final InstanceCreationExpression parent):
        return parent;
      default:
        return null;
    }
  }
  return null;
}

/// Whether [creation] constructs a type declared in the Flutter framework
/// itself (`package:flutter/...`), as opposed to an app's own widget.
bool isFrameworkWidget(InstanceCreationExpression creation) {
  final type = creation.staticType;
  return type is InterfaceType &&
      type.element.library.uri.toString().startsWith('package:flutter/');
}

/// Whether [type] is Flutter's `Animation` or a subtype of it
/// (`AnimationController`, `CurvedAnimation`, ...) -- something that
/// notifies its listeners on every frame while it runs.
bool isFlutterAnimation(DartType? type) {
  if (type is! InterfaceType) return false;
  return [type, ...type.allSupertypes].any((t) =>
      t.element.name == 'Animation' &&
      t.element.library.uri.toString().startsWith('package:flutter/'));
}

/// Whether [node]'s nearest enclosing function literal, walking up toward
/// [root], is something other than [root] itself — i.e. [node] sits inside
/// a nested closure/local function declared within [root], rather than
/// directly in [root]'s own body.
bool isInsideNestedClosure(AstNode node, AstNode root) {
  for (var current = node.parent;
      current != null && current != root;
      current = current.parent) {
    if (current is FunctionExpression || current is FunctionDeclaration) {
      return true;
    }
  }
  return false;
}
