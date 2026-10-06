import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

/// Whether [classNode] transitively extends/implements a class named
/// [className] — good enough to identify Flutter framework types like
/// `State` without needing an exact package match.
bool extendsClassNamed(ClassDeclaration classNode, String className) {
  final element = classNode.declaredFragment?.element;
  if (element == null) return false;
  return element.allSupertypes.any((t) => t.element3.name3 == className);
}

class ClassVisitor extends RecursiveAstVisitor<void> {
  final void Function(ClassDeclaration node) onClass;

  ClassVisitor(this.onClass);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    onClass(node);
    super.visitClassDeclaration(node);
  }
}

/// Visits every method literally named `build` taking exactly one
/// parameter — Flutter's `Widget build(BuildContext context)` override,
/// identified structurally rather than via type resolution.
class BuildMethodVisitor extends RecursiveAstVisitor<void> {
  final void Function(MethodDeclaration node) onBuildMethod;

  BuildMethodVisitor(this.onBuildMethod);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.name.lexeme == 'build' && node.parameters?.parameters.length == 1) {
      onBuildMethod(node);
    }
    super.visitMethodDeclaration(node);
  }
}

/// The base type name a constructor call invokes — e.g. `FutureBuilder`
/// for both `FutureBuilder(...)` and a generic `FutureBuilder<String>(...)`.
///
/// `node.constructorName.type.toSource()` looks equivalent but isn't: for
/// a generic instantiation it includes the type arguments in the source
/// text (`"FutureBuilder<String>"`), which silently breaks any `==`
/// comparison against a plain type name.
String creationTypeName(InstanceCreationExpression node) =>
    node.constructorName.type.name2.lexeme;

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
      type.element3.library2.uri.toString().startsWith('package:flutter/');
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
