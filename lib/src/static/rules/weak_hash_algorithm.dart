import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

const _weakHashTargets = {'md5', 'sha1'};

/// Flags `package:crypto`'s `md5.convert(...)`/`sha1.convert(...)`. Both
/// are cryptographically broken for security purposes (collision
/// attacks). Fine for a non-security checksum (e.g. a cache key), which
/// is why this is `info`, not a hard error — but it's worth a second
/// look wherever it's actually protecting something.
///
/// Matched by identifier name (`md5`/`sha1`) + `.convert(...)`, not by
/// resolving the receiver's type, so `package:crypto` doesn't need to be
/// a resolvable dependency for this rule to fire.
class WeakHashAlgorithmRule extends StaticRule {
  @override
  String get id => 'weak_hash_algorithm';

  @override
  Category get category => Category.security;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node, name) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.info,
        message: '`$name` is cryptographically broken. Fine for a '
            'non-security checksum, but don\'t use it for passwords, '
            'signatures, or anything security-sensitive — use sha256 or '
            'stronger.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation node, String name) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target is SimpleIdentifier &&
        _weakHashTargets.contains(target.name) &&
        node.methodName.name == 'convert') {
      onMatch(node, target.name);
    }
    super.visitMethodInvocation(node);
  }
}
