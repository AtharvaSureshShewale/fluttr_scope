import '../model/source_location.dart';

/// How many times the widget at [location] rebuilt during a capture window.
class RebuildRecord {
  final SourceLocation location;
  final int rebuildCount;

  const RebuildRecord({required this.location, required this.rebuildCount});

  Map<String, Object?> toJson() => {
        'location': location.toJson(),
        'rebuildCount': rebuildCount,
      };

  factory RebuildRecord.fromJson(Map<String, Object?> json) => RebuildRecord(
        location: SourceLocation.fromJson(json['location'] as Map<String, Object?>),
        rebuildCount: json['rebuildCount'] as int,
      );
}
