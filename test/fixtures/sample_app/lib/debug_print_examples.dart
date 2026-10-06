import 'package:flutter/foundation.dart';

// Flutter's debugPrint is a top-level *variable* of function type, not a
// function, so a call to it resolves to a FunctionExpressionInvocation --
// not the MethodInvocation a plain print() call resolves to.
void debugPrintExamples(String authToken) {
  debugPrint('token: $authToken');
  debugPrint('screen opened');
}
