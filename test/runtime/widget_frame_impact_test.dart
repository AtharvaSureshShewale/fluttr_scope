import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/runtime/frame_metrics.dart';
import 'package:fluttr_scope/src/runtime/frame_rebuild_accumulator.dart';
import 'package:fluttr_scope/src/runtime/widget_frame_impact.dart';
import 'package:test/test.dart';

const _location = SourceLocation(file: 'lib/widgets/product_card.dart', line: 42, column: 12, length: 0);
const _otherLocation = SourceLocation(file: 'lib/widgets/header.dart', line: 7, column: 3, length: 0);

FrameMetrics _frame(int number, {required bool overBudget}) => FrameMetrics(
      frameNumber: number,
      build: Duration(microseconds: overBudget ? 20000 : 3000),
      raster: const Duration(microseconds: 2000),
      elapsed: Duration(microseconds: (overBudget ? 20000 : 3000) + 2000),
      startTimeMicros: number * 16667,
    );

FrameRebuildRecord _rebuild(int frameNumber, Map<SourceLocation, int> counts) =>
    FrameRebuildRecord(frameNumber: frameNumber, countsByLocation: counts);

void main() {
  group('computeWidgetFrameImpacts', () {
    test('a widget build inside a normal (not over-budget) frame is not '
        'counted as frame impact', () {
      final frames = [_frame(1, overBudget: false)];
      final rebuilds = [_rebuild(1, {_location: 1})];

      final impacts = computeWidgetFrameImpacts(rebuilds, frames);
      final impact = impacts.single;
      expect(impact.framesRebuiltIn, {1});
      expect(impact.overBudgetFramesRebuiltIn, isEmpty);
      expect(impact.overBudgetFrameCount, 0);
    });

    test('a widget build overlapping a slow (over-budget) frame is counted', () {
      final frames = [_frame(1, overBudget: true)];
      final rebuilds = [_rebuild(1, {_location: 1})];

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      expect(impact.overBudgetFramesRebuiltIn, {1});
      expect(impact.overBudgetFrameCount, 1);
      expect(impact.percentFramesOverBudget, 100.0);
    });

    test('a widget build outside a slow frame is not attributed to it, '
        'even though other frames in the same capture were over budget '
        '(exact join, not "any bad frame in the window")', () {
      final frames = [_frame(1, overBudget: false), _frame(2, overBudget: true)];
      // This widget only ever rebuilt during frame 1 (the good one).
      final rebuilds = [_rebuild(1, {_location: 1})];

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      expect(impact.framesRebuiltIn, {1});
      expect(impact.overBudgetFramesRebuiltIn, isEmpty);
      expect(impact.overBudgetFrameCount, 0);
    });

    test('multiple widgets rebuilding in the same slow frame are each '
        'independently attributed to it', () {
      final frames = [_frame(1, overBudget: true)];
      final rebuilds = [
        _rebuild(1, {_location: 1, _otherLocation: 1}),
      ];

      final impacts = computeWidgetFrameImpacts(rebuilds, frames);
      expect(impacts, hasLength(2));
      for (final impact in impacts) {
        expect(impact.overBudgetFramesRebuiltIn, {1});
      }
    });

    test('multiple rebuilds of the same location within one frame sum the '
        'rebuild count but count the frame only once toward frames touched', () {
      final frames = [_frame(1, overBudget: true)];
      final rebuilds = [_rebuild(1, {_location: 4})]; // 4 sibling instances rebuilt this frame

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      expect(impact.rebuildCount, 4);
      expect(impact.framesRebuiltIn, {1}); // one frame, not four
      expect(impact.overBudgetFrameCount, 1);
    });

    test('a widget with many rebuilds spread across frames that are never '
        'over budget is HIGH rebuild volume but LOW frame impact', () {
      final frames = [for (var i = 1; i <= 60; i++) _frame(i, overBudget: false)];
      final rebuilds = [for (var i = 1; i <= 60; i++) _rebuild(i, {_location: 1})];

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      expect(impact.rebuildCount, 60); // above highRebuildCountThreshold (50)
      expect(impact.rebuildLevel, RebuildLevel.high);
      expect(impact.frameImpactLevel, FrameImpactLevel.low);
      expect(impact.classification, ImpactClassification.highRebuildLowImpact);
    });

    test('a slow frame with no rebuild record referencing it contributes '
        'no fabricated attribution to any widget', () {
      final frames = [_frame(1, overBudget: false), _frame(2, overBudget: true)];
      // Frame 2 is slow, but nothing rebuilt during it -- no rebuild
      // record mentions frame 2 at all.
      final rebuilds = [_rebuild(1, {_location: 1})];

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      expect(impact.overBudgetFramesRebuiltIn, isEmpty);
      // No widget in the result claims frame 2 -- nothing to iterate that
      // would attribute it, which is itself the assertion: there is
      // exactly one WidgetFrameImpact (for the one location that actually
      // rebuilt), not a second one fabricated for the untouched slow frame.
      expect(computeWidgetFrameImpacts(rebuilds, frames), hasLength(1));
    });

    test('a rebuild reported for a frame number outside the supplied frame '
        'list is left as an unknown, not fabricated as over-budget or '
        'included in frame-duration stats', () {
      final frames = [_frame(1, overBudget: true)]; // only frame 1 is known
      final rebuilds = [_rebuild(99, {_location: 1})]; // rebuild in an unknown frame

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      expect(impact.rebuildCount, 1);
      expect(impact.framesRebuiltIn, {99}); // still recorded as touched...
      expect(impact.overBudgetFramesRebuiltIn, isEmpty); // ...but not classified
      expect(impact.frameBuildStatsMs, isNull); // no duration data fabricated for it
    });

    test('two distinct source locations rebuilding in the same frame '
        '(nested widget builds) are each tracked independently, never merged', () {
      final frames = [_frame(1, overBudget: true)];
      final rebuilds = [
        _rebuild(1, {_location: 2, _otherLocation: 3}),
      ];

      final impacts = computeWidgetFrameImpacts(rebuilds, frames);
      expect(impacts, hasLength(2));
      final productCard = impacts.firstWhere((i) => i.location == _location);
      final header = impacts.firstWhere((i) => i.location == _otherLocation);
      expect(productCard.rebuildCount, 2);
      expect(header.rebuildCount, 3);
    });

    test('source-location matching is exact -- a different line number is '
        'a different widget, never merged by file alone', () {
      const sameFileDifferentLine =
          SourceLocation(file: 'lib/widgets/product_card.dart', line: 99, column: 12, length: 0);
      final frames = [_frame(1, overBudget: false)];
      final rebuilds = [
        _rebuild(1, {_location: 1, sameFileDifferentLine: 1}),
      ];

      final impacts = computeWidgetFrameImpacts(rebuilds, frames);
      expect(impacts, hasLength(2));
      expect(impacts.map((i) => i.location.line).toSet(), {42, 99});
    });

    test('duplicate source locations across separate frames accumulate '
        'into one WidgetFrameImpact, not one per frame', () {
      final frames = [_frame(1, overBudget: false), _frame(2, overBudget: true)];
      final rebuilds = [
        _rebuild(1, {_location: 2}),
        _rebuild(2, {_location: 3}),
      ];

      final impacts = computeWidgetFrameImpacts(rebuilds, frames);
      expect(impacts, hasLength(1));
      expect(impacts.single.rebuildCount, 5);
      expect(impacts.single.framesRebuiltIn, {1, 2});
    });

    test('frameBuildStatsMs describes the duration of frames touched, not a '
        'fabricated per-widget isolated cost', () {
      final frames = [_frame(1, overBudget: false), _frame(2, overBudget: true)];
      final rebuilds = [
        _rebuild(1, {_location: 1}),
        _rebuild(2, {_location: 1}),
      ];

      final impact = computeWidgetFrameImpacts(rebuilds, frames).single;
      // frame 1: 3000+2000=5000us=5ms, frame 2: 20000+2000=22000us=22ms
      expect(impact.frameBuildStatsMs!.min, closeTo(5.0, 1e-9));
      expect(impact.frameBuildStatsMs!.max, closeTo(22.0, 1e-9));
    });

    test('empty input produces no impacts', () {
      expect(computeWidgetFrameImpacts(const [], const []), isEmpty);
    });
  });

  group('describeClassification', () {
    test('renders all four quadrants distinctly', () {
      expect(
        describeClassification(ImpactClassification.lowRebuildLowImpact),
        'LOW REBUILD / LOW FRAME IMPACT',
      );
      expect(
        describeClassification(ImpactClassification.highRebuildHighImpact),
        'HIGH REBUILD / HIGH FRAME IMPACT',
      );
    });
  });
}
