import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/finding.dart';

/// Default baseline file name, written at the analyzed project's root.
const defaultBaselineFileName = 'fluttr_scope_baseline.json';

/// Returns the source text of 1-based [line] in root-relative [file], or
/// `null` if it can't be read.
typedef LineTextReader = String? Function(String file, int line);

/// A snapshot of known findings, so a project with an existing backlog can
/// adopt fluttr_scope and fail only on *new* findings.
///
/// Findings are matched by rule id + file + message + the text of the
/// flagged line (whitespace-trimmed), *not* line number -- otherwise every
/// edit above a known finding would shift its line and resurface it as
/// "new". The line text is what tells apart two findings with the same
/// message in one file: without it, adding a second `setState`-after-
/// `await` would hide the new one and report the old one instead.
///
/// When a recorded line's text has since been edited, matching falls back
/// to counting by rule + file + message, so touching a known finding's line
/// doesn't resurface it either.
class Baseline {
  /// Count per (rule, file, message, line text). Line text is `''` for
  /// entries from a version-1 file, which recorded none.
  final Map<_Entry, int> _counts;

  Baseline._(this._counts);

  factory Baseline.fromFindings(List<Finding> findings, {LineTextReader? lineText}) {
    final counts = <_Entry, int>{};
    for (final f in findings) {
      final entry = _Entry.of(f, lineText);
      counts[entry] = (counts[entry] ?? 0) + 1;
    }
    return Baseline._(counts);
  }

  factory Baseline.fromJson(Map<String, Object?> json) {
    final counts = <_Entry, int>{};
    for (final raw in (json['entries'] as List? ?? const [])) {
      final e = raw as Map<String, Object?>;
      final entry = _Entry(
        e['ruleId'] as String,
        e['file'] as String,
        e['message'] as String,
        (e['lineText'] as String?) ?? '',
      );
      counts[entry] = (counts[entry] ?? 0) + (e['count'] as int);
    }
    return Baseline._(counts);
  }

  static Baseline load(String path) =>
      Baseline.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>);

  Future<void> save(String path) async {
    const encoder = JsonEncoder.withIndent('  ');
    final entries = _counts.keys.toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    await File(path).writeAsString(encoder.convert({
      'version': 2,
      'entries': [
        for (final e in entries) {...e.toJson(), 'count': _counts[e]},
      ],
    }));
  }

  /// [findings] minus those already recorded in this baseline. [lineText]
  /// must read the same project the findings came from.
  List<Finding> filterNew(List<Finding> findings, {LineTextReader? lineText}) {
    final remaining = Map.of(_counts);
    final entries = [for (final f in findings) _Entry.of(f, lineText)];

    // Pass 1: exact matches, line text included.
    final unmatched = <int>[];
    for (var i = 0; i < findings.length; i++) {
      if (!_consume(remaining, entries[i])) unmatched.add(i);
    }

    // Pass 2: whatever's left of the baseline for the same rule/file/
    // message covers findings whose line was edited since.
    final leftoverByLooseKey = <String, int>{};
    for (final e in remaining.entries) {
      if (e.value > 0) {
        leftoverByLooseKey[e.key.looseKey] = (leftoverByLooseKey[e.key.looseKey] ?? 0) + e.value;
      }
    }
    final reported = <int>{};
    for (final i in unmatched) {
      final key = entries[i].looseKey;
      final left = leftoverByLooseKey[key] ?? 0;
      if (left > 0) {
        leftoverByLooseKey[key] = left - 1;
      } else {
        reported.add(i);
      }
    }
    return [for (var i = 0; i < findings.length; i++) if (reported.contains(i)) findings[i]];
  }

  /// Returns true if [entry] was found (and used up) in [remaining].
  static bool _consume(Map<_Entry, int> remaining, _Entry entry) {
    final left = remaining[entry] ?? 0;
    if (left == 0) return false;
    remaining[entry] = left - 1;
    return true;
  }

  int get length => _counts.values.fold(0, (a, b) => a + b);
}

class _Entry {
  final String ruleId;
  final String file;
  final String message;
  final String lineText;

  const _Entry(this.ruleId, this.file, this.message, this.lineText);

  factory _Entry.of(Finding f, LineTextReader? lineText) => _Entry(
        f.ruleId,
        f.location.file,
        f.message,
        lineText?.call(f.location.file, f.location.line)?.trim() ?? '',
      );

  /// Rule + file + message, ignoring the line text.
  String get looseKey => '$ruleId\u0000$file\u0000$message';

  String get sortKey => '$looseKey\u0000$lineText';

  Map<String, Object?> toJson() => {
        'ruleId': ruleId,
        'file': file,
        'message': message,
        if (lineText.isNotEmpty) 'lineText': lineText,
      };

  @override
  bool operator ==(Object other) =>
      other is _Entry &&
      other.ruleId == ruleId &&
      other.file == file &&
      other.message == message &&
      other.lineText == lineText;

  @override
  int get hashCode => Object.hash(ruleId, file, message, lineText);
}

/// A [LineTextReader] over the project at [root], caching each file.
LineTextReader projectLineReader(String root) {
  final cache = <String, List<String>?>{};
  return (file, line) {
    final lines = cache.putIfAbsent(file, () {
      final f = File(p.join(root, file));
      return f.existsSync() ? f.readAsLinesSync() : null;
    });
    return lines != null && line >= 1 && line <= lines.length ? lines[line - 1] : null;
  };
}
