/// Compares two `measure --runs N --format json` results: what got better,
/// what got worse, and what changed by less than the runs vary.
library;

/// Fewer runs than this on either side and nothing is called better or
/// worse: with 3 runs a side, "every after-run beat every before-run"
/// happens by chance 1 time in 10 (2 of the 20 ways to order 6 values);
/// with 2 a side, 1 in 3.
const minRunsToCompare = 3;

enum Change { better, worse, noClearChange, tooFewRuns }

/// One metric measured before and after, one value per valid run.
class MetricComparison {
  final String name;
  final String unit;
  final List<double> before;
  final List<double> after;

  const MetricComparison(this.name, this.unit, this.before, this.after);

  double get beforeMedian => _median(before);
  double get afterMedian => _median(after);

  /// Change in the median, as a percentage of before. `null` when before
  /// is 0 (no percentage of nothing).
  double? get percentChange =>
      beforeMedian == 0 ? null : (afterMedian - beforeMedian) / beforeMedian * 100;

  /// Lower is better for every metric compared. Better or worse only when
  /// the runs don't overlap at all: every after-run below (or above) every
  /// before-run. Anything less is within run-to-run noise.
  Change get change {
    if (before.length < minRunsToCompare || after.length < minRunsToCompare) {
      return Change.tooFewRuns;
    }
    final beforeMin = before.reduce((a, b) => a < b ? a : b);
    final beforeMax = before.reduce((a, b) => a > b ? a : b);
    final afterMin = after.reduce((a, b) => a < b ? a : b);
    final afterMax = after.reduce((a, b) => a > b ? a : b);
    if (afterMax < beforeMin) return Change.better;
    if (afterMin > beforeMax) return Change.worse;
    return Change.noClearChange;
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'unit': unit,
        'before': before,
        'after': after,
        'beforeMedian': beforeMedian,
        'afterMedian': afterMedian,
        'percentChange': percentChange,
        'change': change.name,
      };
}

class Comparison {
  /// Frame timing and total rebuilds.
  final List<MetricComparison> headline;

  /// Rebuilds per source file; empty if either result predates per-file
  /// data (fluttr_scope < 0.5.0).
  final List<MetricComparison> byFile;

  /// Reasons to trust the comparison less: different flows or devices,
  /// invalid runs, missing data.
  final List<String> warnings;

  final String beforeLabel;
  final String afterLabel;

  const Comparison({
    required this.headline,
    required this.byFile,
    required this.warnings,
    required this.beforeLabel,
    required this.afterLabel,
  });

  bool get hasRegression => headline.any((m) => m.change == Change.worse);

  Map<String, Object?> toJson() => {
        'before': beforeLabel,
        'after': afterLabel,
        'warnings': warnings,
        'headline': [for (final m in headline) m.toJson()],
        'byFile': [for (final m in byFile) m.toJson()],
      };
}

/// Thrown when a file isn't a multi-run `measure` JSON result.
class CompareInputException implements Exception {
  final String message;
  const CompareInputException(this.message);

  @override
  String toString() => message;
}

/// Compares [before] and [after], each the decoded JSON of
/// `fluttr_scope measure --runs N --format json`.
Comparison compareMeasurements(
  Map<String, Object?> before,
  Map<String, Object?> after, {
  String beforeLabel = 'before',
  String afterLabel = 'after',
}) {
  _checkShape(before, beforeLabel);
  _checkShape(after, afterLabel);

  final warnings = <String>[];
  final beforeFlow = before['flow'] as String?;
  final afterFlow = after['flow'] as String?;
  if (beforeFlow == null || afterFlow == null) {
    warnings.add('${beforeFlow == null && afterFlow == null ? 'Neither' : 'Only one'} '
        'measurement used a flow (--flow), so the runs may not have done the same things; '
        'differences can come from how the app was used rather than from your change.');
  } else if (beforeFlow != afterFlow) {
    warnings.add('The measurements used different flows ($beforeFlow, $afterFlow).');
  }
  final beforeDevice = _device(before);
  final afterDevice = _device(after);
  if (beforeDevice != null && afterDevice != null && beforeDevice != afterDevice) {
    warnings.add('Measured on different devices ($beforeDevice, $afterDevice): '
        'frame timings are not comparable.');
  }
  for (final (json, label) in [(before, beforeLabel), (after, afterLabel)]) {
    final invalid = (json['invalidRuns'] as List?)?.length ?? 0;
    if (invalid > 0) {
      warnings.add('$label: $invalid run(s) were invalid and left out.');
    }
  }

  final headline = <MetricComparison>[
    for (final (key, name, unit) in const [
      ('overBudgetPercent', 'Frames over budget', '%'),
      ('slowestSteadyStateFrameMs', 'Slowest frame', 'ms'),
      ('jankClusterCount', 'Jank clusters', ''),
    ])
      if (_values(before, key) case final b?)
        if (_values(after, key) case final a?) MetricComparison(name, unit, b, a),
  ];

  final beforeRebuilds = _intList(before['rebuildsPerRun']);
  final afterRebuilds = _intList(after['rebuildsPerRun']);
  final byFile = <MetricComparison>[];
  if (beforeRebuilds == null || afterRebuilds == null) {
    warnings.add('Rebuild counts are missing from '
        '${beforeRebuilds == null ? beforeLabel : afterLabel} (measured with fluttr_scope '
        'before 0.5.0); comparing frame timing only.');
  } else {
    headline.add(MetricComparison('Rebuilds (after warm-up)', '', beforeRebuilds, afterRebuilds));
    final beforeFiles = _filesPerRun(before);
    final afterFiles = _filesPerRun(after);
    for (final file in {...beforeFiles.keys, ...afterFiles.keys}) {
      byFile.add(MetricComparison(
        file,
        '',
        beforeFiles[file] ?? List.filled(beforeRebuilds.length, 0),
        afterFiles[file] ?? List.filled(afterRebuilds.length, 0),
      ));
    }
    byFile.sort((a, b) => (b.afterMedian - b.beforeMedian)
        .abs()
        .compareTo((a.afterMedian - a.beforeMedian).abs()));
  }

  return Comparison(
    headline: headline,
    byFile: byFile,
    warnings: warnings,
    beforeLabel: beforeLabel,
    afterLabel: afterLabel,
  );
}

void _checkShape(Map<String, Object?> json, String label) {
  if (!json.containsKey('validRunCount') || !json.containsKey('overBudgetPercent')) {
    throw CompareInputException(
      '$label is not a multi-run measurement. Create one with: '
      'fluttr_scope measure --runs 3 --format json --out $label',
    );
  }
  if (json['validRunCount'] == 0) {
    throw CompareInputException('$label has no valid runs to compare.');
  }
}

String? _device(Map<String, Object?> json) =>
    (json['environment'] as Map<String, Object?>?)?['device'] as String?;

List<double>? _values(Map<String, Object?> json, String key) {
  final stats = json[key] as Map<String, Object?>?;
  final values = stats?['values'] as List?;
  return values == null ? null : [for (final v in values) (v as num).toDouble()];
}

List<double>? _intList(Object? list) =>
    list is List ? [for (final v in list) (v as num).toDouble()] : null;

Map<String, List<double>> _filesPerRun(Map<String, Object?> json) {
  final byFile = json['rebuildsByFilePerRun'] as Map<String, Object?>? ?? const {};
  final result = <String, List<double>>{};
  for (final MapEntry(:key, :value) in byFile.entries) {
    final counts = _intList(value) ?? const <double>[];
    final name = displayPath(key);
    final existing = result[name];
    result[name] = existing == null
        ? counts
        : [for (var i = 0; i < counts.length; i++) existing[i] + counts[i]];
  }
  return result;
}

final _packageFile = RegExp(r'(?:^|/)([A-Za-z_][A-Za-z0-9_]*)(?:-[0-9][^/]*)?/lib/(.+)$');

/// [path] as the user would recognise it: a file outside the project
/// (`../../AppData/Local/Pub/Cache/hosted/pub.dev/provider-6.1.5/lib/src/x.dart`,
/// or the Flutter SDK's `packages/flutter/lib/...`) as a `package:` URI,
/// which also keeps the machine's own paths (user name) out of reports.
String displayPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  if (!normalized.startsWith('../') && !normalized.startsWith('/') && !normalized.contains(':/')) {
    return normalized;
  }
  final match = _packageFile.firstMatch(normalized);
  return match == null ? normalized : 'package:${match[1]}/${match[2]}';
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// The console report for [comparison]. Shows at most [maxFiles] files.
String formatComparison(Comparison comparison, {int maxFiles = 10}) {
  final buffer = StringBuffer();
  buffer.writeln('BEFORE vs AFTER');
  buffer.writeln('-' * 15);
  buffer.writeln('${comparison.beforeLabel} -> ${comparison.afterLabel}');
  for (final warning in comparison.warnings) {
    buffer.writeln('⚠ $warning');
  }
  buffer.writeln();

  final nameWidth = comparison.headline.fold(6, (w, m) => m.name.length > w ? m.name.length : w);
  buffer.writeln('${'Metric'.padRight(nameWidth)}  ${'Before'.padLeft(10)}  ${'After'.padLeft(10)}  Change');
  for (final m in comparison.headline) {
    buffer.writeln('${m.name.padRight(nameWidth)}  '
        '${_number(m.beforeMedian, m.unit).padLeft(10)}  '
        '${_number(m.afterMedian, m.unit).padLeft(10)}  '
        '${_describe(m)}');
  }
  buffer.writeln('(medians across runs)');

  final changed = comparison.byFile
      .where((m) => m.change == Change.better || m.change == Change.worse)
      .toList();
  if (comparison.byFile.isNotEmpty) {
    buffer.writeln();
    if (changed.isEmpty) {
      buffer.writeln('No file\'s rebuild count changed by more than its runs vary.');
    } else {
      buffer.writeln('REBUILDS BY FILE (changed by more than the runs vary)');
      for (final m in changed.take(maxFiles)) {
        buffer.writeln('  ${m.change == Change.better ? '✅' : '❌'} ${m.name}  '
            '${_number(m.beforeMedian, '')} -> ${_number(m.afterMedian, '')}'
            '${m.percentChange == null ? '' : '  (${_signed(m.percentChange!)}%)'}');
      }
      if (changed.length > maxFiles) {
        buffer.writeln('  ... and ${changed.length - maxFiles} more (see --format json)');
      }
    }
  }

  buffer.writeln();
  buffer.writeln('"Better" or "worse" means every run after beat (or lost to) every run '
      'before. Anything else is reported as no clear change: it could be noise.');
  final runCounts = [for (final m in comparison.headline) ...[m.before.length, m.after.length]];
  if (runCounts.isNotEmpty && runCounts.reduce((a, b) => a < b ? a : b) == minRunsToCompare) {
    buffer.writeln('With $minRunsToCompare runs a side, about 1 in 10 metrics that did not '
        'really change still splits cleanly by chance: re-measure a surprising result, '
        'or use --runs 5 (under 1 in 100).');
  } else {
    buffer.writeln('More runs make smaller changes detectable.');
  }
  return buffer.toString();
}

String _describe(MetricComparison m) {
  final pct = m.percentChange == null ? '' : ' (${_signed(m.percentChange!)}%)';
  return switch (m.change) {
    Change.better => '✅ better$pct',
    Change.worse => '❌ worse$pct',
    Change.noClearChange => 'no clear change$pct',
    Change.tooFewRuns => 'too few runs to tell (need $minRunsToCompare+ each)',
  };
}

String _signed(double pct) => '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}';

String _number(double value, String unit) {
  final text = value == value.roundToDouble()
      ? _grouped(value.round())
      : value.toStringAsFixed(1);
  return unit.isEmpty ? text : unit == '%' ? '$text%' : '$text $unit';
}

String _grouped(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}
