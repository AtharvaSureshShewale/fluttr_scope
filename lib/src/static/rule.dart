import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../model/category.dart';
import '../model/finding.dart';
import '../model/source_location.dart';

/// A single static check, run once per resolved compilation unit.
abstract class StaticRule {
  /// Stable identifier reported on every [Finding] this rule produces.
  String get id;

  /// The category of every [Finding] this rule produces.
  Category get category;

  List<Finding> check(ResolvedUnitResult unit, RuleContext context);
}

/// Shared context passed to every rule for a given analysis run.
class RuleContext {
  /// Absolute path to the project root being analyzed. Used to make
  /// every reported [SourceLocation.file] root-relative rather than
  /// machine-specific, since that's the format reports (SARIF, JSON) and
  /// the future runtime correlator both need.
  final String root;

  const RuleContext({required this.root});
}

/// Builds the [SourceLocation] for [node] within [unit].
///
/// This is the one place span math happens, so every rule reports locations
/// the same way the correlator will later expect.
SourceLocation locationOf(
  ResolvedUnitResult unit,
  AstNode node,
  RuleContext context,
) {
  final offset = _joinOffset(node);
  final start = unit.lineInfo.getLocation(offset);
  return SourceLocation(
    file: relativePath(unit, context),
    line: start.lineNumber,
    column: start.columnNumber,
    length: node.end - offset,
  );
}

/// Where [node] starts, by the same convention Flutter's widget-creation
/// tracking uses for the locations it reports at runtime -- so a finding on
/// a widget and that widget's rebuild data share the exact file:line:column
/// join key. For a constructor call that's the constructor name: `asset`
/// in `Image.asset(...)`, `Text` in `const Text(...)` (no keyword) -- but
/// the type when it has type arguments: `Provider` in
/// `Provider<T>.value(...)` (both seen on Wonderous's rebuild data).
int _joinOffset(AstNode node) => switch (node) {
      InstanceCreationExpression(:final constructorName)
          when constructorName.type.typeArguments == null =>
        constructorName.name?.offset ?? constructorName.offset,
      InstanceCreationExpression(:final constructorName) => constructorName.offset,
      _ => node.offset,
    };

/// Builds the [SourceLocation] of [token] within [unit] -- for pointing a
/// finding at a declaration's *name* rather than its first token, which
/// for a method is its doc comment or `@override` annotation.
///
/// [end] extends the span past the token (e.g. to the end of the method
/// body), so tools that ask "did this code run?" check the body's lines --
/// the VM's coverage never reports a declaration line itself.
SourceLocation locationOfToken(
  ResolvedUnitResult unit,
  Token token,
  RuleContext context, {
  int? end,
}) {
  final start = unit.lineInfo.getLocation(token.offset);
  return SourceLocation(
    file: relativePath(unit, context),
    line: start.lineNumber,
    column: start.columnNumber,
    length: (end ?? token.end) - token.offset,
  );
}

/// Builds a [SourceLocation] from a raw 1-based line/column, for rules
/// that work over [unit]'s source text directly rather than an [AstNode]
/// (e.g. a comment scan).
SourceLocation locationAt(
  ResolvedUnitResult unit,
  RuleContext context, {
  required int line,
  required int column,
  required int length,
}) {
  return SourceLocation(
    file: relativePath(unit, context),
    line: line,
    column: column,
    length: length,
  );
}

String relativePath(ResolvedUnitResult unit, RuleContext context) =>
    p.relative(unit.path, from: context.root).replaceAll('\\', '/');

/// Whether [unit] is test code (`test/`, `integration_test/`, or a
/// `*_test.dart` file) -- where literals like IP addresses and URLs are
/// test data rather than something the app connects to.
bool isTestFile(ResolvedUnitResult unit, RuleContext context) {
  final path = relativePath(unit, context);
  return path.startsWith('test/') ||
      path.startsWith('integration_test/') ||
      path.endsWith('_test.dart');
}

/// [Finding.evidenceLocations] for code at [node] that Flutter's rebuild
/// tracking can't see directly: a widget that is only ever built when
/// [node] runs too.
///
/// That's the nearest constructor call [node] sits inside, if nothing
/// conditional (`?:`, `??`, `&&`, collection `if`/`for`) or closure lies in
/// between. Failing that, when [node] runs unconditionally at the start of
/// its function -- before any branch or early `return` -- every
/// constructor call in that function. Otherwise none: a widget built on
/// another branch says nothing about this code (found on Wonderous, where
/// `if (...) return SizedBox.expand();` was credited with the rebuilds of
/// the widget built when that branch *isn't* taken).
List<SourceLocation> rerunEvidence(
  ResolvedUnitResult unit,
  AstNode node,
  RuleContext context,
) {
  for (var n = node.parent; n != null && !_isConditional(n); n = n.parent) {
    if (n is InstanceCreationExpression) return [locationOf(unit, n, context)];
    if (n is Statement || n is FunctionBody) break;
  }
  final body = node.thisOrAncestorOfType<FunctionBody>();
  if (body == null || !_runsWheneverBodyRuns(node, body)) return const [];
  return creationsIn(unit, body, context);
}

bool _isConditional(AstNode node) => switch (node) {
      ConditionalExpression() || IfElement() || ForElement() || SwitchExpression() => true,
      FunctionBody() || FunctionExpression() => true,
      IfStatement() || SwitchStatement() || ForStatement() || WhileStatement() || DoStatement() ||
          TryStatement() =>
        true,
      BinaryExpression(:final operator) => operator.type == TokenType.QUESTION_QUESTION ||
          operator.type == TokenType.AMPERSAND_AMPERSAND ||
          operator.type == TokenType.BAR_BAR,
      _ => false,
    };

/// Whether [node] runs every time [body] does: nothing conditional between
/// them, and (in a block) no statement before it that could branch or
/// return early.
bool _runsWheneverBodyRuns(AstNode node, FunctionBody body) {
  final block = body is BlockFunctionBody ? body.block : null;
  Statement? statement; // the one directly in the function's block
  for (var n = node.parent; n != null && n != body; n = n.parent) {
    if (_isConditional(n)) return false;
    if (n is Statement && n.parent == block) statement = n;
  }
  if (body is ExpressionFunctionBody) return true;
  if (block == null || statement == null) return false;
  final statements = block.statements;
  final index = statements.indexOf(statement);
  return statements
      .take(index)
      .every((s) => s is VariableDeclarationStatement || s is ExpressionStatement);
}

/// The locations of the constructor calls [body] runs every time it runs:
/// its own, not those in closures nested inside it.
List<SourceLocation> creationsIn(
  ResolvedUnitResult unit,
  FunctionBody body,
  RuleContext context,
) {
  final locations = <SourceLocation>[];
  body.accept(_CreationCollector(body, (node) => locations.add(locationOf(unit, node, context))));
  return locations;
}

class _CreationCollector extends RecursiveAstVisitor<void> {
  final FunctionBody root;
  final void Function(InstanceCreationExpression node) onCreation;

  _CreationCollector(this.root, this.onCreation);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    onCreation(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.body == root) super.visitFunctionExpression(node);
  }
}
