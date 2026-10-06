/// One frame's build/raster timing.
///
/// Decoded from the framework's `Flutter.Frame` VM Service extension
/// event -- posted automatically, for every frame, whenever the app isn't
/// in release mode (`SchedulerBinding`'s own debug/profile instrumentation,
/// see `_profileFramePostEvent` in the framework source). No app-side code
/// is needed to capture this, same as the rebuild-count mechanism.
class FrameMetrics {
  final int frameNumber;
  final Duration build;
  final Duration raster;
  final Duration elapsed;

  /// When this frame's build phase started, in the engine's own monotonic
  /// clock (microseconds since some internal epoch -- meaningless as a
  /// wall-clock time, only meaningful *relative to other frames in the
  /// same capture*). Used to split a capture into a startup window and a
  /// steady-state window by elapsed time rather than by frame count.
  final int startTimeMicros;

  const FrameMetrics({
    required this.frameNumber,
    required this.build,
    required this.raster,
    required this.elapsed,
    required this.startTimeMicros,
  });

  /// Decodes one `Flutter.Frame` extension event's data payload --
  /// `{number, startTime, elapsed, build, raster, vsyncOverhead}`, all
  /// durations in microseconds.
  factory FrameMetrics.fromExtensionData(Map<String, Object?> data) => FrameMetrics(
        frameNumber: data['number'] as int,
        build: Duration(microseconds: data['build'] as int),
        raster: Duration(microseconds: data['raster'] as int),
        elapsed: Duration(microseconds: data['elapsed'] as int),
        startTimeMicros: data['startTime'] as int,
      );

  Map<String, Object?> toJson() => {
        'frameNumber': frameNumber,
        'buildMicros': build.inMicroseconds,
        'rasterMicros': raster.inMicroseconds,
        'elapsedMicros': elapsed.inMicroseconds,
        'startTimeMicros': startTimeMicros,
      };

  factory FrameMetrics.fromJson(Map<String, Object?> json) => FrameMetrics(
        frameNumber: json['frameNumber'] as int,
        build: Duration(microseconds: json['buildMicros'] as int),
        raster: Duration(microseconds: json['rasterMicros'] as int),
        elapsed: Duration(microseconds: json['elapsedMicros'] as int),
        // Older captures predate this field -- 0 makes every frame count
        // as "steady state" under warm-up splitting rather than crashing.
        startTimeMicros: json['startTimeMicros'] as int? ?? 0,
      );
}
