import 'package:flutter/material.dart';

class SimplificationExamples extends StatelessWidget {
  const SimplificationExamples({super.key});

  Widget _buildHelper() => const Text('helper');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(),
        Row(children: [_buildHelper()]),
        Column(children: const []),
      ],
    );
  }
}
