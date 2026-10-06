/// The prefix every fluttr_scope rule id takes in an ignore comment, so it
/// can't collide with a Dart lint of the same name (both have an
/// `avoid_print`, for example).
const ignorePrefix = 'fluttr_scope/';

final _ignorePattern = RegExp(r'//\s*ignore:\s*(.*)$');
final _ignoreForFilePattern = RegExp(r'//\s*ignore_for_file:\s*(.*)$');

/// The `// ignore:` / `// ignore_for_file:` comments in one file, with the
/// same placement rules as the Dart analyzer's own: a comment on a line by
/// itself applies to the next line; a comment after code applies to its
/// own line.
class Suppressions {
  final Set<String> _fileWide;
  final Map<int, Set<String>> _byLine;

  Suppressions._(this._fileWide, this._byLine);

  /// Parses [source]. Only ids written as `fluttr_scope/<rule_id>` count;
  /// everything else in the comment (Dart's own lint names) is ignored.
  factory Suppressions.parse(String source) {
    final fileWide = <String>{};
    final byLine = <int, Set<String>>{};
    // Split on CRLF too: a trailing `\r` would stop the patterns' `.*$`
    // from matching, silently disabling every ignore in a Windows file.
    final lines = source.split(RegExp(r'\r?\n'));

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      final forFile = _ignoreForFilePattern.firstMatch(line);
      if (forFile != null) {
        fileWide.addAll(_ruleIds(forFile.group(1)!));
        continue;
      }

      final match = _ignorePattern.firstMatch(line);
      if (match == null) continue;
      final ids = _ruleIds(match.group(1)!);
      if (ids.isEmpty) continue;

      final standalone = line.trimLeft().startsWith('//');
      final targetLine = standalone ? i + 2 : i + 1; // 1-based
      (byLine[targetLine] ??= {}).addAll(ids);
    }

    return Suppressions._(fileWide, byLine);
  }

  /// Whether [ruleId] is suppressed at 1-based [line].
  bool isSuppressed(String ruleId, int line) =>
      _fileWide.contains(ruleId) || (_byLine[line]?.contains(ruleId) ?? false);
}

Iterable<String> _ruleIds(String commentBody) => commentBody
    .split(',')
    .map((s) => s.trim().split(RegExp(r'\s')).first)
    .where((s) => s.startsWith(ignorePrefix))
    .map((s) => s.substring(ignorePrefix.length));
