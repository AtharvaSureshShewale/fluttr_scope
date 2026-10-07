import '../model/category.dart';
import '../model/finding.dart';
import '../model/source_location.dart';
import '../runtime/executed_lines.dart';
import '../runtime/rebuild_frame_correlation.dart';
import '../runtime/stats.dart';
import '../runtime/widget_frame_impact.dart';

/// How much runtime evidence backs a static finding -- the order to look
/// at findings in, most urgent first.
enum RuntimeEvidence {
  /// A performance finding whose widget rebuilt during slow frames.
  hot,

  /// This code ran during the session.
  ran,

  /// This code was loaded but never ran, or its file was never loaded.
  notRun,

  /// Nothing to go on: not Dart code the app runs (manifests,
  /// `pubspec.lock`, tests), or a line coverage doesn't track (a constant).
  noSignal,
}

class TriagedFinding {
  final Finding finding;
  final RuntimeEvidence evidence;

  /// Rebuild/frame evidence at this exact location, if the widget there
  /// rebuilt at all.
  final WidgetFrameImpactSummary? impact;

  const TriagedFinding({required this.finding, required this.evidence, this.impact});

  Map<String, Object?> toJson() => {
        ...finding.toJson(),
        'runtimeEvidence': evidence.name,
        if (impact != null) 'runtimeImpact': impact!.toJson(),
      };
}

/// Sorts static [findings] by runtime evidence: widget rebuild/frame
/// impact at the finding's exact location ([impacts]) and which lines ran
/// ([executedLines]). Within each [RuntimeEvidence] group, higher severity
/// first, then more rebuilds.
///
/// [sourceLines] returns a file's lines (root-relative path), or `null` if
/// unreadable -- used to find where a multi-line finding's span ends, so
/// a finding on a whole method counts as run if any of its lines ran.
List<TriagedFinding> triageFindings(
  List<Finding> findings, {
  required List<WidgetFrameImpactSummary> impacts,
  required ExecutedLines? executedLines,
  required List<String>? Function(String file) sourceLines,
}) {
  final impactByLocation = {for (final i in impacts) i.location: i};
  final triaged = [
    for (final f in findings)
      _triage(f, impactByLocation[f.location], executedLines, sourceLines),
  ];
  triaged.sort(_byPriority);
  return triaged;
}

TriagedFinding _triage(
  Finding finding,
  WidgetFrameImpactSummary? impact,
  ExecutedLines? executed,
  List<String>? Function(String file) sourceLines,
) {
  TriagedFinding result(RuntimeEvidence e) =>
      TriagedFinding(finding: finding, evidence: e, impact: impact);

  if (impact != null) {
    // Slow frames are only evidence *for* a performance finding. A missing
    // semantic label on an image that happened to be on screen while
    // scrolling was slow says nothing about the label -- for any other
    // category, rebuild data just proves the code ran.
    final slowFrames = impact.classification == ImpactClassification.highRebuildHighImpact ||
        impact.classification == ImpactClassification.lowRebuildHighImpact;
    final hot = finding.category == Category.performance &&
        slowFrames &&
        impact.confidence != Confidence.low;
    return result(hot ? RuntimeEvidence.hot : RuntimeEvidence.ran);
  }

  final loc = finding.location;
  if (executed == null || !loc.file.endsWith('.dart')) return result(RuntimeEvidence.noSignal);
  if (!executed.hasFile(loc.file)) {
    // An app library the VM never loaded can't have run; anything outside
    // lib/ (tests, tools) was never part of the app to begin with.
    return result(loc.file.startsWith('lib/') ? RuntimeEvidence.notRun : RuntimeEvidence.noSignal);
  }

  final lastLine = _endLine(loc, sourceLines(loc.file));
  var missed = false;
  for (var line = loc.line; line <= lastLine; line++) {
    if (executed.wasHit(loc.file, line)) return result(RuntimeEvidence.ran);
    if (executed.wasMissed(loc.file, line)) missed = true;
  }
  return result(missed ? RuntimeEvidence.notRun : RuntimeEvidence.noSignal);
}

/// The 1-based line [loc]'s span ends on: its start line plus however many
/// line breaks its `length` characters cross. Falls back to the start line
/// when the source isn't available or doesn't match.
int _endLine(SourceLocation loc, List<String>? lines) {
  if (lines == null || loc.line > lines.length) return loc.line;
  var remaining = loc.length - (lines[loc.line - 1].length - (loc.column - 1));
  var line = loc.line;
  while (remaining > 0 && line < lines.length) {
    remaining -= lines[line].length + 1; // +1 for the line break
    line++;
  }
  return line;
}

int _byPriority(TriagedFinding a, TriagedFinding b) {
  final byEvidence = a.evidence.index.compareTo(b.evidence.index);
  if (byEvidence != 0) return byEvidence;
  final bySeverity = b.finding.severity.index.compareTo(a.finding.severity.index);
  if (bySeverity != 0) return bySeverity;
  final aRebuilds = a.impact?.rebuildCountStats.median ?? 0;
  final bRebuilds = b.impact?.rebuildCountStats.median ?? 0;
  return bRebuilds.compareTo(aRebuilds);
}
