import 'frame_metrics.dart';

/// Assumed frame budget: 60Hz (16.67ms). This is an *assumption*, not a
/// measured device refresh rate -- querying the display's actual refresh
/// rate isn't implemented, so a 90Hz/120Hz device's frames will be judged
/// against a 60Hz budget unless overridden. Stated explicitly rather than
/// silently treating every device as 60Hz.
const defaultFrameBudget = Duration(microseconds: 16667);

/// A maximal run of consecutive-by-frame-number frames that all exceeded
/// [FrameBudgetSummary.budget] -- a jank cluster is a stronger signal than
/// one isolated slow frame.
typedef JankCluster = List<FrameMetrics>;

/// Which phase an over-budget frame's cost is actually coming from --
/// treating "the frame was slow" as one undifferentiated fact hides
/// whether the fix belongs in widget/layout code (build) or in
/// paint/shader/GPU work (raster), which are different problems with
/// different fixes.
enum FrameBottleneck { build, raster, combined }

/// Classifies which phase dominates an over-budget frame's cost: [build]
/// or [raster] if one phase is at least twice the other, [combined]
/// otherwise (both contributed meaningfully). Meaningless for a frame
/// that isn't over budget -- callers should check that separately.
FrameBottleneck classifyBottleneck(FrameMetrics frame) {
  final build = frame.build.inMicroseconds;
  final raster = frame.raster.inMicroseconds;
  if (raster == 0 || build >= raster * 2) return FrameBottleneck.build;
  if (build == 0 || raster >= build * 2) return FrameBottleneck.raster;
  return FrameBottleneck.combined;
}

/// A magnitude classification for how far over budget a frame is.
///
/// This is a proposed rubric for surfacing relative severity in reports,
/// not a Flutter-standard or measured threshold -- the multiplier bands
/// below (1-1.25x, 1.25-2x, 2-5x, >5x) are a judgment call stated
/// explicitly so they can be revisited, not a hidden black-box score.
enum FrameSeverity { good, slight, moderate, severe, critical }

FrameSeverity classifySeverity(FrameMetrics frame, Duration budget) {
  if (budget.inMicroseconds == 0) return FrameSeverity.good;
  final ratio = (frame.build + frame.raster).inMicroseconds / budget.inMicroseconds;
  if (ratio <= 1) return FrameSeverity.good;
  if (ratio <= 1.25) return FrameSeverity.slight;
  if (ratio <= 2) return FrameSeverity.moderate;
  if (ratio <= 5) return FrameSeverity.severe;
  return FrameSeverity.critical;
}

class FrameBudgetSummary {
  final Duration budget;
  final int totalFrames;
  final int framesOverBudget;
  final FrameMetrics? slowestFrame;
  final List<JankCluster> jankClusters;
  final int minClusterSize;

  const FrameBudgetSummary({
    required this.budget,
    required this.totalFrames,
    required this.framesOverBudget,
    required this.slowestFrame,
    required this.jankClusters,
    required this.minClusterSize,
  });

  double get overBudgetPercent => totalFrames == 0 ? 0 : framesOverBudget / totalFrames * 100;
}

/// Summarizes [frames] against [budget], including jank-cluster detection:
/// a run of at least [minClusterSize] frames, consecutive by frame number
/// (not just consecutive in the list -- a gap means frames weren't
/// captured back-to-back, e.g. the app was idle), that all exceeded budget.
///
/// [frames] does not need to be pre-sorted; this sorts a copy by frame
/// number first so cluster detection is correct regardless of the order
/// events arrived in.
FrameBudgetSummary summarizeFrameBudget(
  List<FrameMetrics> frames, {
  Duration budget = defaultFrameBudget,
  int minClusterSize = 4,
}) {
  final sorted = [...frames]..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));

  bool isOverBudget(FrameMetrics f) => f.build + f.raster > budget;

  FrameMetrics? slowest;
  for (final f in sorted) {
    if (slowest == null || (f.build + f.raster) > (slowest.build + slowest.raster)) {
      slowest = f;
    }
  }

  final clusters = <JankCluster>[];
  var current = <FrameMetrics>[];
  for (final f in sorted) {
    if (current.isNotEmpty && f.frameNumber != current.last.frameNumber + 1) {
      if (current.length >= minClusterSize && isOverBudget(current.first)) {
        clusters.add(current);
      }
      current = [];
    }
    if (isOverBudget(f)) {
      current.add(f);
    } else if (current.isNotEmpty) {
      if (current.length >= minClusterSize) clusters.add(current);
      current = [];
    }
  }
  if (current.length >= minClusterSize) clusters.add(current);

  return FrameBudgetSummary(
    budget: budget,
    totalFrames: sorted.length,
    framesOverBudget: sorted.where(isOverBudget).length,
    slowestFrame: slowest,
    jankClusters: clusters,
    minClusterSize: minClusterSize,
  );
}

String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)}ms';

/// Renders a [FrameBudgetSummary] as the same plain-text block used by both
/// `measure` and `correlate`'s console reports.
String formatFrameBudget(FrameBudgetSummary summary) {
  final buffer = StringBuffer();
  final hz = (1000000 / summary.budget.inMicroseconds).round();

  if (summary.totalFrames == 0) {
    buffer.writeln('Frame budget: no frames captured.');
    return buffer.toString();
  }

  buffer.writeln('Frame budget (assumed ${hz}Hz, ${_ms(summary.budget)}):');
  buffer.writeln(
    '  ${summary.totalFrames} frames captured, ${summary.framesOverBudget} over budget '
    '(${summary.overBudgetPercent.toStringAsFixed(1)}%)',
  );
  final slowest = summary.slowestFrame;
  if (slowest != null) {
    final classification = classifySeverity(slowest, summary.budget) == FrameSeverity.good
        ? ''
        : ' [${classifyBottleneck(slowest).name} bottleneck, '
            '${classifySeverity(slowest, summary.budget).name}]';
    buffer.writeln(
      '  Slowest: frame ${slowest.frameNumber}, build=${_ms(slowest.build)} '
      'raster=${_ms(slowest.raster)}$classification',
    );
  }
  if (summary.jankClusters.isNotEmpty) {
    buffer.writeln(
      '  ${summary.jankClusters.length} jank cluster(s) '
      '(${summary.minClusterSize}+ consecutive over-budget frames)',
    );
  }
  return buffer.toString();
}

/// A capture window split into a startup portion and everything after,
/// by wall-clock time relative to the first captured frame.
class FrameCapture {
  final List<FrameMetrics> startup;
  final List<FrameMetrics> steadyState;

  const FrameCapture({required this.startup, required this.steadyState});
}

/// Splits [frames] into [FrameCapture.startup] (everything within
/// [warmup] of the first captured frame) and [FrameCapture.steadyState]
/// (everything after) -- so a startup spike like heavy first-frame asset
/// loading doesn't get blended into a single "whole window" statistic
/// that looks like a steady-state problem when it isn't one.
///
/// `Duration.zero` (the default) puts everything in [FrameCapture
/// .steadyState] and leaves [FrameCapture.startup] empty -- splitting is
/// opt-in, so existing single-block reports are unaffected unless a
/// caller actually asks for a warm-up window.
FrameCapture splitByWarmup(List<FrameMetrics> frames, Duration warmup) {
  if (frames.isEmpty) return const FrameCapture(startup: [], steadyState: []);
  final sorted = [...frames]..sort((a, b) => a.startTimeMicros.compareTo(b.startTimeMicros));
  if (warmup <= Duration.zero) {
    return FrameCapture(startup: const [], steadyState: sorted);
  }
  final cutoff = sorted.first.startTimeMicros + warmup.inMicroseconds;
  return FrameCapture(
    startup: sorted.where((f) => f.startTimeMicros < cutoff).toList(),
    steadyState: sorted.where((f) => f.startTimeMicros >= cutoff).toList(),
  );
}

/// Renders a warm-up-split capture: a single frame-budget block when
/// there's no startup portion (the common case, [warmup] not requested),
/// or separate STARTUP / STEADY STATE blocks when there is.
String formatFrameCapture(
  FrameCapture capture, {
  Duration budget = defaultFrameBudget,
  int minClusterSize = 4,
}) {
  if (capture.startup.isEmpty) {
    return formatFrameBudget(
      summarizeFrameBudget(capture.steadyState, budget: budget, minClusterSize: minClusterSize),
    );
  }
  final buffer = StringBuffer();
  buffer.writeln('STARTUP (excluded from steady-state stats below):');
  buffer.write(formatFrameBudget(
    summarizeFrameBudget(capture.startup, budget: budget, minClusterSize: minClusterSize),
  ));
  buffer.writeln();
  buffer.writeln('STEADY STATE:');
  buffer.write(formatFrameBudget(
    summarizeFrameBudget(capture.steadyState, budget: budget, minClusterSize: minClusterSize),
  ));
  return buffer.toString();
}
