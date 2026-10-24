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
/// tracking can't see directly: the constructor calls [node] is nested
/// inside, out to its enclosing function -- whenever one of those widgets
/// is rebuilt, this code ran again. When there are none (a local variable
/// at the top of `build`), the constructor calls of that function body.
List<SourceLocation> rerunEvidence(
  ResolvedUnitResult unit,
  AstNode node,
  RuleContext context,
) {
  final enclosing = [
    for (var n = node.parent; n != null && n is! FunctionBody; n = n.parent)
      if (n is InstanceCreationExpression) locationOf(unit, n, context),
  ];
  if (enclosing.isNotEmpty) return enclosing;
  final body = node.thisOrAncestorOfType<FunctionBody>();
  return body == null ? const [] : creationsIn(unit, body, context);
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
