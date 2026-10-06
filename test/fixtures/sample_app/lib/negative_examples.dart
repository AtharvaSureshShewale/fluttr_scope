import 'dart:async';

import 'package:flutter/material.dart';

/// Patterns that must NOT be flagged — false-positive regression coverage
/// for rules whose positive fixtures live elsewhere.
class NegativeExamples extends StatelessWidget {
  const NegativeExamples({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // unbounded_scrollable_in_flex: correctly wrapped in Expanded.
        Expanded(child: ListView(children: const [])),
        // container_color_and_decoration_conflict: only `color` set.
        Container(color: Colors.red),
        // opacity/aspect-ratio/flex: valid values.
        const Opacity(opacity: 0.5, child: Text('ok')),
        const AspectRatio(aspectRatio: 2, child: Text('ok')),
        Expanded(flex: 1, child: const Text('ok')),
        // insecure_http_url: https and localhost are both fine.
        const Text('https://example.com'),
        const Text('http://localhost:8080'),
      ],
    );
  }
}

class LeaksStreamSubscriptionExample extends StatefulWidget {
  const LeaksStreamSubscriptionExample({super.key});

  @override
  State<LeaksStreamSubscriptionExample> createState() =>
      _LeaksStreamSubscriptionExampleState();
}

class _LeaksStreamSubscriptionExampleState
    extends State<LeaksStreamSubscriptionExample> {
  StreamSubscription<int>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Stream<int>.empty().listen((_) {});
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class DisposesStreamSubscriptionExample extends StatefulWidget {
  const DisposesStreamSubscriptionExample({super.key});

  @override
  State<DisposesStreamSubscriptionExample> createState() =>
      _DisposesStreamSubscriptionExampleState();
}

class _DisposesStreamSubscriptionExampleState
    extends State<DisposesStreamSubscriptionExample> {
  StreamSubscription<int>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = Stream<int>.empty().listen((_) {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class KeyOutsideBuildExample extends StatefulWidget {
  const KeyOutsideBuildExample({super.key});

  @override
  State<KeyOutsideBuildExample> createState() => _KeyOutsideBuildExampleState();
}

class _KeyOutsideBuildExampleState extends State<KeyOutsideBuildExample> {
  late final GlobalKey _formKey;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey();
  }

  @override
  Widget build(BuildContext context) => SizedBox(key: _formKey);
}

class ListKeyPresentExample extends StatelessWidget {
  const ListKeyPresentExample({super.key});

  static const _items = ['a', 'b'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _items.map((item) => Text(item, key: ValueKey(item))).toList(),
    );
  }
}
