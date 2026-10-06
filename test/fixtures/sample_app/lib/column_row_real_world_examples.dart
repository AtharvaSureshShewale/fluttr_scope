import 'package:flutter/material.dart';

// unnecessary_column_or_row cases, the 'ok' shapes taken from a real app.
// 'ok ...' must not be flagged, 'bad ...' must.

class ColumnRowExamples extends StatelessWidget {
  final bool flag;

  const ColumnRowExamples({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('ok right-aligned bubble')]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ok cross alignment')]),
        Column(mainAxisSize: MainAxisSize.min, children: [Text('ok min size')]),
        Row(children: [Expanded(child: Text('ok expanded bounds the text'))]),
        Row(children: [Flexible(child: Text('ok flexible bounds the text'))]),
        Row(children: [if (flag) Text('ok collection if')]),

        Row(children: [Text('bad plain single child')]),
        Column(key: const ValueKey('k'), children: [Text('bad plain single child with key')]),
      ],
    );
  }
}
