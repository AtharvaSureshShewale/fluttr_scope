import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Types that must be disposed, mapped to the method that disposes them.
/// `StreamSubscription` uses `.cancel()`; the rest use `.dispose()`.
const _disposableTypes = {
  'AnimationController': 'dispose',
  'TextEditingController': 'dispose',
  'ScrollController': 'dispose',
  'PageController': 'dispose',
  'FocusNode': 'dispose',
  'StreamSubscription': 'cancel',
};

/// Flags fields of a disposable type (animation controllers, text editing
/// controllers, stream subscriptions, ...) declared on a `State` subclass
/// whose `dispose()` doesn't release them — a common source of leaks that
/// `leak_tracker` (the runtime side, a later milestone) would otherwise
/// only catch at test time.
class DisposeMissingRule extends StaticRule {
  @override
  String get id => 'dispose_missing';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(ClassVisitor((classNode) {
      if (!extendsClassNamed(classNode, 'State')) return;

      final fields = _disposableFields(classNode);
      if (fields.isEmpty) return;

      final disposedNames = _disposedFieldNames(classNode);
      final created = _fieldsCreatedHere(classNode);
      for (final entry in fields.entries) {
        final field = entry.key;
        final disposeMethod = entry.value;
        if (disposedNames[field.name.lexeme] == disposeMethod) continue;
        // A controller handed in from elsewhere is its creator's to dispose
        // (disposing it here would be the bug), and a field never assigned
        // holds nothing -- both were false positives on a real app.
        if (!created.contains(field.name.lexeme)) continue;

        findings.add(Finding(
          ruleId: id,
          category: Category.performance,
          severity: Severity.warning,
          message: 'Field `${field.name.lexeme}` is never '
              '${disposeMethod == 'cancel' ? 'cancelled' : 'disposed'} in '
              '`dispose()`.',
          location: locationOf(unit, field, context),
        ));
      }
    }));
    return findings;
  }
}

/// Disposable fields declared directly on [classNode], keyed by the method
/// name (`dispose` or `cancel`) that must be called on them.
Map<VariableDeclaration, String> _disposableFields(
  ClassDeclaration classNode,
) {
  final result = <VariableDeclaration, String>{};
  for (final member in classMembers(classNode)) {
    if (member is! FieldDeclaration) continue;
    // Not `.toSource()`: that includes generic args and the nullability
    // suffix (`StreamSubscription<int>?`), which would never match a plain
    // key in _disposableTypes. `NamedType.name2` is the bare type name.
    final type = member.fields.type;
    final typeName = type is NamedType ? type.name.lexeme : null;
    final disposeMethod = _disposableTypes[typeName];
    if (disposeMethod == null) continue;
    for (final variable in member.fields.variables) {
      result[variable] = disposeMethod;
    }
  }
  return result;
}

/// Names of fields that [classNode] gives a newly created value: an
/// initializer like `= ScrollController()`, or an assignment anywhere in the
/// class like `_controller = PageController(...)` or
/// `_focusNode = widget.focusNode ?? FocusNode()`.
Set<String> _fieldsCreatedHere(ClassDeclaration classNode) {
  final names = <String>{};
  for (final member in classMembers(classNode)) {
    if (member is! FieldDeclaration) continue;
    for (final v in member.fields.variables) {
      final init = v.initializer;
      if (init != null && _createsValue(init)) names.add(v.name.lexeme);
    }
  }
  classNode.accept(_AssignmentVisitor((target, value) {
    if (_createsValue(value)) names.add(target);
  }));
  return names;
}

bool _createsValue(Expression e) {
  var found = false;
  e.accept(_CreationFinder(() => found = true));
  return found;
}

class _CreationFinder extends RecursiveAstVisitor<void> {
  final void Function() onFound;

  _CreationFinder(this.onFound);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) => onFound();

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A controller created inside a callback isn't the field's value.
  }
}

/// Reports `name = value` assignments to a plain or `this.`-qualified name.
class _AssignmentVisitor extends RecursiveAstVisitor<void> {
  final void Function(String target, Expression value) onAssignment;

  _AssignmentVisitor(this.onAssignment);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final target = switch (node.leftHandSide) {
      SimpleIdentifier(:final name) => name,
      PropertyAccess(target: ThisExpression(), :final propertyName) => propertyName.name,
      _ => null,
    };
    if (target != null) onAssignment(target, node.rightHandSide);
    super.visitAssignmentExpression(node);
  }
}

/// Field name -> method name (`dispose`/`cancel`) invoked on it anywhere in
/// the class's `dispose()` method body.
Map<String, String> _disposedFieldNames(ClassDeclaration classNode) {
  final disposeMethod = classMembers(classNode)
      .whereType<MethodDeclaration>()
      .where((m) => m.name.lexeme == 'dispose')
      .firstOrNull;
  if (disposeMethod == null) return const {};

  final calls = <String, String>{};
  disposeMethod.accept(_MethodCallVisitor((target, methodName) {
    if (target != null) calls[target] = methodName;
  }));
  return calls;
}

class _MethodCallVisitor extends RecursiveAstVisitor<void> {
  final void Function(String? target, String methodName) onCall;

  _MethodCallVisitor(this.onCall);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target is SimpleIdentifier) {
      onCall(target.name, node.methodName.name);
    } else if (target == null) {
      onCall(null, node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}
