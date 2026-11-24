import 'category.dart';
import 'severity.dart';
import 'source_location.dart';

/// Runtime evidence attached to a [Finding] by the correlator, when a
/// runtime measurement's location matches this finding's location exactly.
///
/// Deliberately narrow — just what the runtime probe actually measures
/// (rebuild count). No modeled/estimated fields; the blueprint's own rule
/// is "never fabricate evidence," and a modeled estimate (e.g. an
/// estimated time saving) isn't something this milestone has the data to
/// justify.
class Evidence {
  final int rebuildCount;

  const Evidence({required this.rebuildCount});

  Map<String, Object?> toJson() => {'rebuildCount': rebuildCount};
}

/// One text replacement in the finding's file: [length] characters at
/// [offset] (0-based, in the file as analyzed) become [replacement].
class SourceEdit {
  final int offset;
  final int length;
  final String replacement;

  const SourceEdit({required this.offset, required this.length, required this.replacement});

  int get end => offset + length;

  Map<String, Object?> toJson() => {
        'offset': offset,
        'length': length,
        'replacement': replacement,
      };
}

class Fix {
  final String kind;
  final String description;

  /// The edits that make this fix, all in the finding's file. Empty when the
  /// fix needs a human (`analyze --fix` only applies fixes that have edits).
  final List<SourceEdit> edits;

  const Fix({required this.kind, required this.description, this.edits = const []});

  Map<String, Object?> toJson() => {
        'kind': kind,
        'description': description,
        if (edits.isNotEmpty) 'edits': [for (final e in edits) e.toJson()],
      };
}

class Finding {
  final String ruleId;
  final Category category;
  final Severity severity;
  final String message;
  final SourceLocation location;
  final String? widgetPath;
  final List<Evidence> evidence;
  final Fix? fix;

  /// Where to look for runtime rebuild evidence when [location] itself has
  /// none -- because nothing there rebuilds in Flutter's tracking: a
  /// low-level widget like `Opacity` or `Padding` (only widgets with a
  /// `build` are reported), a key or future created inline, a `setState`
  /// call. These are widgets only ever built when this code runs too, e.g.
  /// the widget it sits directly inside (see `rerunEvidence`). Not part of
  /// the report formats.
  final List<SourceLocation> evidenceLocations;

  const Finding({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.message,
    required this.location,
    this.widgetPath,
    this.evidence = const [],
    this.fix,
    this.evidenceLocations = const [],
  });

  Finding copyWith({Severity? severity, List<Evidence>? evidence}) => Finding(
        ruleId: ruleId,
        category: category,
        severity: severity ?? this.severity,
        message: message,
        location: location,
        widgetPath: widgetPath,
        evidence: evidence ?? this.evidence,
        fix: fix,
        evidenceLocations: evidenceLocations,
      );

  Map<String, Object?> toJson() => {
        'ruleId': ruleId,
        'category': category.name,
        'severity': severity.name,
        'message': message,
        'location': location.toJson(),
        if (widgetPath != null) 'widgetPath': widgetPath,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        if (fix != null) 'fix': fix!.toJson(),
      };
}

extension RuntimeRecordLookup on Finding {
  /// The runtime record for this finding in [byLocation]: the one at its
  /// [Finding.location], or failing that the strongest (by [compare]) at
  /// any of its [Finding.evidenceLocations].
  T? recordIn<T>(Map<SourceLocation, T> byLocation, int Function(T a, T b) compare) {
    final own = byLocation[location];
    if (own != null) return own;
    T? best;
    for (final at in evidenceLocations) {
      final record = byLocation[at];
      if (record != null && (best == null || compare(record, best) > 0)) best = record;
    }
    return best;
  }
}
