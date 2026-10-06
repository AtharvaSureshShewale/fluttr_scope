import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:test/test.dart';

void main() {
  group('FrameMetrics', () {
    test('decodes a Flutter.Frame extension event payload', () {
      final metrics = FrameMetrics.fromExtensionData({
        'number': 421,
        'startTime': 1000000,
        'elapsed': 23000,
        'build': 19200,
        'raster': 4100,
        'vsyncOverhead': 500,
      });

      expect(metrics.frameNumber, 421);
      expect(metrics.build, const Duration(microseconds: 19200));
      expect(metrics.raster, const Duration(microseconds: 4100));
      expect(metrics.elapsed, const Duration(microseconds: 23000));
      expect(metrics.startTimeMicros, 1000000);
    });

    test('round-trips through JSON', () {
      const metrics = FrameMetrics(
        frameNumber: 7,
        build: Duration(microseconds: 12345),
        raster: Duration(microseconds: 6789),
        elapsed: Duration(microseconds: 19134),
        startTimeMicros: 555000,
      );

      final restored = FrameMetrics.fromJson(metrics.toJson());

      expect(restored.frameNumber, 7);
      expect(restored.build, metrics.build);
      expect(restored.raster, metrics.raster);
      expect(restored.elapsed, metrics.elapsed);
      expect(restored.startTimeMicros, 555000);
    });

    test('fromJson defaults startTimeMicros to 0 for a capture predating '
        'this field, instead of crashing', () {
      final restored = FrameMetrics.fromJson({
        'frameNumber': 1,
        'buildMicros': 1000,
        'rasterMicros': 1000,
        'elapsedMicros': 2000,
      });
      expect(restored.startTimeMicros, 0);
    });
  });
}
