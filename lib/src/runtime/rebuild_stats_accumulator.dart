import 'package:path/path.dart' as p;

import '../model/source_location.dart';
import 'rebuild_record.dart';

/// Decodes `Flutter.RebuiltWidgets` extension event payloads (the same
/// events DevTools' "Track widget rebuilds" panel consumes) and accumulates
/// per-location rebuild counts across a capture window.
///
/// Each event only reports a *delta* count since the last export (the
/// framework resets its own counters after every export), and only
/// reports a location's `file:line:column` the first time that location
/// is seen — so both need accumulating across every event in the window,
/// not read from a single event in isolation.
class RebuildStatsAccumulator {
  /// Absolute path to the analyzed project root. Locations reported by the
  /// framework are absolute (or `file://` URIs); this makes them
  /// root-relative, matching the format static findings use.
  final String root;

  final Map<int, SourceLocation> _locationById = {};
  final Map<int, int> _countById = {};

  RebuildStatsAccumulator({required this.root});

  /// Forgets the counts so far but keeps the location table: the framework
  /// sends a location only the first time it's seen, so dropping it would
  /// lose every location already reported. Used to start counting when a
  /// flow begins, excluding app startup.
  void resetCounts() => _countById.clear();

  void addEvent(Map<String, Object?> data) {
    final locations = data['locations'] as Map<String, Object?>?;
    if (locations != null) {
      for (final entry in locations.entries) {
        final relativeFile = _toRelativePath(entry.key);
        final loc = entry.value as Map<String, Object?>;
        final ids = (loc['ids'] as List).cast<int>();
        final lines = (loc['lines'] as List).cast<int>();
        final columns = (loc['columns'] as List).cast<int>();
        for (var i = 0; i < ids.length; i++) {
          _locationById[ids[i]] = SourceLocation(
            file: relativeFile,
            line: lines[i],
            column: columns[i],
            length: 0,
          );
        }
      }
    }

    final events = (data['events'] as List?)?.cast<int>() ?? const [];
    for (var i = 0; i + 1 < events.length; i += 2) {
      final id = events[i];
      final count = events[i + 1];
      _countById[id] = (_countById[id] ?? 0) + count;
    }
  }

  /// Accumulated records so far. A location id with a count but no known
  /// location (shouldn't happen in practice — the framework always sends
  /// the location on a widget's first rebuild — but the event stream is
  /// external input) is silently dropped rather than crashing.
  List<RebuildRecord> get records => [
        for (final entry in _countById.entries)
          if (_locationById[entry.key] != null)
            RebuildRecord(location: _locationById[entry.key]!, rebuildCount: entry.value),
      ];

  String _toRelativePath(String file) {
    var path = file;
    if (path.startsWith('file://')) {
      path = Uri.parse(path).toFilePath();
    }
    try {
      return p.relative(path, from: root).replaceAll('\\', '/');
    } catch (_) {
      return path.replaceAll('\\', '/');
    }
  }
}
