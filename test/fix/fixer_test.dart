@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:fluttr_scope/src/fix/fixer.dart';
import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/static/all_rules.dart';
import 'package:fluttr_scope/src/static/engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../static/test_util.dart';

const _fixableRules = {'missing_const_constructor', 'media_query_of_single_property'};

void main() {
  test('applyEdits applies non-overlapping edits by original offsets', () {
    expect(
      applyEdits('abcdef', const [
        SourceEdit(offset: 0, length: 0, replacement: 'X'),
        SourceEdit(offset: 2, length: 2, replacement: 'YY'),
        SourceEdit(offset: 6, length: 0, replacement: 'Z'),
      ]),
      'XabYYefZ',
    );
  });

  test('describeFileFix shows each changed line before and after', () {
    const before = 'a\r\nfoo(bar)\r\nb\r\n';
    const edit = SourceEdit(offset: 3, length: 0, replacement: 'const ');
    final text = describeFileFix(FileFix(
      file: 'lib/x.dart',
      before: before,
      after: applyEdits(before, const [edit]),
      fixed: const [],
      edits: const [edit],
    ));
    expect(text, 'lib/x.dart:2\n- foo(bar)\n+ const foo(bar)\n');
  });

  group('on a copy of the sample app', () {
    late Directory temp;
    late String root;

    setUpAll(() async {
      temp = await Directory.systemTemp.createTemp('fluttr_scope_fix_');
      root = p.join(temp.path, 'sample_app');
      await _copy(Directory(sampleAppRoot), Directory(root));
    });

    tearDownAll(() async {
      await temp.delete(recursive: true);
    });

    test('fixes everything it can without adding a compile error, and is idempotent', () async {
      final engine = AnalysisEngine(allRules());
      final errorsBefore = await _errorCount(root);

      final plan = await planFixes(root, await engine.analyze(root));
      expect(plan.fixCount, greaterThan(0));
      // const there would trip Flutter's own asserts at compile time
      // (`Opacity(opacity: 1.5)`), which the compile check catches.
      expect(plan.skipped.map((s) => s.file), ['lib/numeric_constraint_examples.dart']);
      await writeFixes(root, plan);

      expect(await _errorCount(root), errorsBefore);
      final left = (await engine.analyze(root))
          .where((f) => _fixableRules.contains(f.ruleId))
          .map((f) => f.location.file)
          .toSet();
      expect(left, {'lib/numeric_constraint_examples.dart'});

      final again = await planFixes(root, await engine.analyze(root));
      expect(again.files, isEmpty);
    });
  });
}

Future<int> _errorCount(String root) async {
  final collection = AnalysisContextCollection(includedPaths: [root]);
  var count = 0;
  try {
    for (final context in collection.contexts) {
      for (final path in context.contextRoot.analyzedFiles()) {
        if (!path.endsWith('.dart')) continue;
        final result = await context.currentSession.getResolvedUnit(path);
        if (result is! ResolvedUnitResult) continue;
        count += result.diagnostics
            .where((d) => d.diagnosticCode.severity == DiagnosticSeverity.ERROR)
            .length;
      }
    }
  } finally {
    await collection.dispose();
  }
  return count;
}

Future<void> _copy(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(recursive: true)) {
    final relative = p.relative(entity.path, from: from.path);
    if (relative.startsWith('build') || relative.startsWith('android') || relative.startsWith('windows')) {
      continue;
    }
    final target = p.join(to.path, relative);
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}
