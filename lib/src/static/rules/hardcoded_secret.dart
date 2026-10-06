import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

/// Well-known secret shapes, matched against string literal contents.
///
/// Deliberately narrow: only structurally distinctive prefixes (AWS,
/// Google, Stripe, GitHub, Slack) are matched, so a hit is essentially
/// never a false positive — unlike a generic "assigned to a variable
/// named apiKey" heuristic, which flags header names and placeholder
/// strings just as often as real secrets.
const secretPatterns = <String, String>{
  'AWS access key': r'AKIA[0-9A-Z]{16,}',
  'Google API key': r'AIza[0-9A-Za-z\-_]{35,}',
  'Stripe live key': r'sk_live_[0-9a-zA-Z]{20,}',
  'GitHub token': r'gh[pousr]_[A-Za-z0-9]{36,}',
  'Slack token': r'xox[baprs]-[0-9A-Za-z-]{10,}',
};

final _compiledPatterns = secretPatterns.map((k, v) => MapEntry(k, RegExp(v)));

/// Returns the label of the first secret pattern [value] matches, or
/// `null` if it matches none.
String? matchSecretPattern(String value) {
  for (final entry in _compiledPatterns.entries) {
    if (entry.value.hasMatch(value)) return entry.key;
  }
  return null;
}

class HardcodedSecretRule extends StaticRule {
  @override
  String get id => 'hardcoded_secret';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node, label) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.error,
        message: 'This looks like a hardcoded $label. Move it to a secure '
            'secret store or environment configuration, not source control.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(SimpleStringLiteral node, String label) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final label = matchSecretPattern(node.value);
    if (label != null) onMatch(node, label);
    super.visitSimpleStringLiteral(node);
  }
}
