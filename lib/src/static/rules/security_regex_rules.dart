import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../flutter_ast.dart';
import '../rule.dart';

/// Dev-only hosts: loopback, the Android emulator's host alias, private
/// LAN ranges (a phone on Wi-Fi reaching a laptop's dev server), and mDNS
/// `.local` names. Cleartext to these doesn't cross the internet.
final _localHosts = RegExp(
  r'^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.\d+\.\d+\.\d+'
  r'|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|\[::1\]|[\w.-]+\.local)([:/?#]|$)',
);

/// A URL with an actual host -- not the bare scheme `'http://'`, which is
/// usually a prefix check (`url.startsWith('http://')`), not a request.
final _httpUrl = RegExp(r'^http://[\w\[]');

/// Flags a hardcoded `http://` URL (cleartext, not `https://`) that isn't
/// pointed at a local dev host. Traffic over it can be intercepted or
/// tampered with in transit.
class InsecureHttpUrlRule extends StaticRule {
  @override
  String get id => 'insecure_http_url';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_StringVisitor((node, value) {
      if (_httpUrl.hasMatch(value) && !_localHosts.hasMatch(value)) {
        findings.add(Finding(
          ruleId: id,
          category: Category.security,
          severity: Severity.warning,
          message: 'Cleartext `http://` URL. Traffic over this can be '
              'intercepted or tampered with — use `https://`.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

final _sensitiveQueryParam =
    RegExp(r'[?&](token|password|passwd|api[_-]?key|secret|auth)=', caseSensitive: false);

/// Flags a URL string with a sensitive value (token, password, API key)
/// passed as a query parameter. Query strings routinely end up in server
/// access logs, browser history, and `Referer` headers — that's true even
/// over `https://`, since only the connection is encrypted, not where the
/// URL itself gets logged afterward.
class SensitiveQueryParamRule extends StaticRule {
  @override
  String get id => 'sensitive_query_param';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_StringVisitor((node, value) {
      if (_sensitiveQueryParam.hasMatch(value)) {
        findings.add(Finding(
          ruleId: id,
          category: Category.security,
          severity: Severity.warning,
          message: 'A sensitive value appears to be passed as a URL query '
              'parameter. Query strings are routinely logged (servers, '
              'proxies, browser history) even over HTTPS — send it in the '
              'request body or a header instead.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

final _ipAddress = RegExp(r'^(?!127\.0\.0\.1$|0\.0\.0\.0$)(\d{1,3}\.){3}\d{1,3}$');

/// Flags a hardcoded (non-loopback) IP address literal — usually a sign a
/// server endpoint is hardcoded instead of configured per environment.
class HardcodedIpAddressRule extends StaticRule {
  @override
  String get id => 'hardcoded_ip_address';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_StringVisitor((node, value) {
      if (_ipAddress.hasMatch(value)) {
        findings.add(Finding(
          ruleId: id,
          category: Category.security,
          severity: Severity.info,
          message: 'Hardcoded IP address. Likely a server endpoint that '
              'should come from build-time or runtime configuration '
              'instead of source.',
          location: locationOf(unit, node, context),
        ));
      }
    }));
    return findings;
  }
}

class _StringVisitor extends RecursiveAstVisitor<void> {
  final void Function(SimpleStringLiteral node, String value) onLiteral;

  _StringVisitor(this.onLiteral);

  static const _replaceMethods = {
    'replaceAll',
    'replaceAllMapped',
    'replaceFirst',
    'replaceFirstMapped',
  };

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!_isPartOfRegexRedaction(node)) onLiteral(node, node.value);
    super.visitSimpleStringLiteral(node);
  }

  /// True when [node] sits anywhere inside a `str.replaceAll(RegExp(...),
  /// ...)`-shaped call (any of Dart's four replace* methods paired with a
  /// `RegExp` pattern argument) — covers both the pattern string itself
  /// (`RegExp(r'[?&]token=...')`) and a same-shaped replacement string
  /// (`'?token=***'`), a common redaction idiom. Neither is an actual
  /// URL/IP/token; it's *code describing* what one looks like.
  bool _isPartOfRegexRedaction(SimpleStringLiteral node) {
    for (AstNode? current = node.parent; current != null; current = current.parent) {
      if (current is MethodDeclaration || current is FunctionDeclaration) return false;
      if (current is! MethodInvocation || !_replaceMethods.contains(current.methodName.name)) {
        continue;
      }
      return current.argumentList.arguments
          .any((a) => a is InstanceCreationExpression && creationTypeName(a) == 'RegExp');
    }
    return false;
  }
}
