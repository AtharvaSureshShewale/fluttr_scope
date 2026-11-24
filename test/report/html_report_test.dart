import 'package:fluttr_scope/src/compare/compare.dart';
import 'package:fluttr_scope/src/model/category.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/model/severity.dart';
import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:fluttr_scope/src/report/html_report.dart';
import 'package:test/test.dart';

Finding _finding(String ruleId, int line, {String message = 'Use `const`.', Fix? fix}) => Finding(
      ruleId: ruleId,
      category: Category.performance,
      severity: Severity.warning,
      message: message,
      location: SourceLocation(file: 'lib/a.dart', line: line, column: 3, length: 4),
      fix: fix,
    );

const _source = [
  'import "x";',
  'class A {',
  "  final key = 'dxqHsX7I0URA5hfh';",
  '  Widget build() => Text("<b>hi</b>");',
  '}',
];

void main() {
  test('is one self-contained page: no scripts, nothing from the network', () {
    final html = htmlFindingsReport([_finding('x', 2)], sourceLines: (_) => _source);
    expect(html, startsWith('<!doctype html>'));
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('http://')));
    expect(html, isNot(contains('https://')));
    expect(html, contains('prefers-color-scheme:dark'));
  });

  test('escapes code and messages, and shows the lines around the finding', () {
    final html = htmlFindingsReport(
      [_finding('x', 4, message: 'Avoid `<b>` & co')],
      sourceLines: (_) => _source,
    );
    expect(html, contains('Text(&quot;&lt;b&gt;hi&lt;/b&gt;&quot;)'));
    expect(html, contains('Avoid <code>&lt;b&gt;</code> &amp; co'));
    expect(html, isNot(contains('<b>hi</b>')));
    expect(html, contains('<span class="ln hl"><i>4</i>'));
    expect(html, contains('<i>2</i>')); // two lines before
  });

  test('masks string values in snippets of secret findings, and only those', () {
    final secret = htmlFindingsReport([_finding('hardcoded_secret', 3)], sourceLines: (_) => _source);
    expect(secret, contains("'dxqH••••'"));
    expect(secret, isNot(contains('dxqHsX7I0URA5hfh')));

    final other = htmlFindingsReport([_finding('missing_const_constructor', 3)], sourceLines: (_) => _source);
    expect(other, contains('dxqHsX7I0URA5hfh'));
  });

  test('marks findings --fix can fix', () {
    const fix = Fix(kind: 'add_const', description: 'Add const', edits: [
      SourceEdit(offset: 0, length: 0, replacement: 'const '),
    ]);
    final html = htmlFindingsReport([_finding('x', 2, fix: fix)], sourceLines: (_) => null);
    expect(html, contains('auto-fixable'));
    expect(html, contains('<span class="num">1</span><span>fixable with'));
  });

  test('comparison: verdicts, and only file changes beyond noise', () {
    const comparison = Comparison(
      headline: [
        MetricComparison('Rebuilds (after warm-up)', '', [100, 101, 102], [60, 61, 62]),
        MetricComparison('Slowest frame', 'ms', [50, 70, 60], [55, 65, 60]),
      ],
      byFile: [
        MetricComparison('lib/a.dart', '', [100, 101, 102], [60, 61, 62]),
        MetricComparison('lib/tiny.dart', '', [100, 100, 100], [103, 103, 103]),
      ],
      warnings: ['Neither measurement used a flow'],
      beforeLabel: 'before.json',
      afterLabel: 'after.json',
    );
    final html = htmlComparisonReport(comparison);
    expect(html, contains('✅ better (-40%)'));
    expect(html, contains('no clear change'));
    expect(html, contains('⚠ Neither measurement used a flow'));
    expect(html, contains('lib/a.dart'));
    expect(html, isNot(contains('lib/tiny.dart'))); // +3%: below the 10% bar
  });
}
