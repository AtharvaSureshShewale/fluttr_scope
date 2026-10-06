import 'package:fluttr_scope/src/runtime/stats.dart';
import 'package:test/test.dart';

void main() {
  group('computeStats', () {
    test('throws on empty input rather than producing a fake result', () {
      expect(() => computeStats(const []), throwsArgumentError);
    });

    test('median of an odd-length sample is the middle value', () {
      final stats = computeStats([14.7, 13.9, 15.1]);
      expect(stats.median, 14.7);
    });

    test('median of an even-length sample is the average of the two middle values', () {
      final stats = computeStats([14.7, 13.9, 15.1, 14.4]);
      // sorted: 13.9, 14.4, 14.7, 15.1 -> (14.4 + 14.7) / 2
      expect(stats.median, closeTo(14.55, 1e-9));
    });

    test('mean is the arithmetic average', () {
      final stats = computeStats([10, 20, 30]);
      expect(stats.mean, 20);
    });

    test('min and max are the sample extremes regardless of input order', () {
      final stats = computeStats([15.1, 13.9, 14.7, 14.4, 14.8]);
      expect(stats.min, 13.9);
      expect(stats.max, 15.1);
    });

    test('values preserves original (run) order, not sorted order', () {
      final stats = computeStats([14.7, 13.9, 15.1, 14.4, 14.8]);
      expect(stats.values, [14.7, 13.9, 15.1, 14.4, 14.8]);
    });

    test('a single value has zero standard deviation and CoV', () {
      final stats = computeStats([42.0]);
      expect(stats.stdDev, 0);
      expect(stats.coefficientOfVariation, 0);
    });

    test('identical values across the whole sample have zero standard deviation', () {
      final stats = computeStats([10, 10, 10, 10, 10]);
      expect(stats.stdDev, 0);
      expect(stats.coefficientOfVariation, 0);
    });

    test('computes sample standard deviation (n-1 denominator), not population', () {
      // Values 2, 4, 4, 4, 5, 5, 7, 9 -- a textbook example with a known
      // sample standard deviation of 2.13809... (population stdDev would
      // be 2.0 instead), so this pins down which formula is in use.
      final stats = computeStats([2, 4, 4, 4, 5, 5, 7, 9]);
      expect(stats.stdDev, closeTo(2.13809, 1e-4));
    });

    test('coefficient of variation is stdDev / mean', () {
      final stats = computeStats([10, 15, 20]); // mean=15, sample stdDev=5
      expect(stats.coefficientOfVariation, closeTo(5 / 15, 1e-9));
    });

    test('a mean of exactly zero does not produce a division-by-zero NaN', () {
      final stats = computeStats([0, 0, 0]);
      expect(stats.mean, 0);
      expect(stats.coefficientOfVariation, 0);
      expect(stats.coefficientOfVariation.isNaN, isFalse);
    });
  });

  group('classifyConfidence', () {
    test('a single sample is always LOW, regardless of computed CoV', () {
      // A lone value trivially has CoV 0 -- reporting HIGH from one data
      // point would be a fabricated confidence, not a derived one.
      expect(
        classifyConfidence(coefficientOfVariation: 0.0, sampleSize: 1),
        Confidence.low,
      );
    });

    test('CoV at or below 10% with 2+ samples is HIGH', () {
      expect(
        classifyConfidence(coefficientOfVariation: 0.10, sampleSize: 5),
        Confidence.high,
      );
      expect(
        classifyConfidence(coefficientOfVariation: 0.03, sampleSize: 3),
        Confidence.high,
      );
    });

    test('CoV between 10% and 25% is MEDIUM', () {
      expect(
        classifyConfidence(coefficientOfVariation: 0.15, sampleSize: 5),
        Confidence.medium,
      );
      expect(
        classifyConfidence(coefficientOfVariation: 0.25, sampleSize: 5),
        Confidence.medium,
      );
    });

    test('CoV above 25% is LOW', () {
      expect(
        classifyConfidence(coefficientOfVariation: 0.26, sampleSize: 5),
        Confidence.low,
      );
      expect(
        classifyConfidence(coefficientOfVariation: 1.5, sampleSize: 5),
        Confidence.low,
      );
    });

    test('computeStats wires confidence through end to end for a stable sample', () {
      final stable = computeStats([14.7, 13.9, 15.1, 14.4, 14.8]);
      expect(stable.confidence, Confidence.high);
      expect(stable.isUnstable, isFalse);
    });

    test('computeStats wires confidence through end to end for a noisy sample', () {
      final noisy = computeStats([7, 8, 25, 9, 7]); // one wild outlier
      expect(noisy.confidence, isNot(Confidence.high));
      expect(noisy.isUnstable, isTrue);
    });
  });
}
