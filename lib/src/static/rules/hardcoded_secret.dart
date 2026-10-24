import 'dart:math';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

/// Well-known secret shapes, matched against string literal contents.
///
/// Only structurally distinctive prefixes (AWS, Google, Stripe, GitHub,
/// Slack) are matched here, so a hit is essentially never a false
/// positive. Secrets without a distinctive shape are caught separately by
/// name *and* value (see [looksLikeSecretValue]): a name alone would flag
/// key names, labels, and placeholders just as often as real secrets.
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
  Category get category => Category.security;

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

  // Provider-specific shapes above can't recognise most real secrets (an
  // OAuth client secret, a private API's key), so also flag a literal
  // given to a secret-*named* variable or argument when the value itself
  // looks like a real secret rather than a key name, label, or placeholder.

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _checkNamedValue(node.name.lexeme, node.initializer);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    _checkNamedValue(node.name.label.name, node.expression);
    super.visitNamedExpression(node);
  }

  void _checkNamedValue(String name, Expression? value) {
    if (value is! SimpleStringLiteral) return;
    if (matchSecretPattern(value.value) != null) return; // already reported
    if (secretNamePattern.hasMatch(name) && looksLikeSecretValue(value.value)) {
      onMatch(value, 'secret assigned to `$name`');
    }
  }
}

/// Names a hardcoded secret is typically stored under.
final secretNamePattern = RegExp(
  r'(secret|password|passwd|api[_-]?key|private[_-]?key|access[_-]?key|token|credential)',
  caseSensitive: false,
);

final _placeholder = RegExp(
  r'(your|xxx|example|placeholder|changeme|replace|dummy|sample|todo|<|>|\*\*\*)',
  caseSensitive: false,
);

/// Whether [value] looks like an actual secret rather than a key name
/// (`'access_token'`), a label, a URL, or a placeholder
/// (`'YOUR_API_KEY_HERE'`): long, no spaces, letters *and* digits, and
/// close to random (Shannon entropy of at least 3 bits per character).
bool looksLikeSecretValue(String value) {
  if (value.length < 16 || value.length > 512) return false;
  if (value.contains(RegExp(r'\s')) || value.contains('://')) return false;
  if (_placeholder.hasMatch(value)) return false;
  if (!value.contains(RegExp(r'[0-9]')) || !value.contains(RegExp(r'[A-Za-z]'))) return false;
  return _entropyBitsPerChar(value) >= 3.0;
}

double _entropyBitsPerChar(String value) {
  final counts = <int, int>{};
  for (final c in value.codeUnits) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  var entropy = 0.0;
  for (final n in counts.values) {
    final p = n / value.length;
    entropy -= p * log(p) / ln2;
  }
  return entropy;
}
