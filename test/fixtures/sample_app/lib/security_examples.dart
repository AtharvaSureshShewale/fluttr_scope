import 'dart:math';

import 'package:flutter/material.dart';

// Stand-ins for webview_flutter's API shape — the fixture app doesn't
// depend on that package, and unrestricted_webview_javascript's check is
// purely syntactic (a `javaScriptMode:` argument ending in `.unrestricted`),
// so a local type with the same shape exercises it without the real
// dependency.
class JavaScriptMode {
  const JavaScriptMode._();
  static const unrestricted = JavaScriptMode._();
}

class WebViewSettings {
  final JavaScriptMode javaScriptMode;
  const WebViewSettings({required this.javaScriptMode});
}

class SecurityExamples extends StatelessWidget {
  const SecurityExamples({super.key});

  static const insecureUrl = 'http://api.example.com/data';
  static const sensitiveUrlParam =
      'https://api.example.com/login?token=abc123';
  static const serverIp = '203.0.113.42';
  static const settings = WebViewSettings(
    javaScriptMode: JavaScriptMode.unrestricted,
  );

  @override
  Widget build(BuildContext context) {
    final tokenRandom = Random();
    return Column(
      children: [
        Text(insecureUrl),
        Text(sensitiveUrlParam),
        Text(serverIp),
        Text('${tokenRandom.nextInt(100)}'),
        TextField(
          decoration: const InputDecoration(labelText: 'Password'),
        ),
      ],
    );
  }

  /// A password field whose visibility is toggled by a variable (the
  /// standard show/hide-password pattern) — not missing and not
  /// literally `false` — should not be flagged.
  Widget passwordFieldWithToggle(bool obscurePassword) {
    return TextField(
      decoration: const InputDecoration(labelText: 'Password'),
      obscureText: obscurePassword,
    );
  }

  /// Redacting a token from an error string before logging it. The
  /// literal `token=` inside this regex *pattern* is not itself a URL
  /// carrying a token, so `sensitive_query_param` should not flag it.
  String redactToken(String input) {
    return input.replaceAll(RegExp(r'[?&]token=[^&\s]+'), '?token=***');
  }
}
