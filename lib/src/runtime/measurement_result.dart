import 'frame_metrics.dart';
import 'frame_rebuild_accumulator.dart';
import 'rebuild_record.dart';

/// Retained heap size (bytes, after a forced GC) before and after a
/// capture window — a coarse "is memory growing over this window" signal.
///
/// Deliberately just the raw before/after numbers, not a leak
/// classification: a positive delta over one short window is not proof of
/// a leak (caches, lazily-initialized singletons, and font/image caches
/// all grow heap once and then stop) — it's a signal worth a second look,
/// not a verdict.
class HeapUsage {
  final int beforeBytes;
  final int afterBytes;

  const HeapUsage({required this.beforeBytes, required this.afterBytes});

  int get deltaBytes => afterBytes - beforeBytes;

  Map<String, Object?> toJson() => {
        'beforeBytes': beforeBytes,
        'afterBytes': afterBytes,
        'deltaBytes': deltaBytes,
      };

  factory HeapUsage.fromJson(Map<String, Object?> json) => HeapUsage(
        beforeBytes: json['beforeBytes'] as int,
        afterBytes: json['afterBytes'] as int,
      );
}

/// Everything captured by one `measure` run.
class MeasurementResult {
  final List<RebuildRecord> rebuilds;
  final HeapUsage heapUsage;
  final List<FrameMetrics> frames;

  /// Wall-clock time when this run's `RuntimeDriver.measure()` call
  /// started. `null` for captures predating this field.
  final DateTime? launchedAt;

  /// The target process's own Dart VM version string (`getVM().version`)
  /// -- real data about the device under test, not the host running
  /// fluttr_scope. `null` for captures predating this field.
  final String? dartVmVersion;

  /// Widget rebuild counts by location, per frame -- unlike [rebuilds],
  /// which collapses everything into one whole-window sum, this preserves
  /// the exact frame number each batch of rebuilds happened in (see
  /// `frame_rebuild_accumulator.dart`), which is what makes rebuild-to-
  /// frame correlation possible. Empty for captures predating this field.
  final List<FrameRebuildRecord> perFrameRebuilds;

  const MeasurementResult({
    required this.rebuilds,
    required this.heapUsage,
    this.frames = const [],
    this.launchedAt,
    this.dartVmVersion,
    this.perFrameRebuilds = const [],
  });

  Map<String, Object?> toJson() => {
        'rebuilds': rebuilds.map((r) => r.toJson()).toList(),
        'heapUsage': heapUsage.toJson(),
        'frames': frames.map((f) => f.toJson()).toList(),
        'launchedAt': launchedAt?.toIso8601String(),
        'dartVmVersion': dartVmVersion,
        'perFrameRebuilds': perFrameRebuilds.map((r) => r.toJson()).toList(),
      };

  factory MeasurementResult.fromJson(Map<String, Object?> json) => MeasurementResult(
        rebuilds: [
          for (final entry in json['rebuilds'] as List)
            RebuildRecord.fromJson(entry as Map<String, Object?>),
        ],
        heapUsage: HeapUsage.fromJson(json['heapUsage'] as Map<String, Object?>),
        frames: [
          for (final entry in (json['frames'] as List? ?? const []))
            FrameMetrics.fromJson(entry as Map<String, Object?>),
        ],
        launchedAt: json['launchedAt'] == null
            ? null
            : DateTime.parse(json['launchedAt'] as String),
        dartVmVersion: json['dartVmVersion'] as String?,
        perFrameRebuilds: [
          for (final entry in (json['perFrameRebuilds'] as List? ?? const []))
            FrameRebuildRecord.fromJson(entry as Map<String, Object?>),
        ],
      );
}
