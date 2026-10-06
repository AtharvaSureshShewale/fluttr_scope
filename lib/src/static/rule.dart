import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:path/path.dart' as p;

import '../model/finding.dart';
import '../model/source_location.dart';

/// A single static check, run once per resolved compilation unit.
abstract class StaticRule {
  /// Stable identifier reported on every [Finding] this rule produces.
  String get id;

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
  final start = unit.lineInfo.getLocation(node.offset);
  return SourceLocation(
    file: relativePath(unit, context),
    line: start.lineNumber,
    column: start.columnNumber,
    length: node.length,
  );
}

/// Builds the [SourceLocation] of [token] within [unit] -- for pointing a
/// finding at a declaration's *name* rather than its first token, which
/// for a method is its doc comment or `@override` annotation.
SourceLocation locationOfToken(
  ResolvedUnitResult unit,
  Token token,
  RuleContext context,
) {
  final start = unit.lineInfo.getLocation(token.offset);
  return SourceLocation(
    file: relativePath(unit, context),
    line: start.lineNumber,
    column: start.columnNumber,
    length: token.length,
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
