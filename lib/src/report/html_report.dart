/// Self-contained HTML reports: one file, no scripts, no network, readable
/// in light and dark mode and on a phone. Shared by `analyze`, `prioritize`
/// and `compare` (`--format html`).
library;

import '../compare/compare.dart';
import '../model/finding.dart';
import '../model/severity.dart';
import '../triage/triage.dart';
import '../triage/triage_report.dart';
import '../version.dart';

/// A file's lines (root-relative path), or `null` if it can't be read.
typedef SourceLines = List<String>? Function(String file);

/// `prioritize --format html`: findings ranked by runtime evidence, with
/// the code around each one.
String htmlTriageReport(
  List<TriagedFinding> triaged,
  TriageContext context, {
  required SourceLines sourceLines,
  bool showAll = false,
}) {
  final body = StringBuffer();
  final how = context.flow == null
      ? '${context.validRuns} of ${context.requestedRuns} run(s) of '
          '${context.captureDuration.inSeconds}s'
      : '${context.validRuns} of ${context.requestedRuns} run(s) driven by '
          '<code>${_e(context.flow!)}</code>';
  body.writeln('<p class="meta">Measured $how on <code>${_e(context.device)}</code>, debug mode'
      '${context.overallConfidence == null ? '' : ' · frame-timing confidence '
          '<b>${context.overallConfidence!.name}</b>'}</p>');

  final groups = {
    for (final e in RuntimeEvidence.values) e: triaged.where((t) => t.evidence == e).toList(),
  };
  body.writeln('<div class="tiles">');
  for (final (e, label, css) in const [
    (RuntimeEvidence.hot, 'rebuilt during slow frames', 'hot'),
    (RuntimeEvidence.ran, 'ran during the session', 'ran'),
    (RuntimeEvidence.notRun, 'never ran', 'idle'),
    (RuntimeEvidence.noSignal, 'no runtime signal', 'idle'),
  ]) {
    body.writeln('<div class="tile $css"><span class="num">${groups[e]!.length}</span>'
        '<span>$label</span></div>');
  }
  body.writeln('</div>');

  bool shown(TriagedFinding t) =>
      showAll || t.evidence == RuntimeEvidence.hot || t.finding.severity != Severity.info;

  void section(String title, List<TriagedFinding> items, {String? intro, bool open = true}) {
    final visible = items.where(shown).toList();
    if (visible.isEmpty) return;
    body.writeln('<details${open ? ' open' : ''}><summary><h2>$title '
        '<span class="count">${visible.length}</span></h2></summary>');
    if (intro != null) body.writeln('<p class="intro">$intro</p>');
    for (final t in visible) {
      body.write(_findingCard(t.finding, sourceLines, evidence: _impactText(t), hot: t.evidence == RuntimeEvidence.hot));
    }
    body.writeln('</details>');
  }

  section('🔥 Fix these first: rebuilt during slow frames', groups[RuntimeEvidence.hot]!);
  section('▶ Ran during the session', groups[RuntimeEvidence.ran]!);
  section(
    'Errors and warnings without runtime evidence',
    [...groups[RuntimeEvidence.notRun]!, ...groups[RuntimeEvidence.noSignal]!],
    intro: 'Not exercised by this session, or not code the app runs. Runtime evidence ranks '
        'findings; it doesn\'t excuse them.',
    open: false,
  );
  final hidden = triaged.where((t) => !shown(t)).length;
  if (hidden > 0) {
    body.writeln('<p class="note">$hidden info finding(s) not listed (<code>--all</code> '
        'to include them).</p>');
  }
  if (groups[RuntimeEvidence.hot]!.isNotEmpty) {
    body.writeln('<p class="note">Rebuilding during slow frames is an observed association, '
        'not proof that this code caused them.</p>');
  }
  return _page('What to fix first', body.toString());
}

/// `analyze --format html`: findings grouped by file.
String htmlFindingsReport(List<Finding> findings, {required SourceLines sourceLines}) {
  final body = StringBuffer();
  final bySeverity = {for (final s in Severity.values) s: findings.where((f) => f.severity == s).length};
  final fixable = findings.where((f) => f.fix?.edits.isNotEmpty ?? false).length;
  body.writeln('<div class="tiles">');
  for (final (s, css) in const [
    (Severity.error, 'hot'),
    (Severity.warning, 'warn'),
    (Severity.info, 'idle'),
  ]) {
    body.writeln('<div class="tile $css"><span class="num">${bySeverity[s]}</span>'
        '<span>${s.name}${bySeverity[s] == 1 ? '' : 's'}</span></div>');
  }
  body.writeln('<div class="tile ran"><span class="num">$fixable</span>'
      '<span>fixable with <code>--fix</code></span></div>');
  body.writeln('</div>');

  if (findings.isEmpty) body.writeln('<p class="intro">No findings.</p>');
  final byFile = <String, List<Finding>>{};
  for (final f in findings) {
    byFile.putIfAbsent(f.location.file, () => []).add(f);
  }
  for (final MapEntry(key: file, value: inFile) in byFile.entries) {
    final worst = inFile.map((f) => f.severity.index).reduce((a, b) => a < b ? a : b);
    body.writeln('<details${worst == Severity.error.index ? ' open' : ''}><summary><h2>'
        '<code>${_e(file)}</code> <span class="count">${inFile.length}</span></h2></summary>');
    for (final f in inFile) {
      body.write(_findingCard(f, sourceLines));
    }
    body.writeln('</details>');
  }
  return _page('Findings', body.toString());
}

/// `compare --format html`: before vs after, with bars for rebuilds per file.
String htmlComparisonReport(Comparison comparison, {int maxFiles = 15}) {
  final body = StringBuffer();
  body.writeln('<p class="meta"><code>${_e(comparison.beforeLabel)}</code> → '
      '<code>${_e(comparison.afterLabel)}</code></p>');
  for (final w in comparison.warnings) {
    body.writeln('<p class="warning">⚠ ${_e(w)}</p>');
  }

  body.writeln('<div class="table-wrap"><table><thead><tr><th>Metric</th><th class="n">Before</th><th class="n">After</th>'
      '<th>Change</th></tr></thead><tbody>');
  for (final m in comparison.headline) {
    body.writeln('<tr><td>${_e(m.name)}</td><td class="n">${_metric(m.beforeMedian, m.unit)}</td>'
        '<td class="n">${_metric(m.afterMedian, m.unit)}</td><td>${_verdict(m)}</td></tr>');
  }
  body.writeln('</tbody></table></div><p class="note">Medians across runs.</p>');

  final changed = comparison.byFile
      .where((m) => m.change == Change.better || m.change == Change.worse)
      .where((m) => (m.percentChange?.abs() ?? double.infinity) >= minFileChangePercent)
      .take(maxFiles)
      .toList();
  if (changed.isNotEmpty) {
    final scale = changed
        .expand((m) => [m.beforeMedian, m.afterMedian])
        .reduce((a, b) => a > b ? a : b);
    body.writeln('<h2>Rebuilds by file</h2><p class="intro">Files that changed by more than '
        'the runs vary, and by $minFileChangePercent% or more.</p><div class="bars">');
    for (final m in changed) {
      double w(double v) => scale == 0 ? 0 : v / scale * 100;
      body.writeln('<div class="bar-row"><div class="bar-label"><code>${_e(m.name)}</code> '
          '${_verdict(m)}</div>'
          '<div class="bar before" style="width:${w(m.beforeMedian).toStringAsFixed(1)}%">'
          '<span>before ${_metric(m.beforeMedian, '')}</span></div>'
          '<div class="bar after ${m.change.name}" style="width:${w(m.afterMedian).toStringAsFixed(1)}%">'
          '<span>after ${_metric(m.afterMedian, '')}</span></div></div>');
    }
    body.writeln('</div>');
  }
  body.writeln('<p class="note">"Better" or "worse" means every run after beat (or lost to) '
      'every run before. Anything else is "no clear change": it could be noise.</p>');
  return _page('Before vs after', body.toString());
}

String _impactText(TriagedFinding t) {
  final impact = t.impact;
  if (impact == null) return '';
  final f = t.finding;
  final where = impact.location == f.location
      ? 'Rebuilt'
      : 'Measured at ${_e(displayPath(impact.location.toString()))} (nothing at this line is '
          'tracked): rebuilt';
  return '$where <b>${impact.rebuildCountStats.median.round()}×</b> (median of '
      '${impact.totalRuns} runs); <b>${impact.overBudgetFrameCountStats.median.round()}</b> of '
      '${impact.framesTouchedStats.median.round()} frames it rebuilt in were slow '
      '(confidence ${impact.confidence.name}).';
}

String _findingCard(Finding f, SourceLines sourceLines, {String evidence = '', bool hot = false}) {
  final fixable = f.fix?.edits.isNotEmpty ?? false;
  final out = StringBuffer()
    ..writeln('<article class="finding ${f.severity.name}${hot ? ' is-hot' : ''}">')
    ..writeln('<header><span class="sev">${f.severity.name}</span> <code class="rule">'
        '${_e(f.ruleId)}</code>${fixable ? ' <span class="fix">auto-fixable</span>' : ''}'
        '<span class="loc"><code>${_e(displayPath(f.location.toString()))}</code></span></header>')
    ..writeln('<p>${_inlineCode(f.message)}</p>');
  if (evidence.isNotEmpty) out.writeln('<p class="evidence">$evidence</p>');
  final snippet = _snippet(sourceLines(f.location.file), f.location.line,
      mask: _secretRules.contains(f.ruleId));
  if (snippet != null) out.writeln(snippet);
  out.writeln('</article>');
  return out.toString();
}

/// Two lines either side of [line] (1-based), [line] highlighted. With
/// [mask], string literals are shortened to their first characters.
String? _snippet(List<String>? lines, int line, {bool mask = false}) {
  if (lines == null || line < 1 || line > lines.length) return null;
  final from = line - 2 < 1 ? 1 : line - 2;
  final to = line + 2 > lines.length ? lines.length : line + 2;
  final rows = StringBuffer('<pre class="code">');
  for (var n = from; n <= to; n++) {
    final text = mask ? _maskStrings(lines[n - 1]) : lines[n - 1];
    rows.write('<span class="ln${n == line ? ' hl' : ''}"><i>$n</i>${_e(text)}</span>');
  }
  rows.write('</pre>');
  return rows.toString();
}

/// Rules whose code is likely to hold a real secret. Reports are made to
/// be shared, so their snippets show only enough of each string to tell
/// which one it is.
const _secretRules = {
  'hardcoded_secret',
  'sensitive_query_param',
  'avoid_logging_sensitive_data',
  'insecure_storage_of_sensitive_data',
};

/// A single- or double-quoted string literal on one line.
final _stringLiteral = RegExp(r'''(['"])((?:\\.|(?!\1).)*)\1''');

/// String literals in [line] cut to their first 4 characters:
/// `'dxqHsX7I0URA'` -> `'dxqH••••'`.
String _maskStrings(String line) => line.replaceAllMapped(_stringLiteral, (m) {
      final quote = m[1]!, content = m[2]!;
      return content.length <= 4 ? m[0]! : '$quote${content.substring(0, 4)}••••$quote';
    });

String _verdict(MetricComparison m) {
  final pct = m.percentChange == null
      ? ''
      : ' (${m.percentChange! >= 0 ? '+' : ''}${m.percentChange!.toStringAsFixed(0)}%)';
  return switch (m.change) {
    Change.better => '<span class="v better">✅ better$pct</span>',
    Change.worse => '<span class="v worse">❌ worse$pct</span>',
    Change.noClearChange => '<span class="v unclear">no clear change$pct</span>',
    Change.tooFewRuns => '<span class="v unclear">too few runs to tell</span>',
  };
}

String _metric(double v, String unit) {
  final text = v == v.roundToDouble() ? _grouped(v.round()) : v.toStringAsFixed(1);
  return unit.isEmpty ? text : unit == '%' ? '$text%' : '$text $unit';
}

/// 4611 -> 4,611.
String _grouped(int n) {
  final digits = n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return n < 0 ? '-$digits' : digits;
}

/// [text] HTML-escaped, with `backtick spans` as `<code>`.
String _inlineCode(String text) =>
    _e(text).replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m[1]}</code>');

String _e(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _page(String title, String body) => '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fluttr_scope · $title</title>
<style>
:root{--bg:#ffffff;--fg:#1f2328;--muted:#59636e;--card:#f6f8fa;--line:#d1d9e0;--code:#eff2f5;
--hot:#cf222e;--warn:#9a6700;--ok:#1a7f37;--blue:#0969da;--hl:#fff8c5;--bar:#8c959f}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#9198a1;--card:#151b23;
--line:#30363d;--code:#1f2630;--hot:#f85149;--warn:#d29922;--ok:#3fb950;--blue:#58a6ff;--hl:#3d3418;--bar:#6e7681}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
main{max-width:980px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:26px;margin:0 0 4px}h1 small{font-size:14px;color:var(--muted);font-weight:400}
h2{display:inline;font-size:18px;margin:0}
code{font:13px/1.4 ui-monospace,SFMono-Regular,Consolas,monospace;background:var(--code);padding:1px 5px;border-radius:5px;overflow-wrap:anywhere}
.meta,.intro,.note{color:var(--muted)}.note{font-size:13px}
.warning{border-left:3px solid var(--warn);padding:6px 10px;background:var(--card)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:18px 0}
.tile{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;display:flex;flex-direction:column;color:var(--muted);font-size:13px}
.tile .num{font-size:28px;font-weight:700;color:var(--fg)}
.tile.hot .num{color:var(--hot)}.tile.warn .num{color:var(--warn)}.tile.ran .num{color:var(--blue)}
details{border-top:1px solid var(--line);padding:12px 0}
summary{cursor:pointer;list-style-position:outside}
.count{font-size:13px;color:var(--muted);font-weight:400;margin-left:6px}
.finding{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--bar);border-radius:8px;padding:12px 14px;margin:12px 0}
.finding.error{border-left-color:var(--hot)}.finding.warning{border-left-color:var(--warn)}
.finding.is-hot{box-shadow:0 0 0 1px var(--hot) inset}
.finding header{display:flex;flex-wrap:wrap;gap:6px 10px;align-items:baseline}
.finding p{margin:8px 0}
.sev{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;color:var(--muted)}
.error .sev{color:var(--hot)}.warning .sev{color:var(--warn)}
.loc{margin-left:auto}
.fix{font-size:12px;color:var(--ok);border:1px solid var(--ok);border-radius:999px;padding:0 8px}
.evidence{border-left:3px solid var(--hot);padding-left:10px}
pre.code{margin:8px 0 0;background:var(--code);border-radius:6px;padding:8px 0;overflow-x:auto;font:12.5px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}
pre.code .ln{display:block;padding:0 12px;white-space:pre}
pre.code .ln i{display:inline-block;width:3.5em;color:var(--muted);font-style:normal;user-select:none}
pre.code .hl{background:var(--hl)}
table{border-collapse:collapse;width:100%;margin:16px 0 4px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line)}
th{font-size:13px;color:var(--muted);font-weight:600}.n{text-align:right;font-variant-numeric:tabular-nums}
.v{white-space:nowrap}.better{color:var(--ok)}.worse{color:var(--hot)}.unclear{color:var(--muted)}
.bars{margin-top:8px}.bar-row{margin:14px 0}
.bar-label{font-size:13px;margin-bottom:4px;display:flex;flex-wrap:wrap;gap:4px 10px;min-width:0}
.bar-label code{min-width:0}
.table-wrap{overflow-x:auto}
@media (max-width:600px){th,td{padding:6px 4px;font-size:13px}.v{white-space:normal}.loc{margin-left:0}}
.bar{height:20px;border-radius:4px;margin:3px 0;min-width:2px;position:relative;background:var(--bar)}
.bar.after.better{background:var(--ok)}.bar.after.worse{background:var(--hot)}
.bar span{position:absolute;left:6px;top:0;font-size:12px;line-height:20px;white-space:nowrap;color:var(--fg)}
.bar span{text-shadow:0 0 3px var(--bg)}
footer{margin-top:32px;color:var(--muted);font-size:12px}
</style>
</head>
<body>
<main>
<h1>$title <small>fluttr_scope $packageVersion</small></h1>
$body
<footer>Generated by fluttr_scope $packageVersion. Self-contained: no scripts, nothing loaded from the network.</footer>
</main>
</body>
</html>
''';
