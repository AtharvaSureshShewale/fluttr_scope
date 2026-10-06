import 'dart:convert';
import 'dart:io';

import '../model/finding.dart';

/// Default baseline file name, written at the analyzed project's root.
const defaultBaselineFileName = 'fluttr_scope_baseline.json';

/// A snapshot of known findings, so a project with an existing backlog can
/// adopt fluttr_scope and fail only on *new* findings.
///
/// Findings are matched by rule id + file + message, *not* line number --
/// otherwise every edit above a known finding would shift its line and
/// resurface it as "new". Matching is by count: if a file had 3
/// `avoid_print` findings when the baseline was written, the first 3 are
/// hidden and a 4th is reported.
class Baseline {
  final Map<String, int> _counts;

  Baseline._(this._counts);

  factory Baseline.fromFindings(List<Finding> findings) {
    final counts = <String, int>{};
    for (final f in findings) {
      final key = _key(f.ruleId, f.location.file, f.message);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Baseline._(counts);
  }

  factory Baseline.fromJson(Map<String, Object?> json) {
    final counts = <String, int>{};
    for (final entry in (json['entries'] as List? ?? const [])) {
      final e = entry as Map<String, Object?>;
      counts[_key(e['ruleId'] as String, e['file'] as String, e['message'] as String)] =
          e['count'] as int;
    }
    return Baseline._(counts);
  }

  static Baseline load(String path) =>
      Baseline.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>);

  Future<void> save(String path) async {
    const encoder = JsonEncoder.withIndent('  ');
    final keys = _counts.keys.toList()..sort();
    await File(path).writeAsString(encoder.convert({
      'version': 1,
      'entries': [
        for (final key in keys)
          {
            ..._unkey(key),
            'count': _counts[key],
          },
      ],
    }));
  }

  /// [findings] minus those already recorded in this baseline.
  List<Finding> filterNew(List<Finding> findings) {
    final remaining = Map.of(_counts);
    return [
      for (final f in findings)
        if (_consume(remaining, _key(f.ruleId, f.location.file, f.message))) f,
    ];
  }

  /// Returns true if [key] should be reported (not covered by the baseline).
  static bool _consume(Map<String, int> remaining, String key) {
    final left = remaining[key] ?? 0;
    if (left == 0) return true;
    remaining[key] = left - 1;
    return false;
  }

  int get length => _counts.values.fold(0, (a, b) => a + b);
}

// \u0000 can't appear in a rule id, path, or message, so it's a safe
// separator for a composite key.
String _key(String ruleId, String file, String message) => '$ruleId\u0000$file\u0000$message';

Map<String, String> _unkey(String key) {
  final parts = key.split('\u0000');
  return {'ruleId': parts[0], 'file': parts[1], 'message': parts[2]};
}
