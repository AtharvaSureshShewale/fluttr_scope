import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Flags `setState(...)` called after an `await` in a `State` method
/// without a `mounted` check in between. Awaiting can outlive the widget
/// (the user navigates away, a test tears down); calling `setState` on an
/// unmounted `State` throws at runtime.
///
/// For each call, walks backwards through what runs before it -- earlier
/// statements in each enclosing block, enclosing `if` conditions, the
/// `try` body of an enclosing `catch`/`finally` -- and flags it if an
/// `await` that can fall through is reached before a guard: `if (!mounted)
/// return;` earlier in a block, or an enclosing `if (mounted) {...}`.
///
/// Out of scope, so never flagged rather than guessed at: a `setState`
/// inside a closure (it runs when the callback fires, not after the
/// await), and an await carried around a loop into its next iteration.
class MissingMountedCheckRule extends StaticRule {
  @override
  String get id => 'missing_mounted_check';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(ClassVisitor((classNode) {
      if (!extendsClassNamed(classNode, 'State')) return;

      for (final member in classNode.body.members) {
        if (member is! MethodDeclaration) continue;
        final body = member.body;
        if (body is! BlockFunctionBody) continue;

        body.block.accept(_SetStateFinder((call) {
          if (!_awaitedWithoutGuard(call, body)) return;
          findings.add(Finding(
            ruleId: id,
            category: Category.correctness,
            severity: Severity.warning,
            message: '`setState()` called after `await` without checking '
                '`mounted` first; the widget may have been disposed by '
                'the time this runs.',
            location: locationOf(unit, call, context),
          ));
        }));
      }
    }));
    return findings;
  }
}

/// Whether an `await` can have run before [call] (within [body]) with no
/// `mounted` guard after it. Nearer code is checked first, so whichever of
/// "await" and "guard" happened most recently decides.
bool _awaitedWithoutGuard(MethodInvocation call, FunctionBody body) {
  AstNode child = call;
  for (var node = call.parent; node != null && node != body; child = node, node = node.parent) {
    switch (node) {
      case Block(:final statements):
        for (final stmt in statements.takeWhile((s) => !identical(s, child)).toList().reversed) {
          if (_isMountedReturnGuard(stmt)) return false;
          if (_awaitsAndFallsThrough(stmt)) return true;
        }
      case IfStatement(:final expression, :final thenStatement):
        if (identical(child, thenStatement) && _requiresMounted(expression)) return false;
        if (!identical(child, expression) && _awaitsAndFallsThrough(expression)) return true;
      case CatchClause() || TryStatement():
        final tryStatement = node is TryStatement ? node : node.parent as TryStatement;
        if (!identical(child, tryStatement.body) && _awaitsAndFallsThrough(tryStatement.body)) {
          return true;
        }
    }
  }
  return false;
}

/// Matches the `if (!mounted) return;` shape (or `break`/`continue`),
/// including `if (!context.mounted || other) return;`. The condition must
/// actually exit when *not* mounted -- `if (mounted) return;` is the
/// opposite of a guard.
bool _isMountedReturnGuard(Statement stmt) {
  if (stmt is! IfStatement) return false;
  if (!_testsNotMounted(stmt.expression)) return false;
  final then = stmt.thenStatement;
  final exit =
      then is Block ? (then.statements.length == 1 ? then.statements.first : null) : then;
  return exit is ReturnStatement || exit is BreakStatement || exit is ContinueStatement;
}

/// Whether [node] contains an `await` after which execution can continue
/// past [node] -- i.e. not one inside a block that always ends in
/// `return`/`throw` (`if (x) { await y; return; }`), nor in a closure.
bool _awaitsAndFallsThrough(AstNode node) {
  var found = false;
  node.accept(_AwaitFinder(() => found = true));
  return found;
}

/// `mounted`, `this.mounted`, or `context.mounted` (any `x.mounted`).
bool _isMountedRead(Expression e) => switch (e.unParenthesized) {
      SimpleIdentifier(name: 'mounted') => true,
      PrefixedIdentifier(identifier: SimpleIdentifier(name: 'mounted')) => true,
      PropertyAccess(propertyName: SimpleIdentifier(name: 'mounted')) => true,
      _ => false,
    };

/// Whether [condition] can only be true while mounted: `mounted`, or an
/// `&&` with `mounted` on either side.
bool _requiresMounted(Expression condition) => switch (condition.unParenthesized) {
      final e when _isMountedRead(e) => true,
      BinaryExpression(operator: Token(lexeme: '&&'), :final leftOperand, :final rightOperand) =>
        _requiresMounted(leftOperand) || _requiresMounted(rightOperand),
      _ => false,
    };

/// Whether [condition] is true whenever not mounted: `!mounted`, or an
/// `||` with `!mounted` on either side.
bool _testsNotMounted(Expression condition) => switch (condition.unParenthesized) {
      PrefixExpression(operator: Token(lexeme: '!'), :final operand) => _isMountedRead(operand),
      BinaryExpression(operator: Token(lexeme: '||'), :final leftOperand, :final rightOperand) =>
        _testsNotMounted(leftOperand) || _testsNotMounted(rightOperand),
      _ => false,
    };

class _AwaitFinder extends RecursiveAstVisitor<void> {
  final void Function() onMatch;

  _AwaitFinder(this.onMatch);

  @override
  void visitAwaitExpression(AwaitExpression node) {
    onMatch();
    super.visitAwaitExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Don't descend into nested closures — an await inside a separate
    // async closure doesn't gate this statement's own execution.
  }

  @override
  void visitBlock(Block node) {
    // An await in a block that always exits can't be followed by anything
    // after that block.
    if (_alwaysExits(node)) return;
    super.visitBlock(node);
  }
}

bool _alwaysExits(Block block) {
  final last = block.statements.lastOrNull;
  return last is ReturnStatement ||
      (last is ExpressionStatement &&
          (last.expression is ThrowExpression || last.expression is RethrowExpression));
}

class _SetStateFinder extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation) onMatch;

  _SetStateFinder(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState' &&
        (node.target == null || node.target is ThisExpression)) {
      onMatch(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A setState in a callback runs when the callback fires -- out of scope.
  }
}
