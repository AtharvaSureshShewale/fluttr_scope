import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';
import '../sensitive_names.dart';

/// Flags `Random()` (not `Random.secure()`) feeding a variable whose name
/// suggests security-sensitive use (a token, password, OTP, ...). Dart's
/// default `Random` is not cryptographically secure and is predictable.
///
/// Scope: only catches the direct-initializer case (`final xToken =
/// Random();`) — `Random()` passed through indirection before reaching a
/// sensitive-named variable isn't traced.
class InsecureRandomForSecretRule extends StaticRule {
  @override
  String get id => 'insecure_random_for_secret';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_RandomVisitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.warning,
        message: '`Random()` is not cryptographically secure. Use '
            '`Random.secure()` for anything security-sensitive (tokens, '
            'passwords, OTPs).',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _RandomVisitor extends RecursiveAstVisitor<void> {
  final void Function(InstanceCreationExpression node) onMatch;

  _RandomVisitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (creationTypeName(node) == 'Random' &&
        node.constructorName.name == null &&
        _hasSensitiveName(node)) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  bool _hasSensitiveName(InstanceCreationExpression node) {
    final parent = node.parent;
    if (parent is! VariableDeclaration) return false;
    return sensitiveNamePattern.hasMatch(parent.name.lexeme);
  }
}

/// Flags `javaScriptMode: JavaScriptMode.unrestricted` on a WebView. Any
/// page it loads can then run arbitrary JavaScript in that context.
class UnrestrictedWebviewJavascriptRule extends StaticRule {
  @override
  String get id => 'unrestricted_webview_javascript';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_JavascriptModeVisitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.warning,
        message: '`JavaScriptMode.unrestricted` lets any loaded page run '
            'arbitrary JavaScript. Restrict it unless the app fully '
            'controls and trusts every page it loads.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _JavascriptModeVisitor extends RecursiveAstVisitor<void> {
  final void Function(NamedExpression node) onMatch;

  _JavascriptModeVisitor(this.onMatch);

  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'javaScriptMode' &&
        node.expression.toSource().endsWith('.unrestricted')) {
      onMatch(node);
    }
    super.visitNamedExpression(node);
  }
}

/// Flags a `TextField`/`TextFormField` whose label/hint text suggests it's
/// a password field, but `obscureText` isn't set to `true` — the value
/// would render in plain text.
class TextfieldPasswordNotObscuredRule extends StaticRule {
  @override
  String get id => 'textfield_password_not_obscured';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.warning,
        message: 'This field\'s label suggests a password, but '
            '`obscureText` isn\'t set to `true` — the value will render '
            'in plain text.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(InstanceCreationExpression node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = creationTypeName(node);
    if ((typeName == 'TextField' || typeName == 'TextFormField') &&
        _looksLikePasswordField(node) &&
        _rendersPlainText(node)) {
      onMatch(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  bool _looksLikePasswordField(InstanceCreationExpression node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedExpression && arg.name.label.name == 'decoration') {
        return arg.expression.toSource().toLowerCase().contains('password');
      }
    }
    return false;
  }

  /// Flags only when `obscureText` is missing entirely, or set to the
  /// literal `false`. Any other expression (`_obscurePassword`, a ternary,
  /// ...) is presumed to be a deliberate show/hide-password toggle that
  /// this rule can't evaluate — flagging it would be a false positive
  /// against a common, legitimate pattern.
  bool _rendersPlainText(InstanceCreationExpression node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedExpression && arg.name.label.name == 'obscureText') {
        return arg.expression is BooleanLiteral && !(arg.expression as BooleanLiteral).value;
      }
    }
    return true;
  }
}
