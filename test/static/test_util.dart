import 'dart:io';

import 'package:path/path.dart' as p;

final sampleAppRoot =
    p.join(Directory.current.path, 'test', 'fixtures', 'sample_app');

/// Locates [needle] on the first line of `lib/$relativeFile` that contains
/// it and returns its 1-based (line, column) — an oracle independent of the
/// engine's own line/column arithmetic.
///
/// [columnOf], if given, is a second substring to find *within that same
/// line* and report the column of instead — for when [needle] disambiguates
/// which line (e.g. distinguishing an inner `Scaffold(` from an outer one
/// via a `body: ` prefix) but the AST node the finding points to starts
/// partway through it.
(int, int) locate(
  String needle, {
  String relativeFile = 'main.dart',
  String? columnOf,
}) {
  final path = p.join(sampleAppRoot, 'lib', relativeFile);
  final lines = File(path).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains(needle)) continue;
    final col = lines[i].indexOf(columnOf ?? needle);
    if (col == -1) {
      throw StateError('"$columnOf" not found on the line containing '
          '"$needle" in $path');
    }
    return (i + 1, col + 1);
  }
  throw StateError('"$needle" not found in $path');
}
