import 'frame_metrics.dart';

/// When things happened during one run.
///
/// [launchedAt] is a real wall-clock timestamp (when `RuntimeDriver.measure`
/// started). Everything else is expressed as an offset in milliseconds
/// from the *first captured frame* -- frame timestamps come from the
/// engine's own monotonic clock, which has no fixed relationship to wall
/// time, so treating them as wall-clock-aligned with [launchedAt] would be
/// a fabricated precision this tool doesn't have.
///
/// [flowStartOffsetMs] / [flowEndOffsetMs] are always `null`: this version
/// of the tool has no scripted-interaction flow at all (capture is a fixed
/// -duration passive window after launch, not a repeatable script) -- kept
/// as explicit fields rather than omitted so a report can say "not
/// available" instead of silently having no flow section.
class RunTimeline {
  final DateTime? launchedAt;
  final double warmupEndOffsetMs;
  final double measurementStartOffsetMs;
  final double measurementEndOffsetMs;
  final double? flowStartOffsetMs;
  final double? flowEndOffsetMs;

  const RunTimeline({
    required this.launchedAt,
    required this.warmupEndOffsetMs,
    required this.measurementStartOffsetMs,
    required this.measurementEndOffsetMs,
    this.flowStartOffsetMs,
    this.flowEndOffsetMs,
  });

  double get measurementDurationMs => measurementEndOffsetMs - measurementStartOffsetMs;

  Map<String, Object?> toJson() => {
        'launchedAt': launchedAt?.toIso8601String(),
        'warmupEndOffsetMs': warmupEndOffsetMs,
        'measurementStartOffsetMs': measurementStartOffsetMs,
        'measurementEndOffsetMs': measurementEndOffsetMs,
        'measurementDurationMs': measurementDurationMs,
        'flowStartOffsetMs': flowStartOffsetMs,
        'flowEndOffsetMs': flowEndOffsetMs,
      };
}

/// Builds a [RunTimeline] from one run's full (unsplit) frame list and the
/// warm-up duration that was applied. [frames] does not need to be
/// pre-sorted. Returns `null` if [frames] is empty -- there's no timeline
/// to report.
RunTimeline? buildRunTimeline(
  List<FrameMetrics> frames, {
  required Duration warmup,
  required DateTime? launchedAt,
}) {
  if (frames.isEmpty) return null;
  final sorted = [...frames]..sort((a, b) => a.startTimeMicros.compareTo(b.startTimeMicros));
  final firstMicros = sorted.first.startTimeMicros;
  final lastMicros = sorted.last.startTimeMicros;
  final warmupEndMicros = firstMicros + warmup.inMicroseconds;

  return RunTimeline(
    launchedAt: launchedAt,
    warmupEndOffsetMs: warmup.inMicroseconds / 1000,
    measurementStartOffsetMs: (warmupEndMicros - firstMicros) / 1000,
    measurementEndOffsetMs: (lastMicros - firstMicros) / 1000,
  );
}
