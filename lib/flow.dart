/// Helpers for writing a *flow*: an `integration_test` file that
/// `fluttr_scope measure --flow` / `prioritize --flow` runs as the app, so
/// every measurement run uses the app the same way.
///
/// ```dart
/// import 'package:fluttr_scope/flow.dart';
///
/// void main() {
///   IntegrationTestWidgetsFlutterBinding.ensureInitialized();
///   testWidgets('checkout flow', (tester) async {
///     app.main();
///     await tester.pumpAndSettle();
///     await waitForFluttrScope(); // recording starts here
///     // ... taps, scrolls, text entry ...
///     fluttrScopeDone(); // recording stops here
///   });
/// }
/// ```
///
/// Only `dart:async` and `dart:developer` are used, so importing this from
/// app test code pulls in nothing else. Outside fluttr_scope (a plain
/// `flutter test` run) both calls are harmless: [waitForFluttrScope] gives
/// up after its timeout and the flow runs as a normal test.
library;

import 'dart:async';
import 'dart:developer' as developer;

/// The service extension fluttr_scope calls once it's recording.
const flowStartExtension = 'ext.fluttr_scope.start';

/// The event a flow posts when it's finished.
const flowDoneEvent = 'fluttr_scope.flowDone';

/// Waits until fluttr_scope has started recording, so no action in the flow
/// happens unmeasured. Call it after the app's first frame (e.g. after the
/// first `pumpAndSettle`) and before the first interaction.
///
/// Returns after [timeout] if no fluttr_scope is attached.
Future<void> waitForFluttrScope({Duration timeout = const Duration(seconds: 60)}) {
  final started = Completer<void>();
  developer.registerExtension(flowStartExtension, (method, params) async {
    if (!started.isCompleted) started.complete();
    return developer.ServiceExtensionResponse.result('{}');
  });
  return started.future.timeout(timeout, onTimeout: () {});
}

/// Tells fluttr_scope the flow is over, so it stops recording now rather
/// than at its time limit.
void fluttrScopeDone() => developer.postEvent(flowDoneEvent, <String, Object?>{});
