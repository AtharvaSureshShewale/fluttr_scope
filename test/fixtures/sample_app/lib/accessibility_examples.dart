import 'package:flutter/material.dart';

class AccessibilityExamples extends StatelessWidget {
  const AccessibilityExamples({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
        Image.network('https://example.com/photo.png'),
      ],
    );
  }
}
