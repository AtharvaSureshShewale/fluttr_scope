import 'package:path/path.dart' as p;

import '../model/source_location.dart';

/// One frame's worth of rebuild counts by location, as reported by a
/// single `Flutter.RebuiltWidgets` event.
///
/// `WidgetInspectorService._onFrameEnd` posts exactly one of these events
/// per rendered frame (a post-frame callback registered in
/// `_onFrameStart`), and the payload carries the frame's own
/// `PlatformDispatcher`-derived frame number directly (see
/// `_ElementLocationStatsTracker.exportToJson` in the framework source) --
/// the same numbering `Flutter.Frame` events use. So [frameNumber] here is
/// an *exact* join key against [FrameMetrics.frameNumber], not a fuzzy or
/// inferred one.
class FrameRebuildRecord {
  final int frameNumber;

  /// Rebuild count by location, for this frame only. A location can
  /// appear with count > 1: multiple sibling widget *instances* sharing
  /// the same creation location (e.g. list items built from the same
  /// source line) each count independently, and there's no per-instance
  /// id in this event stream to tell them apart -- "identity" here is the
  /// creation location, not a specific widget instance.
  final Map<SourceLocation, int> countsByLocation;

  const FrameRebuildRecord({required this.frameNumber, required this.countsByLocation});

  Map<String, Object?> toJson() => {
        'frameNumber': frameNumber,
        'counts': [
          for (final entry in countsByLocation.entries)
            {'location': entry.key.toJson(), 'count': entry.value},
        ],
      };

  factory FrameRebuildRecord.fromJson(Map<String, Object?> json) => FrameRebuildRecord(
        frameNumber: json['frameNumber'] as int,
        countsByLocation: {
          for (final entry in json['counts'] as List)
            SourceLocation.fromJson((entry as Map<String, Object?>)['location'] as Map<String, Object?>):
                entry['count'] as int,
        },
      );
}

/// Decodes `Flutter.RebuiltWidgets` extension event payloads while
/// preserving per-frame granularity -- unlike [RebuildStatsAccumulator],
/// which collapses everything into one whole-window sum. Kept as a
/// separate accumulator (not a modification of the existing one) so nothing
/// about the already-verified rebuild-count/trust-milestone behavior changes.
class FrameRebuildAccumulator {
  /// Absolute path to the analyzed project root, for the same
  /// root-relative path normalization [RebuildStatsAccumulator] does.
  final String root;

  final Map<int, SourceLocation> _locationById = {};
  final List<FrameRebuildRecord> _records = [];

  FrameRebuildAccumulator({required this.root});

  /// Forgets the per-frame records so far but keeps the location table
  /// (see [RebuildStatsAccumulator.resetCounts]).
  void resetRecords() => _records.clear();

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

    final frameNumber = data['frameNumber'] as int?;
    if (frameNumber == null) return; // Older/unexpected payload shape -- drop, don't guess.

    final events = (data['events'] as List?)?.cast<int>() ?? const [];
    final countsByLocation = <SourceLocation, int>{};
    for (var i = 0; i + 1 < events.length; i += 2) {
      final id = events[i];
      final count = events[i + 1];
      final location = _locationById[id];
      // A location id with no known location (shouldn't happen -- the
      // framework always sends it on first use -- but the event stream is
      // external input) is silently dropped rather than crashing.
      if (location == null) continue;
      countsByLocation[location] = (countsByLocation[location] ?? 0) + count;
    }
    if (countsByLocation.isNotEmpty) {
      _records.add(FrameRebuildRecord(frameNumber: frameNumber, countsByLocation: countsByLocation));
    }
  }

  /// One [FrameRebuildRecord] per `Flutter.RebuiltWidgets` event that
  /// reported at least one rebuild, in receipt order.
  List<FrameRebuildRecord> get records => List.unmodifiable(_records);

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
