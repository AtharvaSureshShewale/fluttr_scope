import '../model/source_location.dart';
import 'frame_budget.dart';
import 'frame_metrics.dart';
import 'frame_rebuild_accumulator.dart';
import 'stats.dart';

/// Whether a widget rebuilt often enough in the capture window to call its
/// rebuild volume "high" -- a stated judgment call (same treatment as
/// [FrameSeverity]/[Confidence] elsewhere), not a derived threshold.
/// 50 is a round number well above what a normal, cheap widget accumulates
/// incidentally over a several-second window.
const highRebuildCountThreshold = 50;

/// A widget's frame impact counts as "high" only when *both* conditions
/// hold: enough over-budget frames to not be one coincidence
/// ([highFrameImpactMinOverBudgetFrames]), *and* those frames make up a
/// meaningful share of the frames it actually touched
/// ([highFrameImpactMinPercent]) -- a widget that rebuilt during 3 bad
/// frames out of 3000 touched isn't "high impact" by the count alone.
/// Both are stated judgment calls.
const highFrameImpactMinOverBudgetFrames = 3;
const highFrameImpactMinPercent = 30.0;

enum RebuildLevel { low, high }

enum FrameImpactLevel { low, high }

/// The four-quadrant classification from rebuild volume x frame impact.
/// [highRebuildHighImpact] is the interesting one -- a widget rebuilding
/// often *and* those rebuilds co-occurring with frame-budget violations.
enum ImpactClassification {
  lowRebuildLowImpact,
  highRebuildLowImpact,
  lowRebuildHighImpact,
  highRebuildHighImpact,
}

String describeClassification(ImpactClassification c) => switch (c) {
      ImpactClassification.lowRebuildLowImpact => 'LOW REBUILD / LOW FRAME IMPACT',
      ImpactClassification.highRebuildLowImpact => 'HIGH REBUILD / LOW FRAME IMPACT',
      ImpactClassification.lowRebuildHighImpact => 'LOW REBUILD / HIGH FRAME IMPACT',
      ImpactClassification.highRebuildHighImpact => 'HIGH REBUILD / HIGH FRAME IMPACT',
    };

/// One widget's (one creation location's) observed rebuild activity and
/// its exact frame-number association with over-budget frames, for one
/// run.
///
/// Precision, stated plainly: [framesRebuiltIn] and
/// [overBudgetFramesRebuiltIn] are *exact* -- `Flutter.RebuiltWidgets`
/// carries the same frame number `Flutter.Frame` does (see
/// `frame_rebuild_accumulator.dart`), so "this location rebuilt during
/// frame N" is a fact, not an inference. What's *not* available is this
/// widget's own share of that frame's build time -- only the frame's
/// total build+raster duration. [frameBuildStats] is explicitly the
/// distribution of *frame* durations across the frames this widget
/// touched, not this widget's own isolated cost -- never call it "this
/// widget's build time" in a report without that qualifier.
class WidgetFrameImpact {
  final SourceLocation location;
  final int rebuildCount;
  final Set<int> framesRebuiltIn;
  final Set<int> overBudgetFramesRebuiltIn;

  /// build+raster duration (ms) of the frames in [framesRebuiltIn] that
  /// were actually found in the frame list supplied to
  /// [computeWidgetFrameImpacts] -- `null` only if none were (shouldn't
  /// happen in practice, since every frame number here came from that
  /// same capture, but treated as "unknown", never fabricated).
  final Stats? frameBuildStatsMs;

  const WidgetFrameImpact({
    required this.location,
    required this.rebuildCount,
    required this.framesRebuiltIn,
    required this.overBudgetFramesRebuiltIn,
    required this.frameBuildStatsMs,
  });

  int get overBudgetFrameCount => overBudgetFramesRebuiltIn.length;

  double get percentFramesOverBudget =>
      framesRebuiltIn.isEmpty ? 0 : overBudgetFrameCount / framesRebuiltIn.length * 100;

  RebuildLevel get rebuildLevel =>
      rebuildCount >= highRebuildCountThreshold ? RebuildLevel.high : RebuildLevel.low;

  FrameImpactLevel get frameImpactLevel =>
      (overBudgetFrameCount >= highFrameImpactMinOverBudgetFrames &&
              percentFramesOverBudget >= highFrameImpactMinPercent)
          ? FrameImpactLevel.high
          : FrameImpactLevel.low;

  ImpactClassification get classification {
    final highRebuild = rebuildLevel == RebuildLevel.high;
    final highImpact = frameImpactLevel == FrameImpactLevel.high;
    if (highRebuild && highImpact) return ImpactClassification.highRebuildHighImpact;
    if (highRebuild) return ImpactClassification.highRebuildLowImpact;
    if (highImpact) return ImpactClassification.lowRebuildHighImpact;
    return ImpactClassification.lowRebuildLowImpact;
  }

  Map<String, Object?> toJson() => {
        'location': location.toJson(),
        'rebuildCount': rebuildCount,
        'framesRebuiltIn': framesRebuiltIn.length,
        'overBudgetFrameCount': overBudgetFrameCount,
        'percentFramesOverBudget': percentFramesOverBudget,
        'frameBuildStatsMs': frameBuildStatsMs == null
            ? null
            : {
                'median': frameBuildStatsMs!.median,
                'mean': frameBuildStatsMs!.mean,
                'max': frameBuildStatsMs!.max,
              },
        'classification': describeClassification(classification),
      };
}

/// Joins [perFrameRebuilds] (exact per-frame widget rebuild counts) against
/// [frames] (per-frame timing) by frame number, producing one
/// [WidgetFrameImpact] per distinct source location observed rebuilding.
///
/// A rebuild reported for a frame number that isn't in [frames] (e.g. it
/// fell outside the steady-state window this was computed for) is still
/// counted toward [WidgetFrameImpact.rebuildCount] and
/// [WidgetFrameImpact.framesRebuiltIn], but can't contribute to
/// over-budget classification or frame-duration stats for that frame --
/// callers should pass [perFrameRebuilds] and [frames] from the same
/// warm-up-consistent window so this is the exception, not the rule.
List<WidgetFrameImpact> computeWidgetFrameImpacts(
  List<FrameRebuildRecord> perFrameRebuilds,
  List<FrameMetrics> frames, {
  Duration budget = defaultFrameBudget,
}) {
  final frameByNumber = {for (final f in frames) f.frameNumber: f};
  bool isOverBudget(FrameMetrics f) => f.build + f.raster > budget;

  final rebuildCounts = <SourceLocation, int>{};
  final framesRebuiltIn = <SourceLocation, Set<int>>{};

  for (final record in perFrameRebuilds) {
    for (final entry in record.countsByLocation.entries) {
      rebuildCounts[entry.key] = (rebuildCounts[entry.key] ?? 0) + entry.value;
      (framesRebuiltIn[entry.key] ??= {}).add(record.frameNumber);
    }
  }

  return [
    for (final location in rebuildCounts.keys)
      _buildImpact(location, rebuildCounts, framesRebuiltIn, frameByNumber, isOverBudget),
  ];
}

WidgetFrameImpact _buildImpact(
  SourceLocation location,
  Map<SourceLocation, int> rebuildCounts,
  Map<SourceLocation, Set<int>> framesRebuiltIn,
  Map<int, FrameMetrics> frameByNumber,
  bool Function(FrameMetrics) isOverBudget,
) {
  final touchedFrames = framesRebuiltIn[location]!;
  final overBudget = <int>{};
  final durationsMs = <double>[];
  for (final frameNumber in touchedFrames) {
    final frame = frameByNumber[frameNumber];
    if (frame == null) continue;
    if (isOverBudget(frame)) overBudget.add(frameNumber);
    durationsMs.add((frame.build + frame.raster).inMicroseconds / 1000);
  }

  return WidgetFrameImpact(
    location: location,
    rebuildCount: rebuildCounts[location]!,
    framesRebuiltIn: touchedFrames,
    overBudgetFramesRebuiltIn: overBudget,
    frameBuildStatsMs: durationsMs.isEmpty ? null : computeStats(durationsMs),
  );
}
