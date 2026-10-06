import 'package:fluttr_scope/src/static/suppression.dart';
import 'package:test/test.dart';

void main() {
  test('a standalone ignore applies to the next line only', () {
    final s = Suppressions.parse('// ignore: fluttr_scope/avoid_print\nprint(1);\nprint(2);');
    expect(s.isSuppressed('avoid_print', 2), isTrue);
    expect(s.isSuppressed('avoid_print', 1), isFalse);
    expect(s.isSuppressed('avoid_print', 3), isFalse);
  });

  test('a trailing ignore applies to its own line', () {
    final s = Suppressions.parse('print(1); // ignore: fluttr_scope/avoid_print\nprint(2);');
    expect(s.isSuppressed('avoid_print', 1), isTrue);
    expect(s.isSuppressed('avoid_print', 2), isFalse);
  });

  test('ignore_for_file applies to every line', () {
    final s = Suppressions.parse('// ignore_for_file: fluttr_scope/todo_comment\n\n\n');
    expect(s.isSuppressed('todo_comment', 1), isTrue);
    expect(s.isSuppressed('todo_comment', 99), isTrue);
    expect(s.isSuppressed('avoid_print', 1), isFalse);
  });

  test('several ids in one comment, mixed with Dart lint names', () {
    final s = Suppressions.parse(
      'x(); // ignore: avoid_print, fluttr_scope/avoid_print, fluttr_scope/todo_comment',
    );
    expect(s.isSuppressed('avoid_print', 1), isTrue);
    expect(s.isSuppressed('todo_comment', 1), isTrue);
  });

  test('a bare rule id without the fluttr_scope/ prefix does not suppress', () {
    final s = Suppressions.parse('print(1); // ignore: avoid_print');
    expect(s.isSuppressed('avoid_print', 1), isFalse);
  });

  test('CRLF line endings', () {
    final s = Suppressions.parse('// ignore: fluttr_scope/avoid_print\r\nprint(1);\r\n');
    expect(s.isSuppressed('avoid_print', 2), isTrue);
  });
}
