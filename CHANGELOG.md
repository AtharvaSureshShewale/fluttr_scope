## 0.1.0

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
  missed: it's a function-typed variable, not a function).
