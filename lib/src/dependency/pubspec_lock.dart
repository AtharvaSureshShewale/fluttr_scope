import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'locked_package.dart';

/// Parses `pubspec.lock` under [root]. Returns an empty list if the project
/// has no lockfile (e.g. `pub get` hasn't run).
List<LockedPackage> parsePubspecLock(String root) {
  final file = File(p.join(root, 'pubspec.lock'));
  if (!file.existsSync()) return const [];

  final doc = loadYaml(file.readAsStringSync());
  final packages = doc is YamlMap ? doc['packages'] : null;
  if (packages is! YamlMap) return const [];

  return [
    for (final entry in packages.entries)
      if (entry.value is YamlMap)
        LockedPackage(
          name: entry.key as String,
          version: (entry.value as YamlMap)['version'] as String,
          source: (entry.value as YamlMap)['source'] as String,
        ),
  ];
}
