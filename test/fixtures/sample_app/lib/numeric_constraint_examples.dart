import 'package:flutter/material.dart';

class NumericConstraintExamples extends StatelessWidget {
  const NumericConstraintExamples({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Opacity(opacity: 1.5, child: const Text('a')),
        const AspectRatio(aspectRatio: -1, child: Text('b')),
        Expanded(flex: 0, child: const Text('c')),
        Slider(value: 0, min: 10, max: 5, onChanged: null),
        BottomNavigationBar(items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        ]),
      ],
    );
  }
}
