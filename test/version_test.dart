import 'dart:io';

import 'package:fluttr_scope/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version']);
  });

  test('README install snippets use the current minor version', () {
    // pub.dev shows the README of the published version, so a stale
    // `fluttr_scope: ^x.y.z` there sends new users to an old release.
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final version = (pubspec['version'] as String).split('.');
    final current = '${version[0]}.${version[1]}';
    final readme = File('README.md').readAsStringSync();
    final pins = RegExp(r'fluttr_scope: \^(\d+)\.(\d+)\.\d+').allMatches(readme).toList();
    expect(pins, isNotEmpty, reason: 'README should show how to install fluttr_scope');
    for (final pin in pins) {
      expect('${pin[1]}.${pin[2]}', current,
          reason: 'README has "${pin[0]}" but pubspec.yaml is ${pubspec['version']}');
    }
  });
}
