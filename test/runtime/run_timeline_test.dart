import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/run_timeline.dart';
import 'package:test/test.dart';

FrameMetrics _f(int startTimeMicros) => FrameMetrics(
      frameNumber: 1,
      build: const Duration(microseconds: 5000),
      raster: const Duration(microseconds: 3000),
      elapsed: const Duration(microseconds: 8000),
      startTimeMicros: startTimeMicros,
    );

void main() {
  group('buildRunTimeline', () {
    test('returns null for an empty frame list -- nothing to build a timeline from', () {
      expect(buildRunTimeline(const [], warmup: Duration.zero, launchedAt: null), isNull);
    });

    test('offsets are relative to the first captured frame, not absolute', () {
      final frames = [_f(1000000), _f(1016667), _f(1033334)];
      final timeline = buildRunTimeline(
        frames,
        warmup: const Duration(milliseconds: 10),
        launchedAt: null,
      )!;
      expect(timeline.measurementStartOffsetMs, closeTo(10, 1e-9));
      expect(timeline.measurementEndOffsetMs, closeTo(33.334, 1e-6));
    });

    test('preserves the supplied wall-clock launchedAt untouched', () {
      final launchedAt = DateTime(2026, 1, 1, 12, 0, 0);
      final timeline = buildRunTimeline(
        [_f(0)],
        warmup: Duration.zero,
        launchedAt: launchedAt,
      )!;
      expect(timeline.launchedAt, launchedAt);
    });

    test('measurementDurationMs is end minus start', () {
      final timeline = buildRunTimeline(
        [_f(1000000), _f(1500000)],
        warmup: Duration.zero,
        launchedAt: null,
      )!;
      expect(timeline.measurementDurationMs, closeTo(500, 1e-9));
    });

    test('flow start/end are always null -- no scripted flow exists yet', () {
      final timeline = buildRunTimeline([_f(0)], warmup: Duration.zero, launchedAt: null)!;
      expect(timeline.flowStartOffsetMs, isNull);
      expect(timeline.flowEndOffsetMs, isNull);
    });

    test('input order does not matter -- frames are sorted internally', () {
      final inOrder = [_f(1000000), _f(1016667), _f(1033334)];
      final shuffled = inOrder.reversed.toList();
      final timeline = buildRunTimeline(
        shuffled,
        warmup: const Duration(milliseconds: 10),
        launchedAt: null,
      )!;
      expect(timeline.measurementEndOffsetMs, closeTo(33.334, 1e-6));
    });
  });
}
