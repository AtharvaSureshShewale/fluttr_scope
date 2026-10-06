import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:yaml/yaml.dart';

/// Which lines of the app's own code ran during a capture, from the Dart
/// VM's coverage report -- the signal that a static finding's code was
/// actually exercised, for *any* rule (a `setState` call, a `print`, a
/// widget constructor), not just widget creations the rebuild tracker
/// reports.
///
/// [hits] are lines that ran. [misses] are lines that were compiled but
/// never ran -- the report is requested with `forceCompile`, so code that
/// was never called still appears here rather than being absent. A line in
/// neither (a comment, a field without an initializer, a file the app never
/// imported) has no signal either way.
class ExecutedLines {
  final Map<String, Set<int>> hits;
  final Map<String, Set<int>> misses;

  const ExecutedLines({required this.hits, required this.misses});

  static const empty = ExecutedLines(hits: {}, misses: {});

  /// Whether the coverage report covers [file] at all.
  bool hasFile(String file) => hits.containsKey(file) || misses.containsKey(file);

  bool wasHit(String file, int line) => hits[file]?.contains(line) ?? false;

  bool wasMissed(String file, int line) => misses[file]?.contains(line) ?? false;

  /// Union across runs: a line that ran in *any* run ran; a line counts as
  /// missed only if no run hit it.
  ExecutedLines merge(ExecutedLines other) {
    final mergedHits = _union(hits, other.hits);
    final mergedMisses = _union(misses, other.misses);
    for (final entry in mergedMisses.entries) {
      entry.value.removeAll(mergedHits[entry.key] ?? const {});
    }
    return ExecutedLines(hits: mergedHits, misses: mergedMisses);
  }

  Map<String, Object?> toJson() => {
        'hits': {for (final e in hits.entries) e.key: (e.value.toList()..sort())},
        'misses': {for (final e in misses.entries) e.key: (e.value.toList()..sort())},
      };

  factory ExecutedLines.fromJson(Map<String, Object?> json) => ExecutedLines(
        hits: _linesFromJson(json['hits']),
        misses: _linesFromJson(json['misses']),
      );
}

Map<String, Set<int>> _union(Map<String, Set<int>> a, Map<String, Set<int>> b) => {
      for (final file in {...a.keys, ...b.keys}) file: {...?a[file], ...?b[file]},
    };

Map<String, Set<int>> _linesFromJson(Object? json) => {
      for (final e in ((json as Map<String, Object?>?) ?? const {}).entries)
        e.key: {...(e.value as List).cast<int>()},
    };

/// Reads the `name:` of the Flutter project at [root], which is what its
/// own libraries are imported as (`package:<name>/...`).
String? readPackageName(String root) {
  final file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final doc = loadYaml(file.readAsStringSync());
  return doc is YamlMap ? doc['name'] as String? : null;
}

/// Collects line coverage for the app's own libraries (`package:
/// [packageName]/...`), keyed by root-relative path (`lib/...`) -- the
/// same form static findings use.
Future<ExecutedLines> collectExecutedLines(
  VmService service,
  String isolateId, {
  required String packageName,
}) async {
  final report = await service.getSourceReport(
    isolateId,
    [SourceReportKind.kCoverage],
    forceCompile: true,
    reportLines: true,
    libraryFilters: ['package:$packageName/'],
  );

  final prefix = 'package:$packageName/';
  final scripts = report.scripts ?? const <ScriptRef>[];
  final hits = <String, Set<int>>{};
  final misses = <String, Set<int>>{};
  for (final range in report.ranges ?? const <SourceReportRange>[]) {
    final coverage = range.coverage;
    final index = range.scriptIndex;
    if (coverage == null || index == null || index >= scripts.length) continue;
    final uri = scripts[index].uri;
    if (uri == null || !uri.startsWith(prefix)) continue;
    final file = 'lib/${uri.substring(prefix.length)}';
    (hits[file] ??= {}).addAll(coverage.hits ?? const []);
    (misses[file] ??= {}).addAll(coverage.misses ?? const []);
  }
  // A line with several statements can be both hit and missed; it ran.
  for (final entry in misses.entries) {
    entry.value.removeAll(hits[entry.key] ?? const {});
  }
  return ExecutedLines(hits: hits, misses: misses);
}
