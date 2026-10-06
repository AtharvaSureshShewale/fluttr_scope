import 'package:fluttr_scope/src/runtime/rebuild_stats_accumulator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Absolute paths in the host OS's own form: the framework reports
// locations as native absolute paths (or file:// URIs), so hardcoding
// `C:\project` only works on Windows.
final _root = p.join(p.rootPrefix(p.current), 'project');
String _native(String relative) => p.joinAll([_root, ...relative.split('/')]);
String _fileUri(String relative) => p.toUri(_native(relative)).toString();

void main() {
  test('accumulates counts across multiple events for the same location', () {
    final acc = RebuildStatsAccumulator(root: _root);

    acc.addEvent({
      'startTime': 0,
      'frameNumber': 1,
      'events': [0, 3],
      'locations': {
        _native('lib/main.dart'): {
          'ids': [0],
          'lines': [42],
          'columns': [12],
          'names': ['Text'],
        },
      },
    });

    // Second event for the same id carries no 'locations' key (the
    // framework only sends a location the first time it's seen) — the
    // count must still ADD to the first event's, not replace it.
    acc.addEvent({
      'startTime': 1000,
      'frameNumber': 2,
      'events': [0, 5],
    });

    final records = acc.records;
    expect(records, hasLength(1));
    expect(records.single.rebuildCount, 8);
    expect(records.single.location.file, 'lib/main.dart');
    expect(records.single.location.line, 42);
    expect(records.single.location.column, 12);
  });

  test('normalizes a file:// URI to a root-relative path', () {
    final acc = RebuildStatsAccumulator(root: _root);
    acc.addEvent({
      'events': [0, 1],
      'locations': {
        _fileUri('lib/widgets/foo.dart'): {
          'ids': [0],
          'lines': [1],
          'columns': [1],
          'names': ['Foo'],
        },
      },
    });
    expect(acc.records.single.location.file, 'lib/widgets/foo.dart');
  });

  test('tracks multiple distinct locations in the same file independently', () {
    final acc = RebuildStatsAccumulator(root: _root);
    acc.addEvent({
      'events': [0, 2, 1, 7],
      'locations': {
        _native('lib/main.dart'): {
          'ids': [0, 1],
          'lines': [10, 20],
          'columns': [5, 9],
          'names': ['A', 'B'],
        },
      },
    });
    final byLine = {for (final r in acc.records) r.location.line: r.rebuildCount};
    expect(byLine, {10: 2, 20: 7});
  });

  test('an empty event stream produces no records', () {
    final acc = RebuildStatsAccumulator(root: _root);
    expect(acc.records, isEmpty);
  });
}
