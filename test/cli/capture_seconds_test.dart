import 'package:args/args.dart';
import 'package:fluttr_scope/src/cli/capture_seconds.dart';
import 'package:test/test.dart';

void main() {
  ArgResults parse(List<String> args) {
    final parser = ArgParser()..addOption('flow');
    addSecondsOption(parser, fixedDefault: 15);
    return parser.parse(args);
  }

  int seconds(List<String> args) =>
      captureSeconds(parse(args), fixedDefault: 15);

  test('without --flow, defaults to the fixed window', () {
    expect(seconds([]), 15);
  });

  test('with --flow, defaults to the generous flow time limit', () {
    // A real flow often takes longer than 15s; with the old default every
    // run of it was discarded as unfinished.
    expect(
      seconds(['--flow', 'integration_test/f_test.dart']),
      defaultFlowTimeLimitSeconds,
    );
    expect(defaultFlowTimeLimitSeconds, greaterThanOrEqualTo(120));
  });

  test('an explicit --seconds always wins', () {
    expect(seconds(['--seconds', '7']), 7);
    expect(
      seconds(['--seconds', '45', '--flow', 'integration_test/f_test.dart']),
      45,
    );
  });
}
