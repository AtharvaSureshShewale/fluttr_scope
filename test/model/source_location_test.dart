import 'package:fluttr_scope/src/model/source_location.dart';
import 'package:test/test.dart';

void main() {
  test('equality and hashCode ignore length — only file/line/column identify a location', () {
    const a = SourceLocation(file: 'lib/main.dart', line: 10, column: 5, length: 3);
    const b = SourceLocation(file: 'lib/main.dart', line: 10, column: 5, length: 99);
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('differs when file, line, or column differs', () {
    const base = SourceLocation(file: 'lib/main.dart', line: 10, column: 5, length: 3);
    expect(
      base,
      isNot(equals(const SourceLocation(file: 'lib/other.dart', line: 10, column: 5, length: 3))),
    );
    expect(
      base,
      isNot(equals(const SourceLocation(file: 'lib/main.dart', line: 11, column: 5, length: 3))),
    );
    expect(
      base,
      isNot(equals(const SourceLocation(file: 'lib/main.dart', line: 10, column: 6, length: 3))),
    );
  });

  test('toJson includes length even though equality ignores it', () {
    const loc = SourceLocation(file: 'lib/main.dart', line: 10, column: 5, length: 3);
    expect(loc.toJson(), {'file': 'lib/main.dart', 'line': 10, 'column': 5, 'length': 3});
  });

  test('toString is the file:line:column join key, without length', () {
    const loc = SourceLocation(file: 'lib/main.dart', line: 10, column: 5, length: 3);
    expect(loc.toString(), 'lib/main.dart:10:5');
  });
}
