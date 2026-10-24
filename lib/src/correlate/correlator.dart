import '../model/finding.dart';
import '../runtime/rebuild_record.dart';

/// Result of joining static findings to runtime rebuild records.
class CorrelationResult {
  /// The input findings, with [Finding.evidence] filled in wherever a
  /// runtime record's location matched exactly.
  final List<Finding> findings;

  /// Runtime records whose location matched no static finding — a widget
  /// rebuilding with no rule explaining why. Often the most interesting
  /// output: not a fabricated finding (there's no rule violation to
  /// report), just the raw evidence surfaced on its own.
  final List<RebuildRecord> unexplainedRebuilds;

  const CorrelationResult({required this.findings, required this.unexplainedRebuilds});
}

/// Joins static [Finding]s to runtime [RebuildRecord]s by exact
/// `file:line:column` match — the join key both sides already use
/// (verified end to end: `missing_const_constructor`'s finding location
/// and its widget's runtime rebuild location land on the identical key).
///
/// Deliberately simple: attaches evidence where locations match, leaves
/// everything else untouched. No severity escalation — that would need a
/// calibrated threshold (how many rebuilds is "bad"?) this project has no
/// data to justify yet, and inventing one would be exactly the kind of
/// fabricated-looking number the blueprint warns against.
class Correlator {
  CorrelationResult correlate(List<Finding> findings, List<RebuildRecord> runtimeRecords) {
    final byLocation = {for (final r in runtimeRecords) r.location: r};
    final matchedLocations = <Object>{};

    final correlated = [
      for (final finding in findings)
        if (finding.recordIn(byLocation, (a, b) => a.rebuildCount.compareTo(b.rebuildCount))
            case final record?)
          _withEvidence(finding, record, onMatch: () => matchedLocations.add(record.location))
        else
          finding,
    ];

    final unexplained = [
      for (final record in runtimeRecords)
        if (!matchedLocations.contains(record.location)) record,
    ];

    return CorrelationResult(findings: correlated, unexplainedRebuilds: unexplained);
  }

  Finding _withEvidence(
    Finding finding,
    RebuildRecord record, {
    required void Function() onMatch,
  }) {
    onMatch();
    return finding.copyWith(evidence: [Evidence(rebuildCount: record.rebuildCount)]);
  }
}
