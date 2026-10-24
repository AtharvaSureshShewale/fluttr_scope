import 'package:flutter/material.dart';

// Where a finding on a constructor call points, so it shares the key
// Flutter's widget-creation tracking reports rebuilds under.

class JoinKeyExamples extends StatelessWidget {
  const JoinKeyExamples({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Radio<int>.adaptive(value: 1, groupValue: 2, onChanged: null),
      ],
    );
  }
}
