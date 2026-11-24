import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

import '../model/finding.dart';

/// The fixes for one file: its text before and after, and which findings
/// they fix.
class FileFix {
  /// Root-relative, as in [Finding.location].
  final String file;
  final String before;
  final String after;
  final List<Finding> fixed;

  /// Edits applied, in [before]'s offsets, sorted by offset.
  final List<SourceEdit> edits;

  const FileFix({
    required this.file,
    required this.before,
    required this.after,
    required this.fixed,
    required this.edits,
  });
}

/// A file whose fixes weren't applied, and why.
class SkippedFile {
  final String file;
  final int fixCount;
  final String reason;

  const SkippedFile(this.file, this.fixCount, this.reason);
}

class FixPlan {
  final List<FileFix> files;
  final List<SkippedFile> skipped;

  const FixPlan(this.files, this.skipped);

  int get fixCount => files.fold(0, (sum, f) => sum + f.fixed.length);
}

/// Works out the fixes for every finding in [findings] that has edits,
/// without writing anything.
///
/// Every changed file is analyzed again with its fixes applied: if that
/// adds a compile error, none of that file's fixes are used. Fixes whose
/// edits overlap one already taken in the same file are left for a later
/// run.
Future<FixPlan> planFixes(String rootPath, List<Finding> findings) async {
  final root = p.normalize(p.absolute(rootPath));
  final byFile = <String, List<Finding>>{};
  for (final finding in findings) {
    if (finding.fix?.edits.isNotEmpty ?? false) {
      byFile.putIfAbsent(finding.location.file, () => []).add(finding);
    }
  }

  final candidates = <FileFix>[];
  for (final MapEntry(key: file, value: fixable) in byFile.entries) {
    final path = p.normalize(p.join(root, file));
    final before = await File(path).readAsString();
    fixable.sort((a, b) => a.fix!.edits.first.offset.compareTo(b.fix!.edits.first.offset));
    final taken = <SourceEdit>[];
    final fixed = <Finding>[];
    for (final finding in fixable) {
      final edits = finding.fix!.edits;
      if (edits.any((e) => e.end > before.length)) continue; // file changed since analysis
      if (edits.any((e) => taken.any((t) => _overlaps(e, t)))) continue;
      taken.addAll(edits);
      fixed.add(finding);
    }
    taken.sort((a, b) => a.offset.compareTo(b.offset));
    candidates.add(FileFix(
      file: file,
      before: before,
      after: applyEdits(before, taken),
      fixed: fixed,
      edits: taken,
    ));
  }
  if (candidates.isEmpty) return const FixPlan([], []);

  final paths = {for (final c in candidates) p.normalize(p.join(root, c.file))};
  final errorsBefore = await _compileErrors(root, paths, const {});
  final errorsAfter = await _compileErrors(root, paths, {
    for (final c in candidates) p.normalize(p.join(root, c.file)): c.after,
  });

  final files = <FileFix>[];
  final skipped = <SkippedFile>[];
  for (final candidate in candidates) {
    final path = p.normalize(p.join(root, candidate.file));
    final added = (errorsAfter[path] ?? 0) - (errorsBefore[path] ?? 0);
    if (added > 0) {
      skipped.add(SkippedFile(
        candidate.file,
        candidate.fixed.length,
        'the fixes would add $added compile error(s); fix this file by hand',
      ));
    } else {
      files.add(candidate);
    }
  }
  return FixPlan(files, skipped);
}

/// Writes every file in [plan].
Future<void> writeFixes(String rootPath, FixPlan plan) async {
  for (final file in plan.files) {
    await File(p.join(rootPath, file.file)).writeAsString(file.after);
  }
}

/// [text] with [edits] applied. [edits] mustn't overlap.
String applyEdits(String text, List<SourceEdit> edits) {
  final sorted = [...edits]..sort((a, b) => b.offset.compareTo(a.offset));
  var result = text;
  for (final e in sorted) {
    result = result.replaceRange(e.offset, e.end, e.replacement);
  }
  return result;
}

/// Overlapping, or both inserting at the same place (whose order would be
/// arbitrary).
bool _overlaps(SourceEdit a, SourceEdit b) =>
    (a.offset < b.end && b.offset < a.end) || a.offset == b.offset;

/// The number of compile errors in each of [paths], with the text of the
/// files in [overlays] replaced by their new contents.
Future<Map<String, int>> _compileErrors(
  String root,
  Set<String> paths,
  Map<String, String> overlays,
) async {
  final provider = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  for (final MapEntry(key: path, value: content) in overlays.entries) {
    provider.setOverlay(path, content: content, modificationStamp: stamp);
  }
  final collection = AnalysisContextCollection(includedPaths: [root], resourceProvider: provider);
  final counts = <String, int>{};
  try {
    for (final context in collection.contexts) {
      for (final path in context.contextRoot.analyzedFiles()) {
        if (!paths.contains(path)) continue;
        final result = await context.currentSession.getResolvedUnit(path);
        if (result is! ResolvedUnitResult) continue;
        counts[path] = result.diagnostics
            .where((d) => d.diagnosticCode.severity == DiagnosticSeverity.ERROR)
            .length;
      }
    }
  } finally {
    await collection.dispose();
  }
  return counts;
}

/// A readable diff of [fix]: each changed line range, before (`-`) and
/// after (`+`), headed by `file:line`.
String describeFileFix(FileFix fix) {
  final text = fix.before;
  final lineStarts = [0, for (var i = 0; i < text.length; i++) if (text[i] == '\n') i + 1];
  int lineOf(int offset) {
    var lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int lineEnd(int line) {
    if (line + 1 >= lineStarts.length) return text.length;
    var end = lineStarts[line + 1] - 1; // the '\n'
    if (end > 0 && text[end - 1] == '\r') end--;
    return end;
  }

  // Group edits whose line ranges touch, so a line edited twice is shown once.
  final groups = <(int, int, List<SourceEdit>)>[];
  for (final edit in fix.edits) {
    final first = lineOf(edit.offset);
    final last = lineOf(edit.end);
    if (groups.isNotEmpty && first <= groups.last.$2) {
      final (start, end, edits) = groups.removeLast();
      groups.add((start, last > end ? last : end, [...edits, edit]));
    } else {
      groups.add((first, last, [edit]));
    }
  }

  final buffer = StringBuffer();
  for (final (first, last, edits) in groups) {
    final from = lineStarts[first];
    final to = lineEnd(last);
    final old = text.substring(from, to);
    final shifted = [
      for (final e in edits)
        SourceEdit(offset: e.offset - from, length: e.length, replacement: e.replacement),
    ];
    final updated = applyEdits(old, shifted);
    buffer.writeln('${fix.file}:${first + 1}');
    for (final line in old.split(RegExp(r'\r?\n'))) {
      buffer.writeln('- $line');
    }
    for (final line in updated.split(RegExp(r'\r?\n'))) {
      buffer.writeln('+ $line');
    }
  }
  return buffer.toString();
}
