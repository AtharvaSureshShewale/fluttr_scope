import 'package:flutter/material.dart';

class MissingListKeyExample extends StatelessWidget {
  const MissingListKeyExample({super.key});

  static const _items = ['a', 'b', 'c'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _items.map((item) => TextField(decoration: InputDecoration(hintText: item))).toList(),
    );
  }
}
