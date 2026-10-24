import '../model/severity.dart';
import '../runtime/stats.dart';
import 'triage.dart';

/// What a triage report was measured under, for its header.
class TriageContext {
  final String device;
  final int validRuns;
  final int requestedRuns;
  final Duration captureDuration;
  final Duration warmup;
  final Confidence? overallConfidence;

  /// The flow file that drove the runs (`--flow`), or `null` if none did.
  final String? flow;

  const TriageContext({
    required this.device,
    required this.validRuns,
    required this.requestedRuns,
    required this.captureDuration,
    required this.warmup,
    required this.overallConfidence,
    this.flow,
  });
}

String _evidenceLabel(RuntimeEvidence e) => switch (e) {
      RuntimeEvidence.hot => 'performance finding(s) whose widget rebuilt during slow frames',
      RuntimeEvidence.ran => 'ran during the session',
      RuntimeEvidence.notRun => 'never ran in this session',
      RuntimeEvidence.noSignal => 'no runtime signal (config files, constants, tests)',
    };

String _icon(RuntimeEvidence e) => switch (e) {
      RuntimeEvidence.hot => '🔥',
      RuntimeEvidence.ran => '▶',
      RuntimeEvidence.notRun => '○',
      RuntimeEvidence.noSignal => '—',
    };

/// Renders [triaged] (already sorted by [triageFindings]) as the console
/// report. Runtime evidence *ranks* findings; it never hides an error or
/// warning -- those are always listed, with or without evidence. Infos
/// are listed only when they ran during slow frames, unless [showAll].
String formatTriageReport(
  List<TriagedFinding> triaged,
  TriageContext context, {
  bool showAll = false,
}) {
  final buffer = StringBuffer();
  buffer.writeln('WHAT TO FIX FIRST');
  buffer.writeln('-' * 17);
  final how = context.flow == null
      ? 'x ${context.captureDuration.inSeconds}s'
      : 'driven by ${context.flow} (each stopped when the flow finished)';
  buffer.writeln(
    'Measured: ${context.validRuns} of ${context.requestedRuns} run(s) $how on ${context.device}, '
    'debug mode'
    '${context.warmup > Duration.zero ? ' (${context.warmup.inSeconds}s warm-up excluded from frame stats)' : ''}',
  );
  if (context.overallConfidence case final c?) {
    buffer.writeln('Frame-timing confidence: ${c.name.toUpperCase()}');
  }
  buffer.writeln();

  final byEvidence = {
    for (final e in RuntimeEvidence.values) e: triaged.where((t) => t.evidence == e).toList(),
  };
  final width = triaged.length.toString().length;
  for (final e in RuntimeEvidence.values) {
    buffer.writeln('  ${_icon(e)}  ${byEvidence[e]!.length.toString().padLeft(width)}  ${_evidenceLabel(e)}');
  }

  bool shown(TriagedFinding t) =>
      showAll || t.evidence == RuntimeEvidence.hot || t.finding.severity != Severity.info;

  void section(String title, List<TriagedFinding> items, {String? intro}) {
    final visible = items.where(shown).toList();
    if (visible.isEmpty) return;
    buffer.writeln();
    buffer.writeln(title);
    if (intro != null) buffer.writeln('  $intro');
    for (final t in visible) {
      _writeFinding(buffer, t);
    }
  }

  section('🔥 REBUILT DURING SLOW FRAMES -- fix these first', byEvidence[RuntimeEvidence.hot]!);
  section('▶ RAN DURING THE SESSION', byEvidence[RuntimeEvidence.ran]!);
  section(
    '⚠ ERRORS AND WARNINGS WITHOUT RUNTIME EVIDENCE',
    [...byEvidence[RuntimeEvidence.notRun]!, ...byEvidence[RuntimeEvidence.noSignal]!],
    intro: 'Not exercised by this session, or not code the app runs -- runtime evidence '
        'ranks findings, it doesn\'t excuse them.',
  );

  final hidden = triaged.where((t) => !shown(t)).length;
  if (hidden > 0) {
    buffer.writeln();
    buffer.writeln('$hidden info finding(s) not listed (--all to show them).');
  }
  if (byEvidence[RuntimeEvidence.hot]!.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Rebuilding during slow frames is an observed association, not proof that '
        'this code caused them.');
  }
  return buffer.toString();
}

void _writeFinding(StringBuffer buffer, TriagedFinding t) {
  final f = t.finding;
  buffer.writeln('  ${_icon(t.evidence)} ${f.location}  ${f.severity.name}  ${f.ruleId}');
  buffer.writeln('      ${f.message}');
  final impact = t.impact;
  if (impact != null) {
    // Evidence from another location (see Finding.evidenceLocations) names
    // it, so the count isn't read as this exact line's.
    final at = impact.location.file == f.location.file
        ? 'line ${impact.location.line}'
        : '${impact.location}';
    final where = impact.location == f.location
        ? 'Rebuilt'
        : 'Measured at $at (nothing at this line is tracked): rebuilt';
    buffer.writeln(
      '      $where ${impact.rebuildCountStats.median.round()}x (median of ${impact.totalRuns} '
      'run(s)); ${impact.overBudgetFrameCountStats.median.round()} of '
      '${impact.framesTouchedStats.median.round()} frames it rebuilt in were slow '
      '(confidence ${impact.confidence.name}).',
    );
  }
}
