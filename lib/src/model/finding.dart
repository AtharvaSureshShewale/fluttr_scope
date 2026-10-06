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

class Fix {
  final String kind;
  final String description;

  const Fix({required this.kind, required this.description});

  Map<String, Object?> toJson() => {
        'kind': kind,
        'description': description,
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

  const Finding({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.message,
    required this.location,
    this.widgetPath,
    this.evidence = const [],
    this.fix,
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
