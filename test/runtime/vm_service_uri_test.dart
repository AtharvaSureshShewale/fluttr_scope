import 'package:fluttr_scope/src/runtime/vm_service_uri.dart';
import 'package:test/test.dart';

void main() {
  group('parseVmServiceUri', () {
    test('extracts the URI from the line flutter run prints', () {
      final uri = parseVmServiceUri(
        'A Dart VM Service on Windows is available at: '
        'http://127.0.0.1:56123/AbCdEfGhIjK=/',
      );
      expect(uri, isNotNull);
      expect(uri!.host, '127.0.0.1');
      expect(uri.port, 56123);
      expect(uri.path, '/AbCdEfGhIjK=/');
    });

    test('returns null for an unrelated line', () {
      expect(parseVmServiceUri('Launching lib/main.dart on Windows...'), isNull);
    });

    test('returns null for a line mentioning the VM Service without a URI', () {
      expect(parseVmServiceUri('The Dart VM Service is starting up.'), isNull);
    });
  });

  group('toWebSocketUri', () {
    test('converts http to ws and appends /ws to a trailing-slash path', () {
      final result = toWebSocketUri(Uri.parse('http://127.0.0.1:56123/AbCdEfGhIjK=/'));
      expect(result.toString(), 'ws://127.0.0.1:56123/AbCdEfGhIjK=/ws');
    });

    test('inserts a slash before ws when the path has no trailing slash', () {
      final result = toWebSocketUri(Uri.parse('http://127.0.0.1:56123/AbCdEfGhIjK='));
      expect(result.toString(), 'ws://127.0.0.1:56123/AbCdEfGhIjK=/ws');
    });
  });
}
