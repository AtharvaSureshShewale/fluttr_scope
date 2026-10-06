import 'package:flutter/material.dart';

// avoid_logging_sensitive_data cases, the 'ok' ones taken from a real app
// where the rule used to fire. 'ok ...' must not be flagged, 'bad ...' must.

void loggingExamples({
  required Object authErr,
  required bool authenticated,
  required String token,
  required String requestToken,
  required String storedHash,
  required TextEditingController passwordController,
  required String password,
}) {
  debugPrint('ok error object: $authErr');
  print('ok bool: $authenticated');
  print('ok length only: ${token.length}');
  print('ok hash: $storedHash');
  print('ok password field label');

  debugPrint('bad request token: $requestToken');
  print('bad controller text: ${passwordController.text}');
  print('bad concatenated: ' + password);
  print(token); // 'bad bare token'
}
