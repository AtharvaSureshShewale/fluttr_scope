import 'package:fluttr_scope/src/runtime/frame_rebuild_accumulator.dart';
import 'package:test/test.dart';

void main() {
  group('FrameRebuildAccumulator', () {
    late FrameRebuildAccumulator accumulator;

    setUp(() {
      accumulator = FrameRebuildAccumulator(root: '/project');
    });

    test('decodes one location and count for a given frame number', () {
      accumulator.addEvent({
        'frameNumber': 42,
        'startTime': 1000,
        'events': [1, 3],
        'locations': {
          '/project/lib/foo.dart': {
            'ids': [1],
            'lines': [10],
            'columns': [5],
          },
        },
      });

      expect(accumulator.records, hasLength(1));
      final record = accumulator.records.single;
      expect(record.frameNumber, 42);
      expect(record.countsByLocation.values.single, 3);
      expect(record.countsByLocation.keys.single.file, 'lib/foo.dart');
      expect(record.countsByLocation.keys.single.line, 10);
    });

    test('preserves per-frame granularity across multiple events -- does '
        'not collapse into one whole-window sum', () {
      accumulator.addEvent({
        'frameNumber': 1,
        'startTime': 0,
        'events': [1, 2],
        'locations': {
          '/project/lib/foo.dart': {
            'ids': [1],
            'lines': [10],
            'columns': [5],
          },
        },
      });
      accumulator.addEvent({
        'frameNumber': 2,
        'startTime': 16667,
        'events': [1, 5],
      });

      expect(accumulator.records, hasLength(2));
      expect(accumulator.records[0].frameNumber, 1);
      expect(accumulator.records[0].countsByLocation.values.single, 2);
      expect(accumulator.records[1].frameNumber, 2);
      expect(accumulator.records[1].countsByLocation.values.single, 5);
    });

    test('a location introduced in an earlier event is remembered for '
        'later events that only reference it by id', () {
      accumulator.addEvent({
        'frameNumber': 1,
        'events': [7, 1],
        'locations': {
          '/project/lib/bar.dart': {
            'ids': [7],
            'lines': [20],
            'columns': [3],
          },
        },
      });
      accumulator.addEvent({'frameNumber': 2, 'events': [7, 1]});

      expect(accumulator.records[1].countsByLocation.keys.single.file, 'lib/bar.dart');
    });

    test('multiple locations rebuilding within the same frame are all '
        'captured for that one frame', () {
      accumulator.addEvent({
        'frameNumber': 9,
        'events': [1, 2, 2, 4],
        'locations': {
          '/project/lib/a.dart': {
            'ids': [1],
            'lines': [1],
            'columns': [1],
          },
          '/project/lib/b.dart': {
            'ids': [2],
            'lines': [2],
            'columns': [2],
          },
        },
      });

      final counts = accumulator.records.single.countsByLocation;
      expect(counts.length, 2);
      expect(counts.entries.firstWhere((e) => e.key.file == 'lib/a.dart').value, 2);
      expect(counts.entries.firstWhere((e) => e.key.file == 'lib/b.dart').value, 4);
    });

    test('an event with no frameNumber field is dropped, not guessed', () {
      accumulator.addEvent({
        'events': [1, 3],
        'locations': {
          '/project/lib/foo.dart': {
            'ids': [1],
            'lines': [10],
            'columns': [5],
          },
        },
      });
      expect(accumulator.records, isEmpty);
    });

    test('an event with an unknown location id is silently dropped, not crashed on', () {
      accumulator.addEvent({'frameNumber': 1, 'events': [999, 5]});
      expect(accumulator.records, isEmpty);
    });

    test('an event with no rebuilds at all produces no record', () {
      accumulator.addEvent({'frameNumber': 1, 'events': <int>[]});
      expect(accumulator.records, isEmpty);
    });
  });

  group('FrameRebuildRecord JSON', () {
    test('round-trips through JSON', () {
      final accumulator = FrameRebuildAccumulator(root: '/project');
      accumulator.addEvent({
        'frameNumber': 5,
        'events': [1, 3],
        'locations': {
          '/project/lib/foo.dart': {
            'ids': [1],
            'lines': [10],
            'columns': [5],
          },
        },
      });
      final record = accumulator.records.single;
      final restored = FrameRebuildRecord.fromJson(record.toJson());

      expect(restored.frameNumber, 5);
      expect(restored.countsByLocation.values.single, 3);
      expect(restored.countsByLocation.keys.single.file, 'lib/foo.dart');
    });
  });
}
