import 'package:flutter/material.dart';

class ExpandedOutsideFlexExample extends StatelessWidget {
  const ExpandedOutsideFlexExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Expanded(child: Text('bad')),
    );
  }
}

class ExpandedInsideRowExample extends StatelessWidget {
  const ExpandedInsideRowExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('ok')),
      ],
    );
  }
}

class PositionedOutsideStackExample extends StatelessWidget {
  const PositionedOutsideStackExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Positioned(top: 0, child: Text('bad')),
    );
  }
}
