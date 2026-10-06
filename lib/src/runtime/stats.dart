import 'dart:math';

/// How much a metric's per-run values can be trusted, derived from actual
/// run-to-run variability -- never assigned by guesswork.
enum Confidence { high, medium, low }

/// Descriptive statistics for one metric measured across multiple runs.
///
/// [values] preserves the original per-run order (run #1 first) so callers
/// can print a "Runs: #1 ... #2 ..." listing; every other field is derived
/// from a sorted copy.
class Stats {
  final List<double> values;
  final double median;
  final double mean;
  final double min;
  final double max;
  final double stdDev;

  /// stdDev / mean -- the standard relative-variability measure, used to
  /// derive [confidence]. `0` when [mean] is `0` (nothing to divide by,
  /// and a mean of exactly zero across every run is itself maximally
  /// stable).
  final double coefficientOfVariation;

  final Confidence confidence;

  const Stats({
    required this.values,
    required this.median,
    required this.mean,
    required this.min,
    required this.max,
    required this.stdDev,
    required this.coefficientOfVariation,
    required this.confidence,
  });

  /// `true` when [confidence] is anything other than [Confidence.high] --
  /// i.e. this metric should carry an explicit "don't trust this for a CI
  /// gate yet" warning in reports.
  bool get isUnstable => confidence != Confidence.high;
}

/// Confidence thresholds -- stated explicitly as a judgment call, not a
/// derived scientific standard, per this project's convention for
/// proposed rubrics (see [FrameSeverity] in `frame_budget.dart` for the
/// same treatment). Coefficient of variation is the standard relative-
/// variability measure; <=10% is treated as tight enough to trust, 10-25%
/// as noticeable but usable with care, and above that as too noisy to act
/// on without investigating the variance source first.
///
/// A sample of fewer than 2 runs cannot have its variability estimated at
/// all -- a single run trivially has zero spread, so reporting HIGH from
/// one data point would be a fabricated confidence, not a derived one.
/// [sampleSize] < 2 is therefore always [Confidence.low], regardless of
/// [coefficientOfVariation].
Confidence classifyConfidence({
  required double coefficientOfVariation,
  required int sampleSize,
}) {
  if (sampleSize < 2) return Confidence.low;
  if (coefficientOfVariation <= 0.10) return Confidence.high;
  if (coefficientOfVariation <= 0.25) return Confidence.medium;
  return Confidence.low;
}

/// Computes [Stats] for [values], one entry per run, in run order.
///
/// Standard deviation uses the sample formula (dividing by `n - 1`, not
/// `n`) since these runs are a sample used to estimate the variability of
/// an underlying (noisy) process, not the entire population of possible
/// runs -- the conventional choice for this kind of measurement.
Stats computeStats(List<double> values) {
  if (values.isEmpty) {
    throw ArgumentError('computeStats requires at least one value');
  }

  final n = values.length;
  final sorted = [...values]..sort();
  final mean = sorted.reduce((a, b) => a + b) / n;
  final median = n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;

  double stdDev = 0;
  if (n >= 2) {
    final sumSquaredDiffs = sorted.fold<double>(0, (sum, v) => sum + pow(v - mean, 2));
    stdDev = sqrt(sumSquaredDiffs / (n - 1));
  }

  final coefficientOfVariation = mean == 0 ? 0.0 : stdDev / mean;

  return Stats(
    values: values,
    median: median,
    mean: mean,
    min: sorted.first,
    max: sorted.last,
    stdDev: stdDev,
    coefficientOfVariation: coefficientOfVariation,
    confidence: classifyConfidence(coefficientOfVariation: coefficientOfVariation, sampleSize: n),
  );
}
