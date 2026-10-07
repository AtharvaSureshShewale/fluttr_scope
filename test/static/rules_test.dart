@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:fluttr_scope/src/model/finding.dart';
import 'package:fluttr_scope/src/static/all_rules.dart';
import 'package:fluttr_scope/src/static/engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_util.dart';

// Spinning up an AnalysisContextCollection means resolving the whole
// Flutter SDK, which is slow (tens of seconds) the first time a process
// does it. Run the engine once here, with every rule, and have each test
// below assert against the shared result — running it per-test (per-rule)
// made the cold-start cost dominate the entire suite.
//
// Each assertion is also scoped to the specific fixture file it expects
// findings in, not just the ruleId — with several fixture files now
// feeding one shared engine run, a bare ruleId count would silently break
// whenever an unrelated fixture happens to also trip the same rule.
void main() {
  late List<Finding> findings;

  setUpAll(() async {
    findings = await AnalysisEngine(allRules()).analyze(sampleAppRoot);
  });

  // `endsWith` alone would wrongly match more_risky_widgets.dart against
  // 'risky_widgets.dart' — one filename is a literal suffix of the other.
  Iterable<Finding> inFile(String ruleId, String file) => findings.where(
        (f) => f.ruleId == ruleId && f.location.file == 'lib/$file',
      );

  test('avoid_print flags a bare print() call at its exact location', () {
    final matches = inFile('avoid_print', 'main.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate("print('building HomePage')");
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'missing_const_constructor flags a non-const widget creation '
      'that could be const', () {
    final matches = inFile('missing_const_constructor', 'main.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate("Text('Hello')");
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'missing_const_constructor does not flag a creation already in a '
      'const context', () {
    expect(
      inFile('missing_const_constructor', 'main.dart')
          .where((f) => f.location.line == 12),
      isEmpty,
      reason: 'HomePage() inside `const MaterialApp(...)` is implicitly '
          'const and must not be double-flagged',
    );
  });

  test('dispose_missing flags a controller field never disposed', () {
    final matches = inFile('dispose_missing', 'main.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate('_controller;');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'missing_const_constructor does not flag a string interpolation as '
      'a constant literal', () {
    // `Text('$_count')` and `Text(_data)` in risky_widgets.dart reference a
    // non-const field, so despite `Text(...)` being const-capable and the
    // interpolation itself satisfying `is Literal`, neither is actually a
    // compile-time constant — regression test for that gap.
    expect(inFile('missing_const_constructor', 'risky_widgets.dart'), isEmpty);
  });

  test(
      'setstate_in_build flags setState() called directly in build(), '
      'but not the one inside a closure', () {
    final matches = inFile('setstate_in_build', 'risky_widgets.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('setState(() => _count++);', relativeFile: 'risky_widgets.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'missing_mounted_check flags setState() after an unguarded await, '
      'but not the one guarded by `if (!mounted) return;`', () {
    final matches = inFile('missing_mounted_check', 'risky_widgets.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'setState(() => _data = result);',
      relativeFile: 'risky_widgets.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('shrinkwrap_listview flags shrinkWrap: true on a ListView', () {
    final matches = inFile('shrinkwrap_listview', 'more_risky_widgets.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('shrinkWrap: true', relativeFile: 'more_risky_widgets.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'unbounded_scrollable_in_flex flags a ListView as a direct child '
      'of Column', () {
    final matches =
        inFile('unbounded_scrollable_in_flex', 'more_risky_widgets.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'ListView(children: const []),',
      relativeFile: 'more_risky_widgets.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('nested_scaffold flags a Scaffold nested inside another Scaffold', () {
    final matches = inFile('nested_scaffold', 'more_risky_widgets.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'body: Scaffold(',
      relativeFile: 'more_risky_widgets.dart',
      columnOf: 'Scaffold(',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('hardcoded_secret flags a Google API key literal', () {
    final matches = inFile('hardcoded_secret', 'more_risky_widgets.dart');
    expect(matches, hasLength(1));
    expect(matches.single.message, contains('Google API key'));

    final (line, column) = locate(
      "'AIzaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'",
      relativeFile: 'more_risky_widgets.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('expanded_outside_flex flags Expanded outside a Column/Row/Flex', () {
    final matches = inFile('expanded_outside_flex', 'hierarchy_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "Expanded(child: Text('bad')),",
      relativeFile: 'hierarchy_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('expanded_outside_flex does not flag Expanded correctly nested in a Row', () {
    final (correctLine, _) = locate(
      "Expanded(child: Text('ok')),",
      relativeFile: 'hierarchy_examples.dart',
    );
    expect(
      inFile('expanded_outside_flex', 'hierarchy_examples.dart')
          .where((f) => f.location.line == correctLine),
      isEmpty,
    );
  });

  // The line of every string literal in [file] starting with [prefix] --
  // fixtures mark each case with an 'ok ...' or 'bad ...' label on the
  // line the finding would point to. Comment lines are skipped.
  Set<int> labelledLines(String file, String prefix) {
    final lines = File(p.join(sampleAppRoot, 'lib', file)).readAsLinesSync();
    return {
      for (var i = 0; i < lines.length; i++)
        if (!lines[i].trimLeft().startsWith('//') && lines[i].contains("'$prefix")) i + 1,
    };
  }

  Set<int> flaggedLines(String file, List<String> ruleIds) => {
        for (final id in ruleIds)
          for (final f in inFile(id, file)) f.location.line,
      };

  void labelledFixtureTests(String file, List<String> ruleIds) {
    test('flags only the genuine mistakes', () {
      expect(flaggedLines(file, ruleIds), labelledLines(file, 'bad '));
    });

    test('flags none of the valid real-world shapes', () {
      expect(flaggedLines(file, ruleIds).intersection(labelledLines(file, 'ok ')), isEmpty);
    });
  }

  group('hierarchy rules on real-world shapes (hierarchy_real_world_examples.dart)', () {
    labelledFixtureTests(
      'hierarchy_real_world_examples.dart',
      ['expanded_outside_flex', 'positioned_outside_stack'],
    );
  });

  group('unbounded_scrollable_in_flex on real-world shapes (scrollable_real_world_examples.dart)',
      () {
    labelledFixtureTests('scrollable_real_world_examples.dart', ['unbounded_scrollable_in_flex']);
  });

  group('missing_mounted_check on real-world shapes (mounted_check_examples.dart)', () {
    labelledFixtureTests('mounted_check_examples.dart', ['missing_mounted_check']);
  });

  group('avoid_logging_sensitive_data on real-world shapes (logging_real_world_examples.dart)',
      () {
    labelledFixtureTests('logging_real_world_examples.dart', ['avoid_logging_sensitive_data']);
  });

  group('insecure_http_url on real-world shapes (http_url_real_world_examples.dart)', () {
    labelledFixtureTests('http_url_real_world_examples.dart', ['insecure_http_url']);
  });

  group('missing_list_key on real-world shapes (list_key_real_world_examples.dart)', () {
    labelledFixtureTests('list_key_real_world_examples.dart', ['missing_list_key']);
  });

  group('unnecessary_column_or_row on real-world shapes (column_row_real_world_examples.dart)',
      () {
    labelledFixtureTests('column_row_real_world_examples.dart', ['unnecessary_column_or_row']);
  });

  group('widget_returning_method on real-world shapes (widget_method_real_world_examples.dart)',
      () {
    labelledFixtureTests('widget_method_real_world_examples.dart', ['widget_returning_method']);
  });

  group('hardcoded_secret on real-world shapes (secret_real_world_examples.dart)', () {
    labelledFixtureTests('secret_real_world_examples.dart', ['hardcoded_secret']);
  });

  group('sql_injection_risk on real-world shapes (sql_real_world_examples.dart)', () {
    labelledFixtureTests('sql_real_world_examples.dart', ['sql_injection_risk']);
  });

  group('scaffold_missing_body on real-world shapes (scaffold_real_world_examples.dart)', () {
    labelledFixtureTests('scaffold_real_world_examples.dart', ['scaffold_missing_body']);
  });

  group('network literal rules on real-world shapes (network_literal_real_world_examples.dart)',
      () {
    labelledFixtureTests(
      'network_literal_real_world_examples.dart',
      ['hardcoded_ip_address', 'insecure_http_url'],
    );

    test('test files are skipped: their IPs and URLs are test data', () {
      expect(
        findings.where((f) =>
            f.location.file == 'test/network_literals_test.dart' &&
            (f.ruleId == 'hardcoded_ip_address' || f.ruleId == 'insecure_http_url')),
        isEmpty,
      );
    });
  });

  test('positioned_outside_stack flags Positioned outside a Stack', () {
    final matches = inFile('positioned_outside_stack', 'hierarchy_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "Positioned(top: 0, child: Text('bad')),",
      relativeFile: 'hierarchy_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('key_created_in_build flags GlobalKey() created inside build()', () {
    final matches = inFile('key_created_in_build', 'build_misuse_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('GlobalKey()', relativeFile: 'build_misuse_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'inherited_widget_of_in_initstate flags Theme.of(context) called '
      'directly in initState()', () {
    final matches =
        inFile('inherited_widget_of_in_initstate', 'build_misuse_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'Theme.of(context)',
      relativeFile: 'build_misuse_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('build_context_stored_in_field flags a BuildContext assigned to a field', () {
    final matches =
        inFile('build_context_stored_in_field', 'build_misuse_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      '_savedContext = context;',
      relativeFile: 'build_misuse_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('insecure_http_url flags a non-localhost http:// URL literal', () {
    final matches = inFile('insecure_http_url', 'security_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "'http://api.example.com/data'",
      relativeFile: 'security_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('sensitive_query_param flags a token= query parameter', () {
    final matches = inFile('sensitive_query_param', 'security_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "'https://api.example.com/login?token=abc123'",
      relativeFile: 'security_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('hardcoded_ip_address flags a hardcoded IP literal', () {
    final matches = inFile('hardcoded_ip_address', 'security_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate("'203.0.113.42'", relativeFile: 'security_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'unrestricted_webview_javascript flags javaScriptMode: '
      'JavaScriptMode.unrestricted', () {
    final matches =
        inFile('unrestricted_webview_javascript', 'security_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'javaScriptMode: JavaScriptMode.unrestricted,',
      relativeFile: 'security_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'insecure_random_for_secret flags Random() feeding a '
      'sensitively-named variable', () {
    final matches = inFile('insecure_random_for_secret', 'security_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('Random();', relativeFile: 'security_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'textfield_password_not_obscured flags a password-labeled field '
      'without obscureText: true', () {
    final matches =
        inFile('textfield_password_not_obscured', 'security_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate('TextField(', relativeFile: 'security_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'textfield_password_not_obscured does not flag obscureText driven by '
      'a variable (a show/hide-password toggle)', () {
    final toggleLine =
        locate('return TextField(', relativeFile: 'security_examples.dart').$1;
    final matches = inFile('textfield_password_not_obscured', 'security_examples.dart');
    expect(matches.where((f) => f.location.line == toggleLine), isEmpty);
  });

  test(
      'sensitive_query_param does not flag a regex pattern describing a '
      'query param (e.g. a redaction helper)', () {
    final patternLine =
        locate("RegExp(r'[?&]token=", relativeFile: 'security_examples.dart').$1;
    final matches = inFile('sensitive_query_param', 'security_examples.dart');
    expect(matches.where((f) => f.location.line == patternLine), isEmpty);
  });

  test('missing_tooltip_for_iconbutton flags an IconButton without a tooltip', () {
    final matches =
        inFile('missing_tooltip_for_iconbutton', 'accessibility_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'IconButton(onPressed: () {}, icon: const Icon(Icons.close)),',
      relativeFile: 'accessibility_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('image_missing_semantic_label flags Image.network without semanticLabel', () {
    final matches =
        inFile('image_missing_semantic_label', 'accessibility_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "Image.network('https://example.com/photo.png'),",
      relativeFile: 'accessibility_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('image_network_without_error_builder flags Image.network without errorBuilder', () {
    final matches =
        inFile('image_network_without_error_builder', 'accessibility_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "Image.network('https://example.com/photo.png'),",
      relativeFile: 'accessibility_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      "future_builder_missing_error_check flags a FutureBuilder whose "
      "builder never checks snapshot.hasError", () {
    final matches =
        inFile('future_builder_missing_error_check', 'async_widget_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('FutureBuilder<String>(', relativeFile: 'async_widget_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      "stream_builder_missing_error_check flags a StreamBuilder whose "
      "builder never checks snapshot.hasError", () {
    final matches =
        inFile('stream_builder_missing_error_check', 'async_widget_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('StreamBuilder<int>(', relativeFile: 'async_widget_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test(
      'future_created_in_build flags both FutureBuilder.future and '
      'StreamBuilder.stream created inline', () {
    final matches = inFile('future_created_in_build', 'async_widget_examples.dart');
    expect(matches, hasLength(2));

    final (futureLine, futureColumn) = locate(
      'future: _fetchData(),',
      relativeFile: 'async_widget_examples.dart',
      columnOf: '_fetchData()',
    );
    final (streamLine, streamColumn) = locate(
      'stream: _tickStream(),',
      relativeFile: 'async_widget_examples.dart',
      columnOf: '_tickStream()',
    );

    expect(
      matches.map((f) => (f.location.line, f.location.column)),
      containsAll([(futureLine, futureColumn), (streamLine, streamColumn)]),
    );
  });

  test('missing_list_key flags a stateful item generated via .map().toList() without a key', () {
    final matches = inFile('missing_list_key', 'missing_list_key_example.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'TextField(',
      relativeFile: 'missing_list_key_example.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('empty_container_instead_of_sizedbox flags an empty Container()', () {
    final matches =
        inFile('empty_container_instead_of_sizedbox', 'simplification_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('Container(),', relativeFile: 'simplification_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('unnecessary_column_or_row flags a Row wrapping a single child', () {
    final matches =
        inFile('unnecessary_column_or_row', 'simplification_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'Row(children: [_buildHelper()]),',
      relativeFile: 'simplification_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('empty_flex_children flags a Column with an empty children list', () {
    final matches = inFile('empty_flex_children', 'simplification_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'Column(children: const []),',
      relativeFile: 'simplification_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('widget_returning_method flags a Widget-returning helper method', () {
    final matches = inFile('widget_returning_method', 'simplification_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      "Widget _buildHelper() => const Text('helper');",
      relativeFile: 'simplification_examples.dart',
      columnOf: '_buildHelper',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);

    // The span runs to the end of the method, so runtime coverage (which
    // never reports a declaration line) can check the body's lines.
    expect(
      matches.single.location.length,
      "_buildHelper() => const Text('helper');".length,
    );
  });

  test('opacity_out_of_range flags Opacity.opacity outside [0.0, 1.0]', () {
    final matches =
        inFile('opacity_out_of_range', 'numeric_constraint_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('1.5', relativeFile: 'numeric_constraint_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('invalid_aspect_ratio flags AspectRatio.aspectRatio <= 0', () {
    final matches =
        inFile('invalid_aspect_ratio', 'numeric_constraint_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'aspectRatio: -1',
      relativeFile: 'numeric_constraint_examples.dart',
      columnOf: '-1',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('flex_value_non_positive flags Expanded(flex: 0)', () {
    final matches =
        inFile('flex_value_non_positive', 'numeric_constraint_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'flex: 0',
      relativeFile: 'numeric_constraint_examples.dart',
      columnOf: '0',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('slider_invalid_range flags Slider.min >= Slider.max', () {
    final matches =
        inFile('slider_invalid_range', 'numeric_constraint_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'Slider(value: 0, min: 10, max: 5, onChanged: null),',
      relativeFile: 'numeric_constraint_examples.dart',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('bottom_navigation_bar_too_few_items flags fewer than 2 items', () {
    final matches = inFile(
        'bottom_navigation_bar_too_few_items', 'numeric_constraint_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'BottomNavigationBar(items: const [',
      relativeFile: 'numeric_constraint_examples.dart',
      columnOf: 'BottomNavigationBar(',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('container_color_and_decoration_conflict flags both color and decoration set', () {
    final matches =
        inFile('container_color_and_decoration_conflict', 'misc_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('Container(', relativeFile: 'misc_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('scaffold_missing_body flags a Scaffold with no body', () {
    final matches = inFile('scaffold_missing_body', 'misc_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) = locate(
      'return Scaffold(',
      relativeFile: 'misc_examples.dart',
      columnOf: 'Scaffold(',
    );
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  test('deeply_nested_widget_tree flags a build() nested more than 8 levels deep', () {
    final matches = inFile('deeply_nested_widget_tree', 'misc_examples.dart');
    expect(matches, hasLength(1));
    expect(matches.single.message, contains('9 levels deep'));

    // "Widget build(BuildContext context) {" appears identically in all
    // three classes in this fixture; DeeplyNestedExample's build() is the
    // one whose tree actually exceeds the threshold, so locate it via the
    // class name rather than the ambiguous signature text.
    final classLine = locate(
      'class DeeplyNestedExample',
      relativeFile: 'misc_examples.dart',
    ).$1;
    expect(matches.single.location.line, greaterThan(classLine));

    // Points at the method name, not its `@override` annotation.
    final flaggedLine = File(p.join(sampleAppRoot, 'lib', 'misc_examples.dart'))
        .readAsLinesSync()[matches.single.location.line - 1];
    expect(flaggedLine.substring(matches.single.location.column - 1), startsWith('build('));
  });

  test('todo_comment flags an unresolved TODO comment', () {
    final matches = inFile('todo_comment', 'misc_examples.dart');
    expect(matches, hasLength(1));

    final (line, column) =
        locate('TODO', relativeFile: 'misc_examples.dart');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  group('generated-code exclusion', () {
    test('avoid_print does not fire inside a .g.dart file', () {
      expect(inFile('avoid_print', 'generated_example.g.dart'), isEmpty);
    });

    test('avoid_print does not fire inside a .freezed.dart file', () {
      expect(inFile('avoid_print', 'generated_example.freezed.dart'), isEmpty);
    });
  });

  test(
      'avoid_logging_sensitive_data flags debugPrint of a token-named value, '
      'not an innocuous one (debug_print_examples.dart)', () {
    const file = 'debug_print_examples.dart';
    final matches = inFile('avoid_logging_sensitive_data', file);
    expect(matches, hasLength(1));

    final (line, column) =
        locate("debugPrint('token:", relativeFile: file, columnOf: 'debugPrint(');
    expect(matches.single.location.line, line);
    expect(matches.single.location.column, column);
  });

  group('ignore comments (suppression_examples.dart)', () {
    const file = 'suppression_examples.dart';

    test('only the print without a fluttr_scope/ ignore is reported', () {
      final matches = inFile('avoid_print', file);
      expect(matches, hasLength(1));
      expect(
        matches.single.location.line,
        locate("print('NOT suppressed", relativeFile: file).$1,
      );
    });

    test('ignore_for_file suppresses todo_comment for the whole file', () {
      expect(inFile('todo_comment', file), isEmpty);
    });
  });

  group('false-positive regressions (negative_examples.dart)', () {
    const file = 'negative_examples.dart';

    test('unbounded_scrollable_in_flex does not flag a ListView wrapped in Expanded', () {
      expect(inFile('unbounded_scrollable_in_flex', file), isEmpty);
    });

    test(
        'container_color_and_decoration_conflict does not flag a Container '
        'with only `color` set', () {
      expect(inFile('container_color_and_decoration_conflict', file), isEmpty);
    });

    test('opacity_out_of_range does not flag a value inside [0.0, 1.0]', () {
      expect(inFile('opacity_out_of_range', file), isEmpty);
    });

    test('invalid_aspect_ratio does not flag a positive aspect ratio', () {
      expect(inFile('invalid_aspect_ratio', file), isEmpty);
    });

    test('flex_value_non_positive does not flag a positive flex value', () {
      expect(inFile('flex_value_non_positive', file), isEmpty);
    });

    test('insecure_http_url does not flag https:// or a localhost URL', () {
      expect(inFile('insecure_http_url', file), isEmpty);
    });

    test('dispose_missing flags a StreamSubscription never cancelled', () {
      final matches = inFile('dispose_missing', file)
          .where((f) => f.message.contains('cancelled'));
      expect(matches, hasLength(1));

      // The finding's location is the VariableDeclaration node, which
      // starts at the field NAME, not the type — same convention as the
      // existing AnimationController test elsewhere in this file. Both the
      // leaking and the well-behaved example declare an identically-worded
      // field; `locate` finds the first (leaking) one, which is exactly
      // the one expected to be flagged.
      final (line, column) = locate('_subscription;', relativeFile: file);
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test(
        'dispose_missing does not flag a StreamSubscription that is '
        'cancelled in dispose()', () {
      final cancelledFieldLine = locate('_subscription;', relativeFile: file).$1;
      expect(
        inFile('dispose_missing', file).where((f) => f.location.line != cancelledFieldLine),
        isEmpty,
      );
    });

    test(
        'key_created_in_build does not flag a GlobalKey created in '
        'initState() and merely referenced in build()', () {
      expect(inFile('key_created_in_build', file), isEmpty);
    });

    test('missing_list_key does not flag a generated widget that already has a key', () {
      expect(inFile('missing_list_key', file), isEmpty);
    });
  });

  group('advanced security rules (advanced_security_examples.dart)', () {
    const file = 'advanced_security_examples.dart';

    test('avoid_logging_sensitive_data flags a print() referencing a token-named value', () {
      final matches = inFile('avoid_logging_sensitive_data', file);
      expect(matches, hasLength(1));

      final (line, column) =
          locate("print('token: \$authToken');", relativeFile: file, columnOf: 'print(');
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test('sql_injection_risk flags a rawQuery built via string interpolation', () {
      final matches = inFile('sql_injection_risk', file);
      expect(matches, hasLength(1));

      final (line, column) = locate(
        "db.rawQuery('SELECT * FROM users WHERE id = \$userId');",
        relativeFile: file,
        columnOf: "'SELECT",
      );
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test('insecure_storage_of_sensitive_data flags a token-named SharedPreferences key', () {
      final matches = inFile('insecure_storage_of_sensitive_data', file);
      expect(matches, hasLength(1));

      final (line, column) = locate(
        "prefs.setString('auth_token', authToken);",
        relativeFile: file,
        columnOf: 'prefs.setString(',
      );
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test('weak_hash_algorithm flags md5.convert(...)', () {
      final matches = inFile('weak_hash_algorithm', file);
      expect(matches, hasLength(1));
      expect(matches.single.message, contains('md5'));

      final (line, column) = locate(
        'md5.convert(utf8.encode(password));',
        relativeFile: file,
        columnOf: 'md5.convert(',
      );
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test('sql_table_missing_constraints flags a CREATE TABLE with no constraints', () {
      final matches = inFile('sql_table_missing_constraints', file);
      expect(matches, hasLength(1));

      final (line, column) = locate(
        "'CREATE TABLE notes (id INTEGER, body TEXT)'",
        relativeFile: file,
      );
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test(
        'sql_table_missing_constraints does not flag a CREATE TABLE that has '
        'PRIMARY KEY/NOT NULL/UNIQUE', () {
      final constrainedLine = locate(
        'CREATE TABLE users',
        relativeFile: file,
      ).$1;
      expect(
        inFile('sql_table_missing_constraints', file)
            .where((f) => f.location.line == constrainedLine),
        isEmpty,
      );
    });

    test(
        'insecure_certificate_validation flags badCertificateCallback that '
        'always returns true', () {
      final matches = inFile('insecure_certificate_validation', file);
      expect(matches, hasLength(1));

      final (line, column) = locate(
        'client.badCertificateCallback = (cert, host, port) => true;',
        relativeFile: file,
        columnOf: 'client.badCertificateCallback',
      );
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test(
        'insecure_certificate_validation does not flag a callback that '
        'actually checks something', () {
      final realCheckLine = locate(
        'host == expectedHost',
        relativeFile: file,
      ).$1;
      expect(
        inFile('insecure_certificate_validation', file)
            .where((f) => f.location.line == realCheckLine),
        isEmpty,
      );
    });
  });

  group('setstate_in_list_builder (list_builder_examples.dart)', () {
    const file = 'list_builder_examples.dart';

    test(
        'flags setState nested inside an itemBuilder tap handler '
        '(rebuilds every item, not just the tapped one)', () {
      final matches = inFile('setstate_in_list_builder', file);
      expect(matches, hasLength(1));

      final (line, column) =
          locate('setState(() {', relativeFile: file, columnOf: 'setState');
      expect(matches.single.location.line, line);
      expect(matches.single.location.column, column);
    });

    test(
        'does not flag a setState call outside any builder callback', () {
      final buttonSetStateLine =
          locate('_toggled = !_toggled;', relativeFile: file).$1;
      expect(
        inFile('setstate_in_list_builder', file)
            .where((f) => f.location.line == buttonSetStateLine - 1),
        isEmpty,
      );
    });
  });
}
