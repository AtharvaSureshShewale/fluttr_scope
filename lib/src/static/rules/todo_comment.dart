import 'package:analyzer/dart/analysis/results.dart';

import '../../model/category.dart';
import '../../model/finding.dart';
import '../../model/severity.dart';
import '../rule.dart';

final _pattern = RegExp(r'(TODO|FIXME)\b');

/// Flags an unresolved `TODO`/`FIXME` comment. Works directly on the raw
/// source text rather than the AST — comments aren't part of the AST's
/// node structure — so it's the one rule in this set that doesn't accept
/// or reject any particular code shape, just a text pattern.
class TodoCommentRule extends StaticRule {
  @override
  String get id => 'todo_comment';

  @override
  Category get category => Category.style;

  @override
  List<Finding> check(ResolvedUnitResult unit, RuleContext context) {
    final findings = <Finding>[];
    final lines = unit.content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = _pattern.firstMatch(lines[i]);
      if (match == null) continue;
      findings.add(Finding(
        ruleId: id,
        category: Category.style,
        severity: Severity.info,
        message: 'Unresolved ${match.group(1)} comment.',
        location: locationAt(
          unit,
          context,
          line: i + 1,
          column: match.start + 1,
          length: match.group(0)!.length,
        ),
      ));
    }
    return findings;
  }
}
