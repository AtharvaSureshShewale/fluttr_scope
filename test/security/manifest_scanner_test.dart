import 'dart:io';

import 'package:fluttr_scope/src/security/manifest_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _root = p.join(Directory.current.path, 'test', 'fixtures', 'manifest_project');

void main() {
  test('flags android:usesCleartextTraffic="true" in AndroidManifest.xml', () {
    final findings = scanManifests(_root);
    final match = findings.where((f) => f.ruleId == 'android_cleartext_traffic_enabled');
    expect(match, hasLength(1));
    expect(match.single.location.file, 'android/app/src/main/AndroidManifest.xml');
    expect(match.single.location.line, 4);
  });

  test('flags NSAllowsArbitraryLoads enabled in Info.plist', () {
    final findings = scanManifests(_root);
    final match = findings.where((f) => f.ruleId == 'ios_arbitrary_loads_enabled');
    expect(match, hasLength(1));
    expect(match.single.location.file, 'ios/Runner/Info.plist');
    expect(match.single.location.line, 9);
  });

  test('returns no findings when neither manifest file exists', () {
    final emptyRoot = p.join(Directory.current.path, 'test', 'fixtures', 'does_not_exist');
    expect(scanManifests(emptyRoot), isEmpty);
  });

  test('does not flag a clean AndroidManifest.xml with no cleartext attribute', () {
    // sample_app's real, unmodified manifest (scaffolded by `flutter
    // create`, never had the attribute added) is the negative-case proof.
    final sampleAppRoot =
        p.join(Directory.current.path, 'test', 'fixtures', 'sample_app');
    expect(
      scanManifests(sampleAppRoot).where((f) => f.ruleId == 'android_cleartext_traffic_enabled'),
      isEmpty,
    );
  });
}
