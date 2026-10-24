## Unreleased

- **3 new performance rules**, each checked by hand on real apps
  (Wonderous, Spotube and 4 others: 139 findings, no false alarms):
  - `setstate_in_animation_listener`: `setState` in an `Animation`'s
    listener, rebuilding the whole widget on every frame;
  - `opacity_in_animation`: `Opacity` driven by an animation's `.value`
    (use `FadeTransition`);
  - `media_query_of_single_property`: `MediaQuery.of(context).size` and
    friends, which rebuild on any MediaQuery change (use
    `MediaQuery.sizeOf(context)`, `widthOf`, `paddingOf`, ...).

## 0.2.0

First release on pub.dev. Includes everything in 0.1.0 (tagged in git,
never published) plus:

- **Repeatable flows**: `measure --flow` / `prioritize --flow` run an
  `integration_test` file as the app, so every run does the same thing.
  `package:fluttr_scope/flow.dart` marks where recording starts
  (`waitForFluttrScope()`, which excludes app startup) and stops
  (`fluttrScopeDone()`). Variance reports say whether a flow was used.
- **Riverpod**: rules that check widget `build` methods
  (`future_created_in_build`, `key_created_in_build`,
  `deeply_nested_widget_tree`, `setstate_in_build`) now also cover
  `build(BuildContext context, WidgetRef ref)`.
- **analyzer 10** (from 7.7). The constraint is `^10.0.1`, so fluttr_scope
  installs as a dev dependency in Flutter 3.35 apps (analyzer 10.0.2+ needs
  `meta` 1.18, which Flutter 3.35 pins at 1.16), and newer setups get 10.2.
  Findings on eight real apps are identical before and after. CI tests
  Flutter 3.35.2 and the latest stable, including installing the package
  into a fresh Flutter app.
- `dispose_missing` only flags controllers the class creates itself, not
  ones handed in from elsewhere or never assigned.
- `setstate_in_build` is now info: Flutter ignores a rebuild request made
  during a widget's own build, so it's pointless code, not a crash.
- `measure` / `prioritize` report a failed app launch (build error, unknown
  device) as soon as `flutter run` exits, with its last lines of output,
  instead of waiting for the timeout and printing a stack trace; multi-run
  stops after the first failed launch.
- **Breaking for custom rules:** `StaticRule` has a new `category` getter
  that every rule must implement (e.g. `Category get category =>
  Category.style;`). The built-in rules all declare theirs.

## 0.1.0 (git tag only)

First public release.

- `analyze`: 47 Flutter-specific static rules (performance, correctness,
  security, accessibility, style), OSV.dev dependency audit, lcov coverage,
  console / JSON / SARIF output.
- `security`: security-only rules, Android/iOS manifest checks and the
  dependency audit, with a SECURE / NEEDS ATTENTION / NOT SECURE verdict.
- `measure` (experimental): rebuild counts per source location and frame
  timing over the VM Service, across multiple runs with confidence levels,
  joined to static performance findings.
- `correlate`: attaches rebuild counts from a saved capture to static
  findings.
- `prioritize` (experimental): ranks every static finding by runtime
  evidence -- ran during slow frames, ran, never ran, no signal -- using
  the VM's line coverage plus rebuild/frame timing. `measure` captures now
  include which app lines ran (`executedLines` in JSON).
- `fluttr_scope.yaml`: exclude paths, disable rules, override severities.
- `// ignore: fluttr_scope/<rule>` and `// ignore_for_file:` comments.
- Baselines (`--write-baseline`, `--baseline`) for adopting on existing
  projects.
- `dart analyze`-style exit codes (`--fatal-warnings`, `--fatal-infos`).
- `measure --device` auto-detects when exactly one device is connected.

Rule accuracy, checked against real apps before release:

- `expanded_outside_flex` / `positioned_outside_stack` no longer flag
  widgets built by `.map(...)`, `List.generate`, collection `if`/`for`,
  spreads, or helper methods. They flag only a visibly wrong framework
  parent, and now catch `Positioned` inside `IndexedStack`.
- `unbounded_scrollable_in_flex` follows the framework's viewport
  assertions: no longer flags `SingleChildScrollView` or vertical
  `shrinkWrap: true` lists in a `Column`; now catches `PageView`,
  horizontal lists in a `Column`, and scrollables inside collection `if`.
- `missing_mounted_check` recognises `if (mounted) {...}`,
  `mounted && ...`, `context.mounted`, and guards nested in `try` blocks;
  no longer treats `if (mounted) return;` as a guard; now also checks
  `setState` in `catch`/`finally` after an awaited `try`, and ignores
  awaits in branches that always return.
- `avoid_logging_sensitive_data` now checks `debugPrint` (previously
  missed: it's a function-typed variable, not a function), and only flags
  logged *String* values with a secret-like name -- not `$authError`,
  `$isPasswordValid`, or `${token.length}`.
- `hardcoded_secret` also catches secrets without a provider-specific
  shape: a random-looking literal assigned to a secret-named variable or
  named argument (`clientSecret`, `apiKey`, `accessToken`, ...).
  Placeholders, key names, labels, and URLs are not flagged.
- `insecure_http_url` treats private LAN addresses and `.local` hosts as
  dev hosts, ignores a bare `'http://'` prefix check, and no longer treats
  `http://localhost.evil.com` as local.
- `missing_list_key` only flags items that hold state (`TextField`, form
  fields, `ExpansionTile`, app-defined `StatefulWidget`s); now a
  correctness rule.
- `unnecessary_column_or_row` skips single-child flexes that set
  alignment or sizing, wrap `Flexible`/`Expanded`/`Spacer`, or use
  `if`/`for`/spread elements.
- `widget_returning_method` only flags instance members of widget and
  `State` classes; it and `deeply_nested_widget_tree` now point at the
  method name instead of its doc comment or `@override`.
- `avoid_print`, `shrinkwrap_listview`, and `setstate_in_list_builder`
  default to info (advisory; raise them in `fluttr_scope.yaml`).
- `sql_injection_risk` no longer flags queries that only splice in schema
  names, constants, numbers, or `?` placeholder lists.
- `scaffold_missing_body` only flags Flutter's own `Scaffold`, not a UI
  library's.
- `hardcoded_ip_address` and `insecure_http_url` skip test files and text
  shown to the user (`Text(...)`, hints, labels).
- `FutureBuilder`/`StreamBuilder` error-check message now describes what
  actually happens (silent stale or loading UI, not an exception).
- Baselines record each finding's line text, so a new finding with the same
  message as a known one is reported instead of hidden.
- Findings on named constructors (`Image.asset(...)`, `ListView.builder(...)`)
  are reported at the constructor name, the column Flutter's widget-creation
  tracking uses, so they now join with their runtime rebuild data.
- `prioritize` only ranks *performance* findings as hot: slow frames aren't
  evidence for an accessibility or security finding that merely ran.
