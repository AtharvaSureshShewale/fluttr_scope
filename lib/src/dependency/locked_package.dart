/// A single package entry resolved in `pubspec.lock`.
class LockedPackage {
  final String name;
  final String version;

  /// `hosted`, `sdk`, `git`, or `path`. Only `hosted` packages (pub.dev)
  /// are queryable against OSV's Pub ecosystem.
  final String source;

  const LockedPackage({
    required this.name,
    required this.version,
    required this.source,
  });
}
