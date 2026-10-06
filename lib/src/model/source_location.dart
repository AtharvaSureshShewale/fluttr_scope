/// A location in a source file.
///
/// [file], [line], and [column] together form the join key the runtime
/// correlator (a later milestone) will use to match this location against
/// creation locations emitted by `--track-widget-creation`. [length] is
/// carried for display/range purposes only and deliberately excluded from
/// equality — the runtime side only ever supplies a single point, not a span.
class SourceLocation {
  final String file;
  final int line;
  final int column;
  final int length;

  const SourceLocation({
    required this.file,
    required this.line,
    required this.column,
    required this.length,
  });

  Map<String, Object?> toJson() => {
        'file': file,
        'line': line,
        'column': column,
        'length': length,
      };

  factory SourceLocation.fromJson(Map<String, Object?> json) => SourceLocation(
        file: json['file'] as String,
        line: json['line'] as int,
        column: json['column'] as int,
        length: json['length'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      other.file == file &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(file, line, column);

  @override
  String toString() => '$file:$line:$column';
}
