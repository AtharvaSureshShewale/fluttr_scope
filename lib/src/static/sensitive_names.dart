/// Identifier-name fragments that suggest a security-sensitive value (a
/// token, password, secret, or API key) — used by rules that flag a value
/// based on what it's *called*, not what it *is*, since Dart has no way
/// to know a String's semantic meaning at analysis time.
///
/// No bare `auth`: on real code it matched `authError`, `authenticated`,
/// and `authUserName` far more often than an actual credential, which the
/// specific `auth...` forms below still catch.
final sensitiveNamePattern = RegExp(
  r'(password|passwd|token|secret|api[_-]?key|private[_-]?key|credential'
  r'|authorization|bearer|auth[_-]?code|otp\b|pin\b)',
  caseSensitive: false,
);
