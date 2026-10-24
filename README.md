<h1 align="center">fluttr_scope</h1>

<p align="center">
  <b>Every other Flutter analyzer reads your code. This one runs it.</b><br>
  50 Flutter-specific checks, plus measured widget rebuilds and frame timing,<br>
  joined to the exact line of code that caused the finding.
</p>

<p align="center">
  <a href="https://pub.dev/packages/fluttr_scope"><img src="https://img.shields.io/pub/v/fluttr_scope?label=pub.dev&color=0175C2" alt="pub.dev version"></a>
  <a href="https://github.com/AtharvaSureshShewale/fluttr_scope/actions/workflows/ci.yml"><img src="https://github.com/AtharvaSureshShewale/fluttr_scope/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Flutter-3.35%2B-02569B?logo=flutter" alt="Flutter 3.35+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License: Apache-2.0"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#real-bugs-in-real-apps">Real bugs it found</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#rules">All rules</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/AtharvaSureshShewale/fluttr_scope/main/doc/images/dashboard.svg" alt="fluttr_scope dashboard: rule and test counts, CI status, rules by category, findings on Wonderous and Spotube, verification scores and roadmap" width="960">
</p>

## Why

A mid-sized Flutter app easily has thousands of analyzer warnings, so teams
ignore all of them, including the few that crash the app or leak a secret.
Static analyzers can't tell which warnings matter, because they never run the
app. fluttr_scope does both:

| | `flutter analyze` | Flutter DevTools | **fluttr_scope** |
|---|:---:|:---:|:---:|
| Flutter-specific checks (layout, lifecycle, rebuilds) | Dart lints | | ✅ 50 rules |
| Security: secrets, manifests, known CVEs | | | ✅ |
| Measures rebuilds and frame timing | | ✅ by hand | ✅ scripted, repeatable |
| Attaches runtime evidence to the finding's line | | | ✅ |
| Tells you which findings' code actually ran | | | ✅ |
| CI-ready: SARIF, exit codes, baselines | exit codes | | ✅ |

## Quick start

```sh
flutter pub add --dev fluttr_scope        # 1. add it to your app (dev only, never shipped)
dart run fluttr_scope analyze             # 2. 50 Flutter checks
dart run fluttr_scope security            # 3. secrets, manifests, CVEs: one verdict
dart run fluttr_scope prioritize          # 4. run the app: what to fix first
```

Step 4 needs a running emulator or connected phone. Prefer a global install?
`dart pub global activate fluttr_scope`, then `fluttr_scope analyze`.

## Real bugs in real apps

Everything below was found in public, well-known apps and **checked by hand
against the code**. Click through to the exact line.

<p align="center">
  <img src="https://raw.githubusercontent.com/AtharvaSureshShewale/fluttr_scope/main/doc/images/analyze-wonderous.svg" alt="fluttr_scope finding a hardcoded secret, a memory leak, a setState-after-await and a FutureBuilder restarting on every rebuild in the Wonderous app" width="900">
</p>

| App | Finding | Why it matters |
|---|---|---|
| [Wonderous](https://github.com/gskinnerTeam/flutter-wonderous-app) | [`PageController` never disposed](https://github.com/gskinnerTeam/flutter-wonderous-app/blob/ff1ab1b8d086a91bab09509d896450dfe83fcb6c/lib/ui/screens/home/wonders_home_screen.dart#L33) | Created in `initState`; `dispose()` releases a different controller but not this one. A memory leak, one of 5 in the app. |
| Wonderous | [`setState` after `await`](https://github.com/gskinnerTeam/flutter-wonderous-app/blob/ff1ab1b8d086a91bab09509d896450dfe83fcb6c/lib/ui/screens/home/wonders_home_screen.dart#L91) | Runs after a dialog closes, with no `mounted` check: throws if the user has left the screen. |
| Wonderous | [`FutureBuilder` restarts every rebuild](https://github.com/gskinnerTeam/flutter-wonderous-app/blob/ff1ab1b8d086a91bab09509d896450dfe83fcb6c/lib/ui/screens/editorial/widgets/_scrolling_content.dart#L272) | `future: _loadGoogleMap()` is created inside `build()`, so the map reloads whenever the parent rebuilds. |
| Wonderous | [API keys in source control](https://github.com/gskinnerTeam/flutter-wonderous-app/blob/ff1ab1b8d086a91bab09509d896450dfe83fcb6c/lib/logic/unsplash_service.dart#L5) | Unsplash access and secret keys, hardcoded in a public repo. |
| [Spotube](https://github.com/KRTirtho/spotube) | [`FutureBuilder` ignores errors](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/library/user_local_tracks/local_folder.dart#L156) | If reading the folder size fails, the screen silently shows **"0 GB"**. |

### A real 🔥: found, ranked first, fixed, measured

`prioritize` ran Wonderous's home screen 3 times with a [flow](#repeatable-flows)
that swipes through the wonders. Out of 183 findings, it ranked this one first:

```
🔥 lib/ui/wonder_illustrations/common/wonder_illustration_builder.dart:30:7  warning  setstate_in_animation_listener
    Measured at line 59 (nothing at this line is tracked): rebuilt 1230x (median of 3 run(s));
    125 of 223 frames it rebuilt in were slow (confidence medium).
```

[`..addListener(() => setState(() {}))`](https://github.com/gskinnerTeam/flutter-wonderous-app/blob/d30aee040e16b56c535f50588dc3e7b36a18f862/lib/ui/wonder_illustrations/common/wonder_illustration_builder.dart#L30)
rebuilds every illustration on every animation frame, though that `build` only
checks whether the animation is at 0. The fix: each
[illustration piece](https://github.com/gskinnerTeam/flutter-wonderous-app/blob/d30aee040e16b56c535f50588dc3e7b36a18f862/lib/ui/wonder_illustrations/common/illustration_piece.dart#L86)
animates itself with an `AnimatedBuilder`, and the listener calls `setState`
only when "at 0" changes (16 changed lines). Measured again, same flow, 3 runs:

| Per run (median) | Before | After |
|---|---|---|
| Widget rebuilds | ~28,500 | ~17,500 (**−38%**) |
| One illustration piece's rebuilds | 109 | 12 (**−89%**) |
| Slowest frame | 167 ms | 79 ms |
| Frames over budget | 16.5% | 20.0% |

The share of slow frames didn't drop: in debug mode on an emulator, frame time
is dominated by other costs. That's why fluttr_scope reports rebuilds during slow
frames as an association, never as proof that fixing them speeds the app up.
(Measured on commit `d30aee0`: the newest commit doesn't build for Android.)

<details>
<summary><b>How do we know the rules are right?</b> (click to expand)</summary>

<br>

Every rule was run against eight real Flutter apps (four private ones, plus
the open-source [Ente Photos](https://github.com/ente-io/ente),
[Spotube](https://github.com/KRTirtho/spotube),
[LocalSend](https://github.com/localsend/localsend) and
[Wonderous](https://github.com/gskinnerTeam/flutter-wonderous-app)), each hit
was read by hand, and every false positive was fixed with a test built from
the real code that fooled it.

- **139 → 6** errors across the first four apps; all 6 that remain are real.
- Real-app testing caught bugs that no unit test had: for example, runtime
  evidence never reached `Image.asset(...)` widgets, because Flutter records a
  named constructor 6 columns later than where the finding pointed.
- Hundreds of automated tests (the dashboard shows today's count). CI checks Flutter 3.35.2 and the latest stable,
  including installing the package into a fresh Flutter app.
- Rules favour precision over recall: when a rule can't be sure, it stays
  quiet rather than guess.

These 13 rules never fired on any of the eight apps, so they're tested only
against small examples so far (most catch crashes that rarely survive into
committed code): `bottom_navigation_bar_too_few_items`,
`container_color_and_decoration_conflict`, `flex_value_non_positive`,
`inherited_widget_of_in_initstate`, `insecure_certificate_validation`,
`insecure_random_for_secret`, `invalid_aspect_ratio`, `nested_scaffold`,
`opacity_out_of_range`, `sensitive_query_param`, `slider_invalid_range`,
`sql_table_missing_constraints`, `unrestricted_webview_javascript`.

</details>

## How it works

<p align="center">
  <img src="https://raw.githubusercontent.com/AtharvaSureshShewale/fluttr_scope/main/doc/images/how-it-works.svg" alt="Your code goes through 50 Flutter rules; your running app goes through the Dart VM service; both are joined on the exact source line into a ranked report" width="900">
</p>

The static side is a normal analyzer. The runtime side launches your app in
debug mode and asks the Dart VM which lines ran, which widgets rebuilt, and
how long each frame took. Flutter tags every widget with the file, line and
column it was created at, the same position the static rule reports, so the
two join exactly, with no guessing.

<p align="center">
  <img src="https://raw.githubusercontent.com/AtharvaSureshShewale/fluttr_scope/main/doc/images/measure-flow.svg" alt="Three flow-driven runs; the diagnosis says the app did the same work each run, so timing differences come from the device" width="900">
</p>

A **flow** (an ordinary `integration_test` file) drives the app the same way on
every run, so fluttr_scope can tell the app's own behaviour apart from device
noise, as in the run above. See [Repeatable flows](#repeatable-flows).

## Commands

Click a command to see its options.

<details>
<summary><code>analyze</code>: run the 50 static checks</summary>

<br>

```sh
fluttr_scope analyze [project_dir]
```

| Option | Default | |
|---|---|---|
| `--format` | `console` | `console`, `json`, or `sarif` |
| `--out <file>` | stdout | Write the report to a file |
| `--[no-]fatal-warnings` | on | Exit 1 on warnings |
| `--[no-]fatal-infos` | off | Exit 1 on infos |
| `--[no-]dependency-audit` | on | Check `pubspec.lock` against [OSV.dev](https://osv.dev) (needs network; use `--no-dependency-audit` offline) |
| `--coverage <lcov.info>` | `coverage/lcov.info` | Include line coverage in the report, if present |
| `--baseline <file>` | | Report only findings not in this baseline |
| `--write-baseline` | | Record all current findings as the baseline |

Exit codes match `dart analyze`: `0` clean, `1` findings at a fatal
severity, `2` invalid `fluttr_scope.yaml`, `64` bad command-line usage.
Errors are always fatal.

</details>

<details>
<summary><code>security</code>: is this app secure? One plain verdict</summary>

<br>

```sh
fluttr_scope security [project_dir]
```

Runs only the security rules, plus `AndroidManifest.xml` / `Info.plist`
checks and the dependency CVE audit (live [OSV.dev](https://osv.dev)
lookup at your exact locked versions), and gives a plain verdict:
**SECURE**, **NEEDS ATTENTION**, or **NOT SECURE**. Exits 1 only on NOT SECURE.

</details>

<details>
<summary><code>prioritize</code>: run the app, then rank every finding (experimental)</summary>

<br>

```sh
fluttr_scope prioritize [project_dir] --device emulator-5554 --runs 3 --seconds 15
fluttr_scope prioritize [project_dir] --device emulator-5554 --runs 3 --flow integration_test/my_flow_test.dart
```

Runs every static check, launches the app, and records which of your lines
actually ran (the Dart VM's own coverage) plus widget rebuilds and frame
timing. Then it ranks every finding:

| | Meaning |
|---|---|
| 🔥 | A performance finding whose widget rebuilt during slow frames: fix first |
| ▶ | The code ran during the session |
| ○ | Never ran in this session (or the file was never loaded) |
| — | No runtime signal: manifests, `pubspec.lock`, constants, tests |

Rebuild and frame data attaches to findings located on a widget's
constructor call (such as `missing_const_constructor`), so only those can
reach 🔥; every other finding is ranked by whether its code ran.

Drive the app with a [flow](#repeatable-flows) (`--flow`), or use it by
hand while it's measured, so the screens you care about actually run.
Runtime evidence only ranks findings: errors and warnings are always
listed, even when the code never ran. Info findings are shown only when
they ran during slow frames, unless you pass `--all`. `--format json` gives
every finding with its evidence.

</details>

<details>
<summary><code>measure</code>: rebuilds, frame timing and memory, over repeated runs (experimental)</summary>

<br>

```sh
fluttr_scope measure [project_dir] --device emulator-5554 --runs 5 --seconds 10 --warmup 3
fluttr_scope measure [project_dir] --device emulator-5554 --runs 3 --flow integration_test/my_flow_test.dart
```

Launches the app with `flutter run`, records widget rebuild counts by
source location and per-frame build/raster times over the VM Service, and
repeats it `--runs` times. It reports median, spread and a confidence
level for each metric, explains run-to-run variance, and joins the results
to the static performance findings:

- **Matched**: a static finding whose widget actually rebuilt, with the
  measured evidence attached.
- **Runtime-only**: a widget that rebuilt heavily during slow frames with
  no static rule explaining why.
- **Not exercised**: a static finding whose code never ran during the
  capture. No runtime claim is made for these.

`--device` can be omitted when exactly one device is connected.
`--technical` prints the raw report instead of the plain-language one.

</details>

<details>
<summary><code>correlate</code>: attach rebuild counts from a saved capture</summary>

<br>

```sh
fluttr_scope measure --runs 1 --format json --out capture.json
fluttr_scope correlate --runtime capture.json
```

Re-runs the static rules and attaches rebuild counts from a single saved
`measure` capture.

</details>

## Repeatable flows

A flow is an ordinary `integration_test` file that uses your app: taps,
scrolls, typing. Pass it with `--flow` and every measured run does the same
thing, so runs are comparable:

```sh
fluttr_scope prioritize --device emulator-5554 --runs 3 --flow integration_test/checkout_flow_test.dart
```

<details>
<summary><b>Write your first flow</b> (two packages, two calls)</summary>

<br>

Add the two packages it needs:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
  fluttr_scope: ^0.2.0
```

Then mark where the measured session starts and ends:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttr_scope/flow.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('checkout flow', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await waitForFluttrScope(); // recording starts here: startup is excluded

    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(Scrollable).first, const Offset(0, -800), 1500);
    await tester.pumpAndSettle();

    fluttrScopeDone(); // recording stops here
  });
}
```

`--seconds` becomes a time limit: recording stops as soon as the flow
calls `fluttrScopeDone()`. Outside fluttr_scope (a plain `flutter test`)
both calls are harmless, so the same file still works as a normal test.

A flow makes the *actions* identical every run. Rebuilds driven by
animations happen once per frame, though, so their count still follows the
device's frame rate: on an Android emulator, three runs of one flow gave
identical rebuild counts in one session (1,376 each) and 9.5% variation in
another, when the emulator was rendering fewer frames. For the steadiest
numbers, run flows on a physical device.

</details>

## Use it in a real project

<details>
<summary><b>Configure rules</b>: <code>fluttr_scope.yaml</code></summary>

<br>

Put a `fluttr_scope.yaml` at your project root. Every key is optional.

```yaml
exclude:
  - lib/generated/**
  - lib/l10n/**

rules:
  todo_comment: false            # turn a rule off
  avoid_print: error             # change its severity: info, warning, error
  dependency_vulnerability: warning
```

Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`) are always
skipped. An unknown rule id prints a warning, so typos don't fail silently.

</details>

<details>
<summary><b>Ignore a finding</b>: <code>// ignore: fluttr_scope/…</code></summary>

<br>

Same syntax as Dart's own ignore comments, with a `fluttr_scope/` prefix
so the ids can't collide with Dart lints of the same name:

```dart
// ignore: fluttr_scope/avoid_print
print('debug only');

final key = 'AKIA...'; // ignore: fluttr_scope/hardcoded_secret
```

```dart
// ignore_for_file: fluttr_scope/todo_comment, fluttr_scope/widget_returning_method
```

A comment on its own line applies to the next line. A comment at the end
of a line applies to that line.

</details>

<details>
<summary><b>Adopt it on an existing codebase</b>: baselines</summary>

<br>

```sh
fluttr_scope analyze --write-baseline        # writes fluttr_scope_baseline.json
fluttr_scope analyze --baseline fluttr_scope_baseline.json
```

Commit the baseline file. Only findings that aren't in it are reported.
Findings are matched by rule, file, message and the text of the flagged
line, not the line number, so editing code above a known finding doesn't
bring it back as "new", and a new finding with the same message as an old
one is still caught.

</details>

<details>
<summary><b>Run it in CI</b>: GitHub Actions + Code Scanning</summary>

<br>

```yaml
- uses: subosito/flutter-action@v2
- run: flutter pub get
- run: dart run fluttr_scope analyze --format sarif --out fluttr_scope.sarif
  continue-on-error: true
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: fluttr_scope.sarif
```

Findings then show up as annotations on pull requests.

</details>

<details>
<summary><b>Runtime limitations, stated plainly</b></summary>

<br>

- **Debug mode only.** Flutter's rebuild tracking lives inside an
  `assert()` and is compiled out of profile/release builds, so absolute
  timings are slower than release. Compare runs against each other, not
  against release.
- **Without a flow, runs vary.** A capture without `--flow` is a fixed
  window after launch; use the app the same way each run, or numbers will
  vary (the report tells you when they do). With a flow, the app does the
  same things every run, but frame timing (and animation-driven rebuild
  counts) still vary with the device; an emulator is noisier than a
  physical phone.
- **60 Hz frame budget is assumed**, not read from the device.
- **Association, not causation.** "Rebuilt during slow frames" is a
  measured overlap, and the report says so on every finding.
- Thresholds (50 rebuilds = high, ≥3 slow frames and ≥30% overlap = high
  impact, run-to-run variation ≤10% = high confidence) are stated judgment
  calls and may change.

</details>

## Rules

50 rules check your Dart code; 3 more check `AndroidManifest.xml`,
`Info.plist` and `pubspec.lock` (marked † below). Click a category to see
its rules. Ids in **bold** are the ones runtime evidence attaches to most
directly.

<details>
<summary><b>Performance</b> · 11 rules</summary>

<br>

| Rule | Default | Flags |
|---|---|---|
| **`missing_const_constructor`** | warning | A widget that could be `const` but isn't |
| `future_created_in_build` | warning | `FutureBuilder.future` / `StreamBuilder.stream` created inline in `build()`, so it re-fires every rebuild |
| `key_created_in_build` | warning | `GlobalKey` / `UniqueKey` constructed in `build()` |
| `dispose_missing` | warning | A controller / subscription the `State` creates but `dispose()` never releases |
| **`setstate_in_list_builder`** | info | `setState` inside an `itemBuilder`, which rebuilds the whole list on every tap |
| `shrinkwrap_listview` | info | `shrinkWrap: true` on a scrollable |
| `empty_container_instead_of_sizedbox` | info | An empty `Container()` used for spacing |
| **`widget_returning_method`** | info | A method on a widget / `State` returning `Widget` instead of a widget class |
| **`setstate_in_animation_listener`** | warning | `setState` in an animation's listener, which rebuilds the whole widget on every frame |
| **`opacity_in_animation`** | info | `Opacity(opacity: animation.value)`, which rebuilds its child every frame; `FadeTransition` doesn't |
| `media_query_of_single_property` | info | `MediaQuery.of(context).size` (or `.padding`, ...), which rebuilds on any MediaQuery change; `MediaQuery.sizeOf(context)` doesn't |

</details>

<details>
<summary><b>Correctness</b> · 19 rules</summary>

<br>

| Rule | Default | Flags |
|---|---|---|
| `unbounded_scrollable_in_flex` | error | A scrollable directly in a `Column` / `Row` without `Expanded` |
| `expanded_outside_flex` | error | `Expanded` / `Flexible` outside a `Column` / `Row` / `Flex` |
| `positioned_outside_stack` | error | `Positioned` outside a `Stack` |
| `inherited_widget_of_in_initstate` | error | `Theme.of(context)` etc. in `initState()` |
| `container_color_and_decoration_conflict` | error | `Container` with both `color` and `decoration` |
| `opacity_out_of_range` | error | Literal opacity outside `[0, 1]` |
| `invalid_aspect_ratio` | error | Literal `aspectRatio <= 0` |
| `flex_value_non_positive` | error | Literal `flex <= 0` |
| `slider_invalid_range` | error | Literal `Slider` `min >= max` |
| `bottom_navigation_bar_too_few_items` | error | `BottomNavigationBar` with fewer than 2 items |
| `missing_mounted_check` | warning | `setState` after `await` with no `mounted` check |
| `nested_scaffold` | warning | A `Scaffold` inside another `Scaffold` |
| `build_context_stored_in_field` | warning | A `BuildContext` assigned to a field |
| `missing_list_key` | warning | `.map(...).toList()` items that hold state (`TextField`, `ExpansionTile`, your own `StatefulWidget`s) with no `key:` |
| `future_builder_missing_error_check` | warning | `FutureBuilder` that never checks `snapshot.hasError` |
| `stream_builder_missing_error_check` | warning | `StreamBuilder` that never checks `snapshot.hasError` |
| `image_network_without_error_builder` | info | `Image.network` with no `errorBuilder` |
| `scaffold_missing_body` | info | `Scaffold` with no `body` |
| `setstate_in_build` | info | `setState` inside a widget's own `build()`, which Flutter ignores |

</details>

<details>
<summary><b>Security</b> · 13 rules + 3 file checks</summary>

<br>

| Rule | Default | Flags |
|---|---|---|
| `hardcoded_secret` | error | AWS / Google / Stripe / GitHub / Slack key shapes, or a random-looking literal assigned to a secret-named variable or argument (`clientSecret`, `apiKey`, `accessToken`, ...) |
| `sql_injection_risk` | error | Raw SQL that splices in a value that could carry user input |
| `insecure_certificate_validation` | error | `badCertificateCallback` that always returns `true` |
| `dependency_vulnerability` † | error | A known CVE in a locked dependency version (OSV.dev) |
| `insecure_http_url` | warning | A cleartext `http://` URL to a non-local host (loopback, LAN and `.local` dev hosts are fine) |
| `sensitive_query_param` | warning | A token / password / key passed in a URL query |
| `insecure_random_for_secret` | warning | `Random()` (not `Random.secure()`) for a secret-named value |
| `unrestricted_webview_javascript` | warning | `JavaScriptMode.unrestricted` |
| `textfield_password_not_obscured` | warning | A password field without `obscureText: true` |
| `avoid_logging_sensitive_data` | warning | `print` / `debugPrint` of a secret-named String value |
| `insecure_storage_of_sensitive_data` | warning | A secret-named key in `SharedPreferences` |
| `sql_table_missing_constraints` | warning | `CREATE TABLE` with no constraints at all |
| `android_cleartext_traffic_enabled` † | warning | `usesCleartextTraffic="true"` in `AndroidManifest.xml` |
| `ios_arbitrary_loads_enabled` † | warning | `NSAllowsArbitraryLoads` in `Info.plist` |
| `hardcoded_ip_address` | info | A non-loopback IP literal |
| `weak_hash_algorithm` | info | `md5` / `sha1` from `package:crypto` |

</details>

<details>
<summary><b>Accessibility</b> · 2 rules</summary>

<br>

| Rule | Default | Flags |
|---|---|---|
| `missing_tooltip_for_iconbutton` | warning | `IconButton` with no `tooltip` |
| `image_missing_semantic_label` | info | `Image` with no `semanticLabel` |

</details>

<details>
<summary><b>Style</b> · 5 rules</summary>

<br>

| Rule | Default | Flags |
|---|---|---|
| `avoid_print` | info | Bare `print(...)` |
| `deeply_nested_widget_tree` | info | A `build()` tree nested too deep |
| `todo_comment` | info | `TODO` / `FIXME` comments |
| `unnecessary_column_or_row` | info | `Column` / `Row` with a single plain child and no alignment or sizing |
| `empty_flex_children` | info | `Column` / `Row` with no children |

</details>

## Use it as a library

```dart
import 'package:fluttr_scope/fluttr_scope.dart';

Future<void> main() async {
  final findings = await AnalysisEngine(allRules()).analyze('path/to/app');
  print(toSarifReport(findings));
}
```

You can add your own rules by extending `StaticRule`. See
[`example/example.dart`](example/example.dart).

## License

Apache-2.0. See [LICENSE](LICENSE).
