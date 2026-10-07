# fluttr_scope

Flutter-aware static analysis, plus something `flutter analyze` can't do: it
**runs your app**, measures widget rebuilds and frame timing, and attaches
that evidence to the exact source line a static rule flagged.

> `missing_const_constructor` at `lib/product_grid.dart:42:12` → rebuilt 487×
> during the capture, 8 of those frames over budget.

- **47 Flutter-specific rules** across performance, correctness, security,
  accessibility and style. See the [rule list](#rules).
- **Security check**: hardcoded secrets, cleartext traffic, unsafe
  randomness, Android/iOS manifest settings, and known CVEs in your locked
  dependencies (via [OSV.dev](https://osv.dev)).
- **Runtime evidence**: rebuild counts per source location and frame
  build/raster timing, repeated over several runs with stated confidence.
- **CI-ready**: SARIF output for GitHub Code Scanning, `dart analyze`-style
  exit codes, and a baseline so existing projects fail only on new findings.

## Install

As a dev dependency (recommended, since the version is pinned per project):

```sh
flutter pub add --dev fluttr_scope
dart run fluttr_scope analyze
```

Or globally:

```sh
dart pub global activate fluttr_scope
fluttr_scope analyze
```

fluttr_scope is a dev tool only. Nothing from it ends up in your app.

## Commands

### `analyze`: static rules

```sh
fluttr_scope analyze [project_dir]
```

| Option | Default | |
|---|---|---|
| `--format` | `console` | `console`, `json`, or `sarif` |
| `--out <file>` | stdout | Write the report to a file |
| `--[no-]fatal-warnings` | on | Exit 1 on warnings |
| `--[no-]fatal-infos` | off | Exit 1 on infos |
| `--[no-]dependency-audit` | on | Check `pubspec.lock` against OSV.dev (needs network; use `--no-dependency-audit` offline) |
| `--coverage <lcov.info>` | `coverage/lcov.info` | Include line coverage in the report, if present |
| `--baseline <file>` | | Report only findings not in this baseline |
| `--write-baseline` | | Record all current findings as the baseline |

Exit codes match `dart analyze`: `0` clean, `1` findings at a fatal
severity, `2` invalid `fluttr_scope.yaml`, `64` bad command-line usage.
Errors are always fatal.

### `security`: is this app secure?

```sh
fluttr_scope security [project_dir]
```

Runs only the security rules, plus `AndroidManifest.xml` / `Info.plist`
checks and the dependency CVE audit, and gives a plain verdict:
**SECURE**, **NEEDS ATTENTION**, or **NOT SECURE**. Exits 1 only on NOT SECURE.

### `prioritize`: what to fix first (experimental)

```sh
fluttr_scope prioritize [project_dir] --device emulator-5554 --runs 3 --seconds 15
```

A large app can have thousands of findings, and nobody fixes thousands of
findings. `prioritize` runs every static check, launches the app, and
records which of your lines actually ran (the Dart VM's own coverage) plus
widget rebuilds and frame timing. Then it ranks every finding:

| | Meaning |
|---|---|
| 🔥 | A performance finding whose widget rebuilt during slow frames: fix first |
| ▶ | The code ran during the session |
| ○ | Never ran in this session (or the file was never loaded) |
| — | No runtime signal: manifests, `pubspec.lock`, constants, tests |

Rebuild and frame data attaches to findings located on a widget's
constructor call (such as `missing_const_constructor`), so only those can
reach 🔥; every other finding is ranked by whether its code ran.

Use the app while it's measured, so the screens you care about actually
run. Runtime evidence only ranks findings: errors and warnings are always
listed, even when the code never ran. Info findings are shown only when
they ran during slow frames, unless you pass `--all`. `--format json` gives
every finding with its evidence.

### `measure`: runtime evidence (experimental)

```sh
fluttr_scope measure [project_dir] --device emulator-5554 --runs 5 --seconds 10 --warmup 3
```

Launches the app with `flutter run`, records widget rebuild counts by
source location and per-frame build/raster times over the VM Service, and
repeats it `--runs` times. It reports median, spread and a confidence
level for each metric. It then joins the results to the static
performance findings:

- **Matched**: a static finding whose widget actually rebuilt, with the
  measured evidence attached.
- **Runtime-only**: a widget that rebuilt heavily during slow frames with
  no static rule explaining why.
- **Not exercised**: a static finding whose code never ran during the
  capture. No runtime claim is made for these.

`--device` can be omitted when exactly one device is connected.
`--technical` prints the raw report instead of the plain-language one.

### `correlate`: join a saved capture

```sh
fluttr_scope measure --runs 1 --format json --out capture.json
fluttr_scope correlate --runtime capture.json
```

Re-runs the static rules and attaches rebuild counts from a single saved
`measure` capture.

### Runtime limitations, stated plainly

- **Debug mode only.** Flutter's rebuild tracking lives inside an
  `assert()` and is compiled out of profile/release builds, so absolute
  timings are slower than release. Compare runs against each other, not
  against release.
- **No scripted interaction yet.** A capture is a fixed window after
  launch, not a repeatable user flow. Interact with the app the same way
  each run, or numbers will vary (the report tells you when they do).
- **60 Hz frame budget is assumed**, not read from the device.
- **Association, not causation.** "Rebuilt during slow frames" is a
  measured overlap, and the report says so on every finding.
- Thresholds (50 rebuilds = high, ≥3 slow frames and ≥30% overlap = high
  impact, run-to-run variation ≤10% = high confidence) are stated judgment
  calls and may change.

## Configuration

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

## Ignoring a finding

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

## Adopting on an existing project

```sh
fluttr_scope analyze --write-baseline        # writes fluttr_scope_baseline.json
fluttr_scope analyze --baseline fluttr_scope_baseline.json
```

Commit the baseline file. Findings are matched by rule, file and message,
not line number, so editing code above a known finding doesn't bring it
back as "new".

## CI: GitHub Actions + Code Scanning

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

## Rules

Ids in **bold** are the ones runtime evidence attaches to most directly.

### Performance
| Rule | Default | Flags |
|---|---|---|
| **`missing_const_constructor`** | warning | A widget that could be `const` but isn't |
| `future_created_in_build` | warning | `FutureBuilder.future` / `StreamBuilder.stream` created inline in `build()`, so it re-fires every rebuild |
| `key_created_in_build` | warning | `GlobalKey` / `UniqueKey` constructed in `build()` |
| `dispose_missing` | warning | A controller / subscription field on a `State` that `dispose()` never releases |
| **`setstate_in_list_builder`** | info | `setState` inside an `itemBuilder`, which rebuilds the whole list on every tap |
| `shrinkwrap_listview` | info | `shrinkWrap: true` on a scrollable |
| `empty_container_instead_of_sizedbox` | info | An empty `Container()` used for spacing |
| **`widget_returning_method`** | info | A method on a widget / `State` returning `Widget` instead of a widget class |

### Correctness
| Rule | Default | Flags |
|---|---|---|
| `setstate_in_build` | error | `setState` called directly during `build()` |
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

### Security
| Rule | Default | Flags |
|---|---|---|
| `hardcoded_secret` | error | AWS / Google / Stripe / GitHub / Slack key shapes, or a random-looking literal assigned to a secret-named variable or argument (`clientSecret`, `apiKey`, `accessToken`, ...) |
| `sql_injection_risk` | error | Raw SQL built by interpolation or `+` |
| `insecure_certificate_validation` | error | `badCertificateCallback` that always returns `true` |
| `dependency_vulnerability` | error | A known CVE in a locked dependency version (OSV.dev) |
| `insecure_http_url` | warning | A cleartext `http://` URL to a non-local host (loopback, LAN and `.local` dev hosts are fine) |
| `sensitive_query_param` | warning | A token / password / key passed in a URL query |
| `insecure_random_for_secret` | warning | `Random()` (not `Random.secure()`) for a secret-named value |
| `unrestricted_webview_javascript` | warning | `JavaScriptMode.unrestricted` |
| `textfield_password_not_obscured` | warning | A password field without `obscureText: true` |
| `avoid_logging_sensitive_data` | warning | `print` / `debugPrint` of a secret-named String value |
| `insecure_storage_of_sensitive_data` | warning | A secret-named key in `SharedPreferences` |
| `sql_table_missing_constraints` | warning | `CREATE TABLE` with no constraints at all |
| `android_cleartext_traffic_enabled` | warning | `usesCleartextTraffic="true"` in `AndroidManifest.xml` |
| `ios_arbitrary_loads_enabled` | warning | `NSAllowsArbitraryLoads` in `Info.plist` |
| `hardcoded_ip_address` | info | A non-loopback IP literal |
| `weak_hash_algorithm` | info | `md5` / `sha1` from `package:crypto` |

### Accessibility
| Rule | Default | Flags |
|---|---|---|
| `missing_tooltip_for_iconbutton` | warning | `IconButton` with no `tooltip` |
| `image_missing_semantic_label` | info | `Image` with no `semanticLabel` |

### Style
| Rule | Default | Flags |
|---|---|---|
| `avoid_print` | info | Bare `print(...)` |
| `deeply_nested_widget_tree` | info | A `build()` tree nested too deep |
| `todo_comment` | info | `TODO` / `FIXME` comments |
| `unnecessary_column_or_row` | info | `Column` / `Row` with a single plain child and no alignment or sizing |
| `empty_flex_children` | info | `Column` / `Row` with no children |

Rules favour precision over recall: when a rule can't be sure, it stays
quiet rather than report a false positive.

Every rule was run against seven real Flutter apps (four private, plus the
open-source [Ente Photos](https://github.com/ente-io/ente),
[Spotube](https://github.com/KRTirtho/spotube) and
[LocalSend](https://github.com/localsend/localsend)), each hit checked by
hand, and false positives fixed. These rules never fired on any of them, so
they're only tested against small examples so far (most catch crashes that
rarely survive into committed code): `bottom_navigation_bar_too_few_items`, `container_color_and_decoration_conflict`, `flex_value_non_positive`, `inherited_widget_of_in_initstate`, `insecure_certificate_validation`, `insecure_random_for_secret`, `invalid_aspect_ratio`, `nested_scaffold`, `opacity_out_of_range`, `sensitive_query_param`, `setstate_in_build`, `slider_invalid_range`, `sql_table_missing_constraints`, `unrestricted_webview_javascript`.

## Using it as a library

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
