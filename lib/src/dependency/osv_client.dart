import 'dart:convert';

import 'package:http/http.dart' as http;

import 'locked_package.dart';

class OsvVulnerability {
  final String id;
  final String summary;

  const OsvVulnerability({required this.id, required this.summary});
}

class OsvQueryException implements Exception {
  final String message;

  const OsvQueryException(this.message);

  @override
  String toString() => 'OsvQueryException: $message';
}

/// Thin client for OSV.dev's vulnerability database — no API key required.
class OsvClient {
  static final _batchUri = Uri.parse('https://api.osv.dev/v1/querybatch');
  static Uri _vulnUri(String id) => Uri.parse('https://api.osv.dev/v1/vulns/$id');

  final http.Client _client;

  OsvClient([http.Client? client]) : _client = client ?? http.Client();

  /// Vulnerability IDs found for each hosted package, keyed by package name.
  /// Packages that aren't `hosted` (sdk/git/path) are skipped — OSV's Pub
  /// ecosystem only covers pub.dev-published packages.
  Future<Map<String, List<String>>> queryBatch(
    List<LockedPackage> packages,
  ) async {
    final hosted = packages.where((pkg) => pkg.source == 'hosted').toList();
    if (hosted.isEmpty) return const {};

    final response = await _client.post(
      _batchUri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'queries': [
          for (final pkg in hosted)
            {
              'package': {'name': pkg.name, 'ecosystem': 'Pub'},
              'version': pkg.version,
            },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw OsvQueryException(
        'querybatch returned ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;
    final results = body['results'] as List? ?? const [];

    final vulnIds = <String, List<String>>{};
    for (var i = 0; i < hosted.length && i < results.length; i++) {
      final result = results[i] as Map<String, Object?>?;
      final vulns = result?['vulns'] as List? ?? const [];
      if (vulns.isEmpty) continue;
      vulnIds[hosted[i].name] = [
        for (final v in vulns) (v as Map<String, Object?>)['id'] as String,
      ];
    }
    return vulnIds;
  }

  Future<OsvVulnerability> getVulnerability(String id) async {
    final response = await _client.get(_vulnUri(id));
    if (response.statusCode != 200) {
      throw OsvQueryException(
        'vulns/$id returned ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;
    return OsvVulnerability(
      id: id,
      summary: (body['summary'] as String?) ??
          (body['details'] as String?) ??
          'No summary available.',
    );
  }

  void close() => _client.close();
}
