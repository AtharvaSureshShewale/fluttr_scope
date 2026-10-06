import 'package:fluttr_scope/src/coverage/lcov_parser.dart';
import 'package:test/test.dart';

const _sample = '''
TN:
SF:lib/main.dart
DA:1,1
DA:2,0
DA:3,1
LF:3
LH:2
end_of_record
SF:lib/util.dart
DA:1,0
LF:1
LH:0
end_of_record
''';

void main() {
  test('parses per-file line counts and uncovered lines', () {
    final files = parseLcov(_sample);

    expect(files, hasLength(2));

    expect(files[0].file, 'lib/main.dart');
    expect(files[0].linesFound, 3);
    expect(files[0].linesHit, 2);
    expect(files[0].uncoveredLines, [2]);
    expect(files[0].percentage, closeTo(66.7, 0.1));

    expect(files[1].file, 'lib/util.dart');
    expect(files[1].uncoveredLines, [1]);
    expect(files[1].percentage, 0.0);
  });

  test('a record with no lines instrumented is fully "covered" by convention', () {
    final files = parseLcov('SF:lib/empty.dart\nLF:0\nLH:0\nend_of_record\n');
    expect(files.single.percentage, 100.0);
  });

  test('drops a record missing its end_of_record terminator', () {
    final files = parseLcov('SF:lib/broken.dart\nDA:1,1\n');
    expect(files, isEmpty);
  });
}
