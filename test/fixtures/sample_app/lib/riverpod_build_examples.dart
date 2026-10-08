import 'package:flutter/material.dart';

// Rules that check widget `build` methods, on Riverpod's two-parameter
// `build(BuildContext context, WidgetRef ref)`. `WidgetRef`/`ConsumerWidget`
// are local stand-ins: the fixture app doesn't depend on Riverpod.
// 'ok ...' must not be flagged, 'bad ...' must.

class WidgetRef {}

abstract class ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref);
}

Future<String> fetchTitle() async => 'title';

class ProfileScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = GlobalKey(debugLabel: 'bad key created in riverpod build');
    return FutureBuilder<String>(
      key: key,
      future: fetchTitle(), // 'bad future created in riverpod build'
      builder: (context, snapshot) => snapshot.hasError ? const Text('error') : Text(snapshot.data ?? ''),
    );
  }
}

class QueryBuilder {
  String build(String table, int limit) {
    final key = UniqueKey(); // 'ok unrelated build method, not a widget'
    return 'SELECT * FROM $table LIMIT $limit -- $key';
  }
}
