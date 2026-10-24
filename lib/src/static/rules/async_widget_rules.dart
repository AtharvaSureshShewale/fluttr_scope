import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

// FutureBuilder/StreamBuilder catch the error themselves and hand it to
// the builder as `snapshot.error` -- nothing is thrown. The failure mode is
// silence: the user sees stale data or a spinner that never ends.
const _errorCheckMessage =
    "This builder never checks `snapshot.hasError`, so if the future or stream "
    "fails, the user keeps seeing the loading state or old data with no error shown.";

/// Flags a `FutureBuilder` whose `builder` never checks `snapshot.hasError`.
class FutureBuilderMissingErrorCheckRule extends StaticRule {
  @override
  String get id => 'future_builder_missing_error_check';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) =>
      _checkMissingErrorHandling(unit, context, id, 'FutureBuilder');
}

/// Flags a `StreamBuilder` whose `builder` never checks `snapshot.hasError`.
class StreamBuilderMissingErrorCheckRule extends StaticRule {
  @override
  String get id => 'stream_builder_missing_error_check';

  @override
  Category get category => Category.correctness;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) =>
      _checkMissingErrorHandling(unit, context, id, 'StreamBuilder');
}

List<Finding> _checkMissingErrorHandling(
  ResolvedUnitResult unit,
  RuleContext context,
  String ruleId,
  String widgetType,
) {
  final findings = <Finding>[];
  unit.unit.accept(_BuilderArgVisitor(widgetType, 'builder', (node, builderFn) {
    var hasErrorChecked = false;
    builderFn.body.accept(_PropertyReadFinder('hasError', () => hasErrorChecked = true));
    if (!hasErrorChecked) {
      findings.add(Finding(
        ruleId: ruleId,
        category: Category.correctness,
        severity: Severity.warning,
        message: _errorCheckMessage,
        location: locationOf(unit, node, context),
      ));
    }
  }));
  return findings;
}

/// Flags `FutureBuilder.future`/`StreamBuilder.stream` created inline in
/// `build()` (e.g. `future: fetchData()`) instead of referencing a value
/// stored in a field. Created inline, it re-fires on every rebuild.
class FutureCreatedInBuildRule extends StaticRule {
  static const _paramByType = {'FutureBuilder': 'future', 'StreamBuilder': 'stream'};

  @override
  String get id => 'future_created_in_build';

  @override
  Category get category => Category.performance;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(BuildMethodVisitor((buildMethod) {
      for (final entry in _paramByType.entries) {
        buildMethod.body.accept(_BuilderArgVisitor(entry.key, entry.value, (node, _) {},
            onArgMethodInvocation: (node, widgetType, paramName) {
          findings.add(Finding(
            ruleId: id,
            category: Category.performance,
            severity: Severity.warning,
            message: '`$widgetType`\'s `$paramName` is created inline in '
                '`build()`, so it restarts on every rebuild. Store it in '
                'a field (e.g. set in `initState`) instead.',
            location: locationOf(unit, node, context),
            evidenceLocations: rerunEvidence(unit, node, context),
          ));
        }));
      }
    }));
    return findings;
  }
}

/// Finds the `argName:` argument of an `InstanceCreationExpression` for
/// [widgetType]. If it's a `FunctionExpression`, [onMatch] fires with it;
/// if it's a `MethodInvocation` (created inline, not a stored reference),
/// [onArgMethodInvocation] fires instead.
class _BuilderArgVisitor extends RecursiveAstVisitor<void> {
  final String widgetType;
  final String argName;
  final void Function(InstanceCreationExpression node, FunctionExpression builder) onMatch;
  final void Function(Expression node, String widgetType, String argName)?
      onArgMethodInvocation;

  _BuilderArgVisitor(this.widgetType, this.argName, this.onMatch, {this.onArgMethodInvocation});

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (creationTypeName(node) == widgetType) {
      for (final arg in node.argumentList.arguments) {
        if (arg is! NamedExpression || arg.name.label.name != argName) continue;
        if (arg.expression is FunctionExpression) {
          onMatch(node, arg.expression as FunctionExpression);
        } else if (arg.expression is MethodInvocation) {
          onArgMethodInvocation?.call(arg.expression, widgetType, argName);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

class _PropertyReadFinder extends RecursiveAstVisitor<void> {
  final String propertyName;
  final void Function() onMatch;

  _PropertyReadFinder(this.propertyName, this.onMatch);

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == propertyName) onMatch();
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == propertyName) onMatch();
    super.visitPrefixedIdentifier(node);
  }
}
