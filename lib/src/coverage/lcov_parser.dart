import 'file_coverage.dart';

/// Parses the LCOV format `flutter test --coverage` writes to
/// `coverage/lcov.info`: one `SF:`/`end_of_record` block per file, with a
/// `DA:<line>,<hitCount>` entry per instrumented line.
List<FileCoverage> parseLcov(String content) {
  final files = <FileCoverage>[];

  String? currentFile;
  var uncovered = <int>[];
  var linesFound = 0;
  var linesHit = 0;

  for (final rawLine in content.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3).replaceAll('\\', '/');
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (int.parse(parts[1]) == 0) uncovered.add(int.parse(parts[0]));
    } else if (line.startsWith('LF:')) {
      linesFound = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      linesHit = int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      if (currentFile != null) {
        files.add(FileCoverage(
          file: currentFile,
          linesFound: linesFound,
          linesHit: linesHit,
          uncoveredLines: uncovered,
        ));
      }
      currentFile = null;
      uncovered = [];
      linesFound = 0;
      linesHit = 0;
    }
  }

  return files;
}
