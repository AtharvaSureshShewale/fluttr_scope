/// Identifier-name fragments that suggest a security-sensitive value (a
/// token, password, secret, or API key) — used by rules that flag a value
/// based on what it's *called*, not what it *is*, since Dart has no way
/// to know a String's semantic meaning at analysis time.
final sensitiveNamePattern = RegExp(
  r'(password|passwd|token|secret|api[_-]?key|auth|otp\b|pin\b)',
  caseSensitive: false,
);
