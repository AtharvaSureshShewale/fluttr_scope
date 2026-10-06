import 'package:flutter/material.dart';

class ShrinkWrapExample extends StatelessWidget {
  const ShrinkWrapExample({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: const [],
    );
  }
}

class UnboundedScrollableExample extends StatelessWidget {
  const UnboundedScrollableExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListView(children: const []),
      ],
    );
  }
}

class NestedScaffoldExample extends StatelessWidget {
  const NestedScaffoldExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Scaffold(
        body: Text('nested'),
      ),
    );
  }
}

class HardcodedSecretExample extends StatelessWidget {
  const HardcodedSecretExample({super.key});

  static const apiKey = 'AIzaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

  @override
  Widget build(BuildContext context) {
    return Text(apiKey);
  }
}
