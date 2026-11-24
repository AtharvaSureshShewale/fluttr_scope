## 0.6.0

- **`measure --profile`**: frame timings from a profile build, close to
  what users see. Physical devices only (emulators can't run profile
  builds). Rebuild counts and coverage exist only in debug builds, so they
  are left out of a profile measurement's JSON; `compare` warns when one
  side is debug and the other profile.
- **Measured on a real Android phone**: the Wonderous listener fix cut
  frames over budget from 14.6% to 11.8% (every run after beat every run
  before) and rebuilds by 23%, in a debug build. In a profile build the
  phone was already smooth (0.1% of frames over budget, slowest 18 ms)
  with no clear change: the fix removes wasted work, but users of this
  phone wouldn't notice.
- The 13 rules never seen on a real app also stayed silent on 32 more
  (Flutter's sample apps): no false alarms, still no real-world hits.

- **HTML reports**: `--format html` on `analyze`, `prioritize` and
  `compare` writes one self-contained page (no scripts, no network; light
  and dark mode; works on a phone): findings with the code around them,
  fix-first findings on top, before/after bars per file. String values in
  snippets of secret-related findings are masked (`'dxqH••••'`), since
  reports are made to be shared.

- **`--fix` for `insecure_random_for_secret`**: `Random()` →
  `Random.secure()`. Same type and methods, unpredictable output instead
  of guessable. A seeded `Random(42)` is still flagged but not changed (the
  seed means repeatable numbers are wanted).

## 0.5.0

- **`compare before.json after.json`**: did a change make the app faster?
  Compares two `measure --runs N --format json` results (frames over
  budget, slowest frame, jank clusters, rebuilds, and rebuilds per file).
  A metric is better or worse only when every run after beat (or lost to)
  every run before; anything less is "no clear change". Warns when the
  measurements aren't comparable (no flow, different flows or devices).
  `--fail-on-regression` exits 1 when frame timing or rebuilds got worse.
  Per-file changes under 10% aren't listed (with hundreds of files, some
  tiny changes line up by chance).
- `measure --format json` now includes `rebuildsPerRun` and
  `rebuildsByFilePerRun` (steady-state rebuilds in each valid run).
- **analyzer 11 and 12** are now allowed (`>=10.0.1 <13.0.0`; the full
  test suite passes on 10, 11 and 12), so fluttr_scope installs in apps on
  newer Flutter versions too. Flutter 3.35 apps still get analyzer 10.
- **Fix:** `empty_container_instead_of_sizedbox` suggested `SizedBox()`,
  which isn't equivalent: an empty `Container()` fills the space its
  parent allows, a bare `SizedBox()` takes none. On Wonderous, following it
  would have shrunk a screen reader's focus area to nothing. It now
  suggests `const SizedBox.expand()` or `const SizedBox.shrink()`.

## 0.4.0

- **`analyze --fix`**: applies the fixes that can't change what the app
  does, then reports what's left; `--fix --dry-run` shows the diff instead.
  Covers `missing_const_constructor` (adds `const`, only on the outermost
  of nested widgets) and `media_query_of_single_property`
  (`MediaQuery.of(context).size.width` → `MediaQuery.widthOf(context)`).
  Each changed file is analyzed again first and left alone if the fixes
  would add a compile error (e.g. `const Opacity(opacity: 1.5)`, which
  fails Flutter's asserts at compile time). On Wonderous: 75 findings fixed
  in 39 files, `dart analyze` output unchanged.
- `Fix` has `edits` (offset, length, replacement), included in the JSON
  report as `fix.edits`.
- **Fix:** `missing_const_constructor` no longer flags a widget whose type
  argument is a type parameter (`Box<T>()`), or one passed a record
  literal; neither can be `const`.

## 0.3.1

- **Flows no longer need `--seconds`.** With `--flow`, `--seconds` is only
  a time limit (recording stops when the flow finishes), but it defaulted to
  15s (`prioritize`) or 10s (`measure`), and since 0.3.0 a run whose flow
  hits the limit is discarded. So any flow longer than that, as most real
  ones are, gave 0 valid runs unless you raised `--seconds`, which the
  README examples didn't. With `--flow` the default is now 300s. Without a
  flow, the defaults are unchanged.
- Reports from a flow say "until the flow finished (limit Ns)" instead of
  showing the time limit as if it were the measured time.
- **README:** the install snippet said `^0.2.0`; a test now keeps it in
  step with `pubspec.yaml`.

## 0.3.0

- **3 new performance rules**, each checked by hand on real apps
  (Wonderous, Spotube and 4 others: 139 findings, no false alarms):
  - `setstate_in_animation_listener`: `setState` in an `Animation`'s
    listener, rebuilding the whole widget on every frame;
  - `opacity_in_animation`: `Opacity` driven by an animation's `.value`
    (use `FadeTransition`);
  - `media_query_of_single_property`: `MediaQuery.of(context).size` and
    friends, which rebuild on any MediaQuery change (use
    `MediaQuery.sizeOf(context)`, `widthOf`, `paddingOf`, ...).
- **Runtime evidence for code Flutter doesn't track.** Flutter only
  reports rebuilds of widgets with a `build` method, so a finding on an
  `Opacity`, `Padding` or `SizedBox`, an inline `GlobalKey` or future, or a
  `setState` call never had rebuild data and could never rank as fix-first.
  These findings now take their evidence from the widgets that re-run the
  code (the report names which). Found on Wonderous: an `Opacity` whose
  parent rebuilt 4,611 times showed nothing.
- **Fix:** a named constructor with type arguments (`Provider<T>.value(...)`)
  is matched to its rebuild data at the type, where Flutter reports it.
- **Fix:** with `--flow`, a run that hits the `--seconds` limit before the
  flow finishes no longer counts (it measured only part of the flow); the
  report says to raise `--seconds`. `measure --runs 1` warns instead.

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
