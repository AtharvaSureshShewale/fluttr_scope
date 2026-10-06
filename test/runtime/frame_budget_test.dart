import 'package:fluttr_scope/src/runtime/frame_budget.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:test/test.dart';

// Simulated steady ~60fps spacing so startTimeMicros is meaningful for
// warm-up-split tests without every test needing to specify it explicitly.
FrameMetrics _frame(int number, {required int buildUs, required int rasterUs}) => FrameMetrics(
      frameNumber: number,
      build: Duration(microseconds: buildUs),
      raster: Duration(microseconds: rasterUs),
      elapsed: Duration(microseconds: buildUs + rasterUs),
      startTimeMicros: number * 16667,
    );

const _underBudget = (buildUs: 5000, rasterUs: 3000); // 8ms, under the 16.667ms default
const _overBudget = (buildUs: 15000, rasterUs: 5000); // 20ms, over the 16.667ms default

void main() {
  group('summarizeFrameBudget', () {
    test('empty input summarizes to zero frames, no slowest, no clusters', () {
      final summary = summarizeFrameBudget(const []);
      expect(summary.totalFrames, 0);
      expect(summary.framesOverBudget, 0);
      expect(summary.overBudgetPercent, 0);
      expect(summary.slowestFrame, isNull);
      expect(summary.jankClusters, isEmpty);
    });

    test('counts frames over budget and computes the percentage', () {
      final frames = [
        _frame(1, buildUs: _underBudget.buildUs, rasterUs: _underBudget.rasterUs),
        _frame(2, buildUs: _underBudget.buildUs, rasterUs: _underBudget.rasterUs),
        _frame(3, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
        _frame(4, buildUs: _underBudget.buildUs, rasterUs: _underBudget.rasterUs),
      ];
      final summary = summarizeFrameBudget(frames);
      expect(summary.totalFrames, 4);
      expect(summary.framesOverBudget, 1);
      expect(summary.overBudgetPercent, 25.0);
    });

    test('identifies the slowest frame by build+raster, not build alone', () {
      final frames = [
        _frame(1, buildUs: 1000, rasterUs: 1000), // total 2000
        _frame(2, buildUs: 500, rasterUs: 30000), // total 30500 -- slowest
        _frame(3, buildUs: 20000, rasterUs: 1000), // total 21000
      ];
      final summary = summarizeFrameBudget(frames);
      expect(summary.slowestFrame!.frameNumber, 2);
    });

    test(
        'a run of consecutive over-budget frames at least minClusterSize '
        'long forms one jank cluster', () {
      final frames = [
        for (var i = 1; i <= 4; i++)
          _frame(i, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
      ];
      final summary = summarizeFrameBudget(frames);
      expect(summary.jankClusters, hasLength(1));
      expect(summary.jankClusters.single, hasLength(4));
    });

    test('a run shorter than minClusterSize is not a jank cluster', () {
      final frames = [
        for (var i = 1; i <= 3; i++)
          _frame(i, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
      ];
      final summary = summarizeFrameBudget(frames);
      expect(summary.jankClusters, isEmpty);
    });

    test(
        'a gap in frame numbers splits what would otherwise be one long '
        'run into two independently-evaluated clusters', () {
      final frames = [
        for (var i = 1; i <= 4; i++)
          _frame(i, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
        // Frame numbers 5-9 never captured -- not "not over budget", just
        // absent, e.g. the app was idle and posted no frames.
        for (var i = 10; i <= 13; i++)
          _frame(i, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
      ];
      final summary = summarizeFrameBudget(frames);
      expect(summary.jankClusters, hasLength(2));
      expect(summary.jankClusters[0].map((f) => f.frameNumber), [1, 2, 3, 4]);
      expect(summary.jankClusters[1].map((f) => f.frameNumber), [10, 11, 12, 13]);
    });

    test('input order does not matter -- frames are sorted internally', () {
      final inOrder = [
        for (var i = 1; i <= 4; i++)
          _frame(i, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
      ];
      final shuffled = inOrder.reversed.toList();

      final summary = summarizeFrameBudget(shuffled);
      expect(summary.jankClusters, hasLength(1));
      expect(summary.jankClusters.single.map((f) => f.frameNumber), [1, 2, 3, 4]);
    });
  });

  group('formatFrameBudget', () {
    test('reports "no frames captured" for an empty summary', () {
      expect(
        formatFrameBudget(summarizeFrameBudget(const [])),
        contains('no frames captured'),
      );
    });

    test('includes frame count, over-budget count/percent, and cluster count', () {
      final frames = [
        for (var i = 1; i <= 4; i++)
          _frame(i, buildUs: _overBudget.buildUs, rasterUs: _overBudget.rasterUs),
        _frame(5, buildUs: _underBudget.buildUs, rasterUs: _underBudget.rasterUs),
      ];
      final output = formatFrameBudget(summarizeFrameBudget(frames));

      expect(output, contains('5 frames captured, 4 over budget'));
      expect(output, contains('1 jank cluster(s)'));
      expect(output, contains('Slowest: frame'));
    });

    test('omits the bottleneck/severity tag when the slowest frame is '
        'actually within budget (an otherwise-empty capture)', () {
      final output = formatFrameBudget(summarizeFrameBudget([
        _frame(1, buildUs: _underBudget.buildUs, rasterUs: _underBudget.rasterUs),
      ]));
      expect(output, contains('Slowest: frame 1'));
      expect(output, isNot(contains('bottleneck')));
    });
  });

  group('classifyBottleneck', () {
    test('build-dominant when build is at least 2x raster', () {
      expect(
        classifyBottleneck(_frame(1, buildUs: 24000, rasterUs: 2000)),
        FrameBottleneck.build,
      );
    });

    test('raster-dominant when raster is at least 2x build', () {
      expect(
        classifyBottleneck(_frame(1, buildUs: 3000, rasterUs: 24000)),
        FrameBottleneck.raster,
      );
    });

    test('combined when neither phase dominates by 2x', () {
      expect(
        classifyBottleneck(_frame(1, buildUs: 18000, rasterUs: 14000)),
        FrameBottleneck.combined,
      );
    });
  });

  group('classifySeverity', () {
    test('classifies by multiplier-of-budget bands', () {
      const budget = Duration(microseconds: 16667);
      expect(
        classifySeverity(_frame(1, buildUs: 5000, rasterUs: 3000), budget),
        FrameSeverity.good, // 8ms, under budget
      );
      expect(
        classifySeverity(_frame(1, buildUs: 10000, rasterUs: 8000), budget),
        FrameSeverity.slight, // 18ms, ~1.08x
      );
      expect(
        classifySeverity(_frame(1, buildUs: 15000, rasterUs: 15000), budget),
        FrameSeverity.moderate, // 30ms, ~1.8x
      );
      expect(
        classifySeverity(_frame(1, buildUs: 30000, rasterUs: 20000), budget),
        FrameSeverity.severe, // 50ms, 3x
      );
      expect(
        classifySeverity(_frame(1, buildUs: 700000, rasterUs: 1000), budget),
        FrameSeverity.critical, // ~700ms, ~42x -- the broke_no_more startup spike
      );
    });
  });

  group('splitByWarmup', () {
    test('zero warmup (the default) puts everything in steadyState', () {
      final frames = [_frame(1, buildUs: 5000, rasterUs: 3000)];
      final capture = splitByWarmup(frames, Duration.zero);
      expect(capture.startup, isEmpty);
      expect(capture.steadyState, hasLength(1));
    });

    test('splits by elapsed time relative to the first frame, not by count', () {
      // 60 frames at ~16.67ms spacing spans ~1s -- ask for a 0.5s warmup.
      final frames = [
        for (var i = 1; i <= 60; i++) _frame(i, buildUs: 5000, rasterUs: 3000),
      ];
      final capture = splitByWarmup(frames, const Duration(milliseconds: 500));
      expect(capture.startup, isNotEmpty);
      expect(capture.steadyState, isNotEmpty);
      expect(capture.startup.length + capture.steadyState.length, 60);
      // Every startup frame's start time precedes every steady-state frame's.
      expect(capture.startup.last.startTimeMicros, lessThan(capture.steadyState.first.startTimeMicros));
    });

    test('empty input splits to two empty lists rather than throwing', () {
      final capture = splitByWarmup(const [], const Duration(seconds: 5));
      expect(capture.startup, isEmpty);
      expect(capture.steadyState, isEmpty);
    });
  });

  group('formatFrameCapture', () {
    test('renders a single block when there is no startup portion', () {
      final capture = splitByWarmup(
        [_frame(1, buildUs: 5000, rasterUs: 3000)],
        Duration.zero,
      );
      final output = formatFrameCapture(capture);
      expect(output, isNot(contains('STARTUP')));
      expect(output, isNot(contains('STEADY STATE')));
      expect(output, contains('1 frames captured'));
    });

    test('renders separate STARTUP and STEADY STATE blocks when warmup splits the capture', () {
      final frames = [
        for (var i = 1; i <= 60; i++) _frame(i, buildUs: 5000, rasterUs: 3000),
      ];
      final capture = splitByWarmup(frames, const Duration(milliseconds: 500));
      final output = formatFrameCapture(capture);
      expect(output, contains('STARTUP (excluded from steady-state stats below):'));
      expect(output, contains('STEADY STATE:'));
    });
  });
}
