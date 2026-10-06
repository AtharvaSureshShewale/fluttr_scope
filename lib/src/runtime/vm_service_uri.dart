final _uriPattern = RegExp(r'(https?://\S+)');

/// Extracts the VM Service HTTP URI `flutter run` prints at startup, e.g.
/// "A Dart VM Service on Windows is available at: http://127.0.0.1:PORT/TOKEN=/".
/// Returns `null` if [line] isn't that line.
Uri? parseVmServiceUri(String line) {
  if (!line.contains('Dart VM Service')) return null;
  final match = _uriPattern.firstMatch(line);
  if (match == null) return null;
  return Uri.tryParse(match.group(1)!);
}

/// Converts the HTTP VM Service URI `flutter run` prints into the WebSocket
/// URI `package:vm_service` needs to connect.
Uri toWebSocketUri(Uri httpUri) {
  final path = httpUri.path.endsWith('/') ? '${httpUri.path}ws' : '${httpUri.path}/ws';
  return httpUri.replace(scheme: 'ws', path: path);
}
