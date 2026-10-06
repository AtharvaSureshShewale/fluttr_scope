import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/measurement_result.dart';
import 'package:fluttr_scope/src/runtime/rebuild_record.dart';
import 'package:test/test.dart';

void main() {
  group('HeapUsage', () {
    test('deltaBytes is after minus before, including when it shrinks', () {
      expect(
        const HeapUsage(beforeBytes: 1000, afterBytes: 1500).deltaBytes,
        500,
      );
      expect(
        const HeapUsage(beforeBytes: 1500, afterBytes: 1000).deltaBytes,
        -500,
      );
    });

    test('round-trips through JSON, including the derived delta', () {
      const usage = HeapUsage(beforeBytes: 1000, afterBytes: 1200);
      final restored = HeapUsage.fromJson(usage.toJson());
      expect(restored.beforeBytes, 1000);
      expect(restored.afterBytes, 1200);
      expect(restored.deltaBytes, 200);
    });
  });

  group('MeasurementResult', () {
    test('round-trips rebuilds and heap usage through JSON', () {
      const result = MeasurementResult(
        rebuilds: [
          RebuildRecord(
            location: SourceLocation(file: 'lib/main.dart', line: 22, column: 12, length: 0),
            rebuildCount: 3,
          ),
        ],
        heapUsage: HeapUsage(beforeBytes: 100, afterBytes: 150),
      );

      final restored = MeasurementResult.fromJson(result.toJson());

      expect(restored.rebuilds, hasLength(1));
      expect(restored.rebuilds.single.rebuildCount, 3);
      expect(restored.rebuilds.single.location.line, 22);
      expect(restored.heapUsage.deltaBytes, 50);
    });

    test('round-trips frames through JSON, and defaults to empty when '
        'absent (older captures predate frame timing)', () {
      const result = MeasurementResult(
        rebuilds: [],
        heapUsage: HeapUsage(beforeBytes: 100, afterBytes: 150),
        frames: [
          FrameMetrics(
            frameNumber: 42,
            build: Duration(milliseconds: 5),
            raster: Duration(milliseconds: 3),
            elapsed: Duration(milliseconds: 8),
            startTimeMicros: 700000,
          ),
        ],
      );

      final restored = MeasurementResult.fromJson(result.toJson());
      expect(restored.frames, hasLength(1));
      expect(restored.frames.single.frameNumber, 42);
      expect(restored.frames.single.build, const Duration(milliseconds: 5));

      final legacyJson = result.toJson()..remove('frames');
      expect(MeasurementResult.fromJson(legacyJson).frames, isEmpty);
    });
  });
}
