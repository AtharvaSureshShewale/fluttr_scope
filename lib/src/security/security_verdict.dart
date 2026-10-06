import '../model/finding.dart';
import '../model/severity.dart';

/// A plain-language answer to "is this secure or not" — the headline the
/// `security` command leads with, backed by the finding counts rather
/// than an opaque score.
enum SecurityVerdict {
  /// No security findings at all.
  secure,

  /// Only warning/info-level findings — worth a look, nothing confirmed
  /// exploitable found by these checks.
  needsAttention,

  /// At least one error-level finding — a hardcoded secret or a known
  /// CVE in a dependency at the exact locked version, not a stylistic
  /// nitpick.
  critical;

  String get label => switch (this) {
        SecurityVerdict.secure => 'SECURE — no security issues found',
        SecurityVerdict.needsAttention => 'NEEDS ATTENTION',
        SecurityVerdict.critical => 'NOT SECURE — critical issue(s) found',
      };
}

class SecuritySummary {
  final SecurityVerdict verdict;
  final int criticalCount;
  final int warningCount;
  final int infoCount;

  const SecuritySummary({
    required this.verdict,
    required this.criticalCount,
    required this.warningCount,
    required this.infoCount,
  });

  int get totalCount => criticalCount + warningCount + infoCount;
}

/// Summarizes security-category findings (static security rules plus the
/// dependency/OSV audit) into a verdict and severity breakdown.
///
/// This is deliberately just counting, not scoring — the blueprint's own
/// rule is "never ship a black-box number," and a single composite score
/// across unrelated issue types (a hardcoded key vs. a cleartext URL vs.
/// a dependency CVE) would be exactly that.
SecuritySummary summarizeSecurity(List<Finding> findings) {
  final criticalCount = findings.where((f) => f.severity == Severity.error).length;
  final warningCount = findings.where((f) => f.severity == Severity.warning).length;
  final infoCount = findings.where((f) => f.severity == Severity.info).length;

  final verdict = criticalCount > 0
      ? SecurityVerdict.critical
      : (warningCount > 0 || infoCount > 0)
          ? SecurityVerdict.needsAttention
          : SecurityVerdict.secure;

  return SecuritySummary(
    verdict: verdict,
    criticalCount: criticalCount,
    warningCount: warningCount,
    infoCount: infoCount,
  );
}
