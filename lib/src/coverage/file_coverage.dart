/// Line coverage for a single source file, as recorded in an LCOV report.
class FileCoverage {
  final String file;
  final int linesFound;
  final int linesHit;
  final List<int> uncoveredLines;

  const FileCoverage({
    required this.file,
    required this.linesFound,
    required this.linesHit,
    required this.uncoveredLines,
  });

  double get percentage =>
      linesFound == 0 ? 100.0 : (linesHit / linesFound) * 100;

  Map<String, Object?> toJson() => {
        'file': file,
        'linesFound': linesFound,
        'linesHit': linesHit,
        'percentage': double.parse(percentage.toStringAsFixed(1)),
        'uncoveredLines': uncoveredLines,
      };
}
