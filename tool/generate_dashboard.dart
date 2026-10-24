// Regenerates doc/images/dashboard.svg, the README's dashboard, from the
// package itself: its version, its rules, and a test run.
//
//   dart test --reporter json > test-results.json
//   dart run tool/generate_dashboard.dart test-results.json
//
// The audit numbers (findings on real apps, false errors fixed, rules seen
// live) come from manual runs on real apps, so they're constants here.

import 'dart:convert';
import 'dart:io';

import 'package:fluttr_scope/fluttr_scope.dart';

const outputPath = 'doc/images/dashboard.svg';

/// Rules seen firing on a real app, out of all Dart rules.
const rulesSeenLive = 34;

/// The bars, in the order they're drawn.
const barCategories = [
  (Category.performance, 'Performance'),
  (Category.correctness, 'Correctness'),
  (Category.security, 'Security'),
  (Category.accessibility, 'Accessibility'),
  (Category.style, 'Style'),
];

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/generate_dashboard.dart <dart test --reporter json output>');
    exit(64);
  }
  final (:passed, :total) = countTests(File(args.single).readAsLinesSync());
  if (total == 0) {
    stderr.writeln('No tests found in ${args.single}.');
    exit(1);
  }
  File(outputPath).writeAsStringSync(dashboard(passed: passed, total: total));
  print('Wrote $outputPath: $passed of $total tests passing.');
}

/// Counts the visible, non-skipped tests in `dart test --reporter json`
/// output, and how many of them passed.
({int passed, int total}) countTests(List<String> lines) {
  var passed = 0, total = 0;
  for (final line in lines) {
    if (!line.startsWith('{')) continue;
    final event = jsonDecode(line) as Map<String, Object?>;
    if (event['type'] != 'testDone' || event['hidden'] == true || event['skipped'] == true) {
      continue;
    }
    total++;
    if (event['result'] == 'success') passed++;
  }
  return (passed: passed, total: total);
}

String dashboard({required int passed, required int total}) {
  final rules = allRules();
  final dartRules = rules.length;
  final fileChecks = nonDartRuleIds.length;

  final counts = {for (final (category, _) in barCategories) category: 0};
  for (final rule in rules) {
    if (!counts.containsKey(rule.category)) {
      throw StateError('${rule.id} is in ${rule.category}, which has no bar.');
    }
    counts[rule.category] = counts[rule.category]! + 1;
  }
  // The file checks (manifests, dependency CVEs) are all security checks.
  counts[Category.security] = counts[Category.security]! + fileChecks;

  // Vertical bars on a baseline at y=330, 6px per rule.
  String categoryBars() {
    final out = StringBuffer();
    for (final (i, (category, label)) in barCategories.indexed) {
      final x = 318 + 72 * i;
      final height = 6 * counts[category]!;
      final y = 330 - height;
      out
        ..writeln('      <rect x="$x" y="$y" width="40" height="$height" rx="${height < 20 ? 3 : 4}" fill="#3fb950"/>')
        ..writeln('      <text x="${x + 20}" y="${y - 6}" fill="#e6edf3" font-weight="600">${counts[category]}</text>')
        ..writeln('      <text x="${x + 20}" y="348" fill="#8b949e">$label</text>');
    }
    return '$out';
  }

  // A ring's filled arc, out of a circumference of 188.5 (r=30).
  String dash(double fraction) => '${_number(fraction * 188.5)} 188.5';
  String percent(double fraction) => '${(fraction * 100).round()}';

  return '''
<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="640" viewBox="0 0 1100 640" role="img" aria-label="fluttr_scope project dashboard: $dartRules Dart rules plus $fileChecks file checks, 5 commands, $passed tests passing, CI green on Flutter 3.35.2 and stable; rules by category; findings on Wonderous and Spotube; verification scores; roadmap progress">
  <defs>
    <linearGradient id="logo" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1f6feb"/>
      <stop offset="1" stop-color="#02569b"/>
    </linearGradient>
  </defs>
  <rect x="0.5" y="0.5" width="1099" height="639" rx="12" fill="#0d1117" stroke="#30363d"/>

  <g font-family="-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif">

    <!-- ===== Left: identity ===== -->
    <circle cx="140" cy="128" r="92" fill="url(#logo)"/>
    <circle cx="140" cy="128" r="92" fill="none" stroke="#30363d" stroke-width="2"/>
    <circle cx="140" cy="128" r="54" fill="none" stroke="#ffffff" stroke-opacity="0.9" stroke-width="7"/>
    <circle cx="140" cy="128" r="30" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="4"/>
    <line x1="140" y1="56" x2="140" y2="96" stroke="#ffffff" stroke-opacity="0.9" stroke-width="5" stroke-linecap="round"/>
    <line x1="140" y1="160" x2="140" y2="200" stroke="#ffffff" stroke-opacity="0.9" stroke-width="5" stroke-linecap="round"/>
    <line x1="68" y1="128" x2="108" y2="128" stroke="#ffffff" stroke-opacity="0.9" stroke-width="5" stroke-linecap="round"/>
    <line x1="172" y1="128" x2="212" y2="128" stroke="#ffffff" stroke-opacity="0.9" stroke-width="5" stroke-linecap="round"/>
    <circle cx="140" cy="128" r="8" fill="#ffffff"/>

    <text x="40" y="262" font-size="26" font-weight="700" fill="#e6edf3">fluttr_scope</text>
    <text x="40" y="288" font-size="15" fill="#8b949e">static + runtime analysis for Flutter</text>
    <text x="40" y="324" font-size="13.5" fill="#c9d1d9">Every other Flutter analyzer</text>
    <text x="40" y="343" font-size="13.5" fill="#c9d1d9">reads your code.</text>
    <text x="40" y="362" font-size="13.5" fill="#58a6ff" font-weight="600">This one runs it.</text>

    <g font-size="13" fill="#8b949e">
      <text x="40" y="404">◆  version $packageVersion</text>
      <text x="40" y="428">◆  Flutter 3.35+ · Dart 3.9+</text>
      <text x="40" y="452">◆  Apache-2.0 license</text>
      <text x="40" y="476">◆  github.com/AtharvaSureshShewale</text>
      <text x="58" y="494">/fluttr_scope</text>
    </g>

    <!-- ===== Middle: stats ===== -->
    <text x="300" y="44" font-size="17" font-weight="600" fill="#58a6ff">At a glance</text>
    <g font-size="13.5" fill="#c9d1d9">
      <text x="300" y="74">▸  <tspan font-weight="700" fill="#e6edf3">$dartRules</tspan> Dart rules + <tspan font-weight="700" fill="#e6edf3">$fileChecks</tspan> file checks</text>
      <text x="300" y="98">▸  <tspan font-weight="700" fill="#e6edf3">5</tspan> commands: analyze, security,</text>
      <text x="322" y="116">measure, prioritize, correlate</text>
      <text x="300" y="140">▸  <tspan font-weight="700" fill="#e6edf3">$passed</tspan> tests passing</text>
      <text x="510" y="74">▸  <tspan font-weight="700" fill="#e6edf3">8</tspan> real apps audited</text>
      <text x="510" y="98">▸  CI: Flutter 3.35.2 + stable</text>
      <text x="510" y="122">▸  live CVE lookup (OSV.dev)</text>
      <text x="510" y="146">▸  SARIF for GitHub scanning</text>
    </g>

    <!-- Rules by category: vertical bars, 6px per rule -->
    <text x="300" y="190" font-size="15" font-weight="600" fill="#58a6ff">Rules by category</text>
    <line x1="300" y1="330" x2="680" y2="330" stroke="#30363d"/>
    <g font-size="12" text-anchor="middle">
${categoryBars()}    </g>

    <!-- Findings on real apps: stacked bars, 1.4px per finding -->
    <text x="300" y="392" font-size="15" font-weight="600" fill="#58a6ff">Findings on real open-source apps</text>
    <g font-size="12.5">
      <text x="300" y="424" fill="#c9d1d9">Wonderous</text>
      <rect x="378" y="413" width="2.8" height="14" fill="#f85149"/>
      <rect x="380.8" y="413" width="121.8" height="14" fill="#d29922"/>
      <rect x="502.6" y="413" width="124.6" height="14" fill="#8b949e"/>
      <text x="636" y="424" fill="#e6edf3" font-weight="600">178</text>
      <text x="300" y="452" fill="#c9d1d9">Spotube</text>
      <rect x="378" y="441" width="134.4" height="14" fill="#d29922"/>
      <rect x="512.4" y="441" width="75.6" height="14" fill="#8b949e"/>
      <text x="597" y="452" fill="#e6edf3" font-weight="600">150</text>
      <circle cx="384" cy="478" r="5" fill="#f85149"/><text x="394" y="482" fill="#8b949e">error</text>
      <circle cx="446" cy="478" r="5" fill="#d29922"/><text x="456" y="482" fill="#8b949e">warning</text>
      <circle cx="526" cy="478" r="5" fill="#8b949e"/><text x="536" y="482" fill="#8b949e">info</text>
    </g>

    <!-- Built with -->
    <text x="300" y="526" font-size="15" font-weight="600" fill="#58a6ff">Built with</text>
    <g font-size="12" fill="#c9d1d9">
      <rect x="300" y="540" width="56" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="328" y="556" text-anchor="middle">Dart</text>
      <rect x="364" y="540" width="76" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="402" y="556" text-anchor="middle">analyzer</text>
      <rect x="448" y="540" width="88" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="492" y="556" text-anchor="middle">vm_service</text>
      <rect x="544" y="540" width="118" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="603" y="556" text-anchor="middle">integration_test</text>
      <rect x="300" y="572" width="78" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="339" y="588" text-anchor="middle">OSV.dev</text>
      <rect x="386" y="572" width="92" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="432" y="588" text-anchor="middle">SARIF 2.1.0</text>
      <rect x="486" y="572" width="122" height="24" rx="12" fill="#161b22" stroke="#30363d"/><text x="547" y="588" text-anchor="middle">GitHub Actions</text>
    </g>

    <!-- ===== Right: verification rings (r=30, circumference 188.5) ===== -->
    <text x="720" y="44" font-size="17" font-weight="600" fill="#58a6ff">Verified on real code</text>
    <g font-size="12" text-anchor="middle">
      <g transform="translate(762,108)">
        <circle r="30" fill="none" stroke="#21262d" stroke-width="6"/>
        <circle r="30" fill="none" stroke="#3fb950" stroke-width="6" stroke-dasharray="${dash(passed / total)}" transform="rotate(-90)"/>
        <text y="6" font-size="18" font-weight="700" fill="#3fb950">${percent(passed / total)}</text>
        <text y="52" fill="#c9d1d9">Tests passing</text>
        <text y="68" fill="#8b949e">$passed of $total</text>
      </g>
      <g transform="translate(856,108)">
        <circle r="30" fill="none" stroke="#21262d" stroke-width="6"/>
        <circle r="30" fill="none" stroke="#3fb950" stroke-width="6" stroke-dasharray="188.5 188.5" transform="rotate(-90)"/>
        <text y="6" font-size="18" font-weight="700" fill="#3fb950">100</text>
        <text y="52" fill="#c9d1d9">CI jobs green</text>
        <text y="68" fill="#8b949e">3.35.2 + stable</text>
      </g>
      <g transform="translate(950,108)">
        <circle r="30" fill="none" stroke="#21262d" stroke-width="6"/>
        <circle r="30" fill="none" stroke="#3fb950" stroke-width="6" stroke-dasharray="181 188.5" transform="rotate(-90)"/>
        <text y="6" font-size="18" font-weight="700" fill="#3fb950">96</text>
        <text y="52" fill="#c9d1d9">False errors fixed</text>
        <text y="68" fill="#8b949e">133 of 139</text>
      </g>
      <g transform="translate(1044,108)">
        <circle r="30" fill="none" stroke="#21262d" stroke-width="6"/>
        <circle r="30" fill="none" stroke="#d29922" stroke-width="6" stroke-dasharray="${dash(rulesSeenLive / dartRules)}" transform="rotate(-90)"/>
        <text y="6" font-size="18" font-weight="700" fill="#d29922">${percent(rulesSeenLive / dartRules)}</text>
        <text y="52" fill="#c9d1d9">Rules seen live</text>
        <text y="68" fill="#8b949e">$rulesSeenLive of $dartRules</text>
      </g>
    </g>

    <!-- What a run tells you -->
    <text x="720" y="226" font-size="15" font-weight="600" fill="#58a6ff">What a run tells you</text>
    <g font-size="13" fill="#c9d1d9">
      <circle cx="728" cy="252" r="6" fill="#f85149"/><text x="744" y="257">Fix first: rebuilt during slow frames</text>
      <circle cx="728" cy="278" r="6" fill="#58a6ff"/><text x="744" y="283">Ran during the session</text>
      <circle cx="728" cy="304" r="6" fill="#8b949e"/><text x="744" y="309">Never ran in this session</text>
      <circle cx="728" cy="330" r="6" fill="none" stroke="#8b949e" stroke-width="1.5"/><text x="744" y="335">No runtime signal (config, constants)</text>
    </g>
    <text x="720" y="366" font-size="12.5" fill="#8b949e">Repeatable flows: same actions every run; rebuild</text>
    <text x="720" y="384" font-size="12.5" fill="#8b949e">variation 9.5% across 3 runs (HIGH confidence).</text>

    <!-- Roadmap -->
    <text x="720" y="428" font-size="15" font-weight="600" fill="#58a6ff">Roadmap</text>
    <g font-size="12.5" fill="#c9d1d9">
      <text x="720" y="454"><tspan fill="#3fb950">✓</tspan>  rules · security · CVEs · measure · prioritize</text>
      <text x="720" y="474"><tspan fill="#3fb950">✓</tspan>  repeatable flows · Riverpod · analyzer 10</text>
      <text x="720" y="494"><tspan fill="#a371f7">●</tspan>  publishing 0.2.0 on pub.dev</text>
      <text x="720" y="514"><tspan fill="#8b949e">○</tspan>  PR regression check · HTML report · IDE plugin</text>
    </g>
    <rect x="720" y="532" width="356" height="10" rx="5" fill="#21262d"/>
    <rect x="720" y="532" width="237" height="10" rx="5" fill="#3fb950"/>
    <rect x="953" y="532" width="30" height="10" fill="#a371f7"/>
    <text x="720" y="562" font-size="12" fill="#8b949e">8 done · 1 doing · 3 to do</text>

    <!-- Bottom: language bar -->
    <line x1="20" y1="600" x2="1080" y2="600" stroke="#30363d"/>
    <rect x="40" y="614" width="960" height="8" rx="4" fill="#00B4AB"/>
    <circle cx="1018" cy="618" r="5" fill="#00B4AB"/>
    <text x="1028" y="622" font-size="12" fill="#8b949e">Dart</text>
  </g>
</svg>
''';
}

/// [value] to one decimal place, without a trailing `.0`.
String _number(double value) {
  final s = value.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
