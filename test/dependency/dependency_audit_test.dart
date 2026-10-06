import 'dart:convert';

import 'package:fluttr_scope/src/dependency/dependency_audit.dart';
import 'package:fluttr_scope/src/dependency/osv_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _fixtureRoot = 'test/fixtures/dependency_audit';

void main() {
  test(
      'flags a hosted package with a known OSV vulnerability at its '
      'locked version', () async {
    final mockClient = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/v1/querybatch') {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final queries = body['queries'] as List;
        // Only the two `source: hosted` packages — `flutter` (sdk) is
        // excluded, and it must preserve pubspec.lock's declaration order
        // so the mocked results below line up by index.
        expect(queries, hasLength(2));
        expect((queries[0] as Map)['package'], {'name': 'vulnerable_pkg', 'ecosystem': 'Pub'});
        expect((queries[1] as Map)['package'], {'name': 'safe_pkg', 'ecosystem': 'Pub'});

        return http.Response(
          jsonEncode({
            'results': [
              {
                'vulns': [
                  {'id': 'GHSA-test-0001'},
                ],
              },
              <String, Object?>{},
            ],
          }),
          200,
        );
      }

      if (request.method == 'GET' &&
          request.url.path == '/v1/vulns/GHSA-test-0001') {
        return http.Response(
          jsonEncode({
            'id': 'GHSA-test-0001',
            'summary': 'Arbitrary file write via a crafted archive.',
          }),
          200,
        );
      }

      return http.Response('unexpected request: ${request.url}', 404);
    });

    final findings = await auditDependencies(
      _fixtureRoot,
      client: OsvClient(mockClient),
    );

    expect(findings, hasLength(1));
    final finding = findings.single;
    expect(finding.ruleId, 'dependency_vulnerability');
    expect(finding.location.file, 'pubspec.lock');
    expect(finding.location.line, 5); // the "  vulnerable_pkg:" line
    expect(finding.message, contains('vulnerable_pkg'));
    expect(finding.message, contains('GHSA-test-0001'));
  });

  test('returns no findings when there is no pubspec.lock', () async {
    final findings = await auditDependencies(
      'test/fixtures/does_not_exist',
      client: OsvClient(MockClient((_) async => http.Response('', 500))),
    );
    expect(findings, isEmpty);
  });
}
