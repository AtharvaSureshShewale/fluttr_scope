import 'package:fluttr_scope/flow.dart';
import 'package:fluttr_scope/src/runtime/measurement_result.dart';
import 'package:test/test.dart';

void main() {
  test('waitForFluttrScope returns after its timeout when no fluttr_scope is attached', () async {
    final watch = Stopwatch()..start();
    await waitForFluttrScope(timeout: const Duration(milliseconds: 50));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('fluttrScopeDone is harmless with nobody listening', () {
    expect(fluttrScopeDone, returnsNormally);
  });

  test('a capture records whether its flow finished, and round-trips it through JSON', () {
    MeasurementResult capture({bool? flowCompleted}) => MeasurementResult(
          rebuilds: const [],
          heapUsage: const HeapUsage(beforeBytes: 1, afterBytes: 2),
          flowCompleted: flowCompleted,
        );
    for (final value in [true, false, null]) {
      final back = MeasurementResult.fromJson(capture(flowCompleted: value).toJson());
      expect(back.flowCompleted, value);
    }
    expect(capture().toJson().containsKey('flowCompleted'), isFalse);
  });
}
