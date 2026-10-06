import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';
import '../sensitive_names.dart';

const _sharedPreferencesSetters = {'setString', 'setInt', 'setBool', 'setDouble', 'setStringList'};

/// Flags a `SharedPreferences.set*` call whose key looks sensitive.
/// `SharedPreferences` is not encrypted at rest (plain XML on Android,
/// a plist on iOS) — a token or password stored there is readable by
/// anything with access to the device's app-data directory (a rooted
/// device, a backup, physical access). Use `flutter_secure_storage`
/// instead, which backs onto Keychain/Keystore.
class InsecureStorageOfSensitiveDataRule extends StaticRule {
  @override
  String get id => 'insecure_storage_of_sensitive_data';

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    unit.unit.accept(_Visitor((node) {
      findings.add(Finding(
        ruleId: id,
        category: Category.security,
        severity: Severity.warning,
        message: 'Storing what looks like a sensitive value in '
            'SharedPreferences, which is not encrypted at rest. Use '
            '`flutter_secure_storage` instead.',
        location: locationOf(unit, node, context),
      ));
    }));
    return findings;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final void Function(MethodInvocation node) onMatch;

  _Visitor(this.onMatch);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_sharedPreferencesSetters.contains(node.methodName.name) &&
        node.argumentList.arguments.isNotEmpty &&
        _isSharedPreferences(node.target) &&
        _hasSensitiveKey(node.argumentList.arguments.first)) {
      onMatch(node);
    }
    super.visitMethodInvocation(node);
  }

  bool _isSharedPreferences(Expression? target) {
    final type = target?.staticType;
    return type is InterfaceType && type.element3.name3 == 'SharedPreferences';
  }

  bool _hasSensitiveKey(Expression keyArg) {
    if (keyArg is! SimpleStringLiteral) return false;
    return sensitiveNamePattern.hasMatch(keyArg.value);
  }
}
