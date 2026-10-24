// Runs fluttr_scope's static rules plus one custom rule against a Flutter
// project and prints the findings as SARIF.
//
//   dart run example/example.dart path/to/flutter_app

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:fluttr_scope/fluttr_scope.dart';

/// A custom rule: flags `debugPrint(...)` calls.
class AvoidDebugPrintRule extends StaticRule {
  @override
  String get id => 'avoid_debug_print';

  @override
  Category get category => Category.style;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_DebugPrintVisitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.style,
        severity: Severity.info,
        message: 'Remove debugPrint before release.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _DebugPrintVisitor extends RecursiveAstVisitor<void> {
  final void Function(AstNode) onMatch;

  _DebugPrintVisitor(this.onMatch);

  // Flutter's debugPrint is a top-level variable holding a function, so a
  // call to it resolves to a FunctionExpressionInvocation, not a
  // MethodInvocation.
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier && function.name == 'debugPrint') onMatch(node);
    super.visitFunctionExpressionInvocation(node);
  }
}

Future<void> main(List<String> args) async {
  final project = args.isEmpty ? '.' : args.first;

  final engine = AnalysisEngine([...allRules(), AvoidDebugPrintRule()]);
  final findings = await engine.analyze(project);

  print(toSarifReport(findings));
}
