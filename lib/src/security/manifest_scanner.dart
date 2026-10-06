import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/category.dart';
import '../model/finding.dart';
import '../model/severity.dart';
import '../model/source_location.dart';

/// Scans platform config files (`AndroidManifest.xml`, `Info.plist`) for
/// a handful of well-known insecure settings.
///
/// Text-pattern based, not a full XML/plist parse — the settings checked
/// for are distinctive attribute/key names that don't need a parser to
/// find reliably, and this is the one part of the pipeline Dart's own
/// AST-based rules can never see: the app's actual network-security
/// posture is set at the platform-config level, not in Dart source.
List<Finding> scanManifests(String root) => [
      ..._scanAndroidManifest(root),
      ..._scanInfoPlist(root),
    ];

List<Finding> _scanAndroidManifest(String root) {
  const needle = 'android:usesCleartextTraffic="true"';
  final findings = <Finding>[];

  for (final relative in const [
    'android/app/src/main/AndroidManifest.xml',
    'android/app/src/debug/AndroidManifest.xml',
  ]) {
    final file = File(p.join(root, relative));
    if (!file.existsSync()) continue;

    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final column = lines[i].indexOf(needle);
      if (column == -1) continue;
      findings.add(Finding(
        ruleId: 'android_cleartext_traffic_enabled',
        category: Category.security,
        severity: Severity.warning,
        message: '`usesCleartextTraffic="true"` allows the app to make '
            'unencrypted HTTP connections anywhere. Remove it, or scope '
            'cleartext exceptions to specific domains via a Network '
            'Security Config instead.',
        location: SourceLocation(
          file: relative,
          line: i + 1,
          column: column + 1,
          length: needle.length,
        ),
      ));
    }
  }

  return findings;
}

List<Finding> _scanInfoPlist(String root) {
  const relative = 'ios/Runner/Info.plist';
  final file = File(p.join(root, relative));
  if (!file.existsSync()) return const [];

  final findings = <Finding>[];
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('NSAllowsArbitraryLoads')) continue;
    // plist pairs a <key> with its value on a following line — check a
    // small window after the key for the boolean that enables it.
    final window = lines.skip(i).take(3).join('\n');
    if (!window.contains('<true/>')) continue;

    findings.add(Finding(
      ruleId: 'ios_arbitrary_loads_enabled',
      category: Category.security,
      severity: Severity.warning,
      message: '`NSAllowsArbitraryLoads` is enabled, disabling App '
          'Transport Security app-wide and allowing unencrypted HTTP '
          'connections. Scope exceptions to specific domains instead.',
      location: SourceLocation(
        file: relative,
        line: i + 1,
        column: lines[i].indexOf('NSAllowsArbitraryLoads') + 1,
        length: 'NSAllowsArbitraryLoads'.length,
      ),
    ));
  }

  return findings;
}
