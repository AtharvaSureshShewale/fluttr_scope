import 'package:flutter/material.dart';

// Shapes found in a real 267-file app that the hierarchy rules used to
// flag as errors even though they're valid Flutter -- every widget below
// labelled 'ok ...' must NOT be flagged -- next to genuine mistakes that
// must still be caught ('bad ...').

class HierarchyRealWorldExamples extends StatelessWidget {
  final List<String> items;
  final bool flag;

  const HierarchyRealWorldExamples({super.key, required this.items, required this.flag});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // .map(...) inside Row children
        Row(children: items.map((t) => Expanded(child: Text('ok map'))).toList()),
        // List.generate inside Row children
        Row(children: List.generate(3, (i) => Expanded(child: Text('ok generate')))),
        // collection if / spread / for
        Row(children: [
          if (flag) Expanded(child: Text('ok if')),
          if (flag) ...[const SizedBox(width: 8), Expanded(child: Text('ok spread'))],
          for (final _ in items) Flexible(child: Text('ok for')),
          flag ? Expanded(child: Text('ok ternary')) : const SizedBox(),
        ]),
        // a helper whose caller is out of sight
        Row(children: [_ohlColumn()]),
        // Positioned via if / map inside a Stack, and inside an IndexedStack
        Stack(children: [
          if (flag) Positioned(top: 0, child: Text('ok stack if')),
          ...items.map((t) => Positioned(left: 0, child: Text('ok stack map'))),
        ]),

        // Genuine mistakes -- these must still be flagged.
        Row(children: [
          Padding(padding: EdgeInsets.zero, child: Expanded(child: Text('bad padding'))),
        ]),
        ListView(shrinkWrap: true, children: [Expanded(child: Text('bad listview'))]),
        Stack(children: [if (flag) Expanded(child: Text('bad expanded in stack'))]),
        Row(children: [Positioned(top: 0, child: Text('bad positioned in row'))]),
        SizedBox(child: flag ? Positioned(top: 0, child: Text('bad sizedbox')) : null),
        // IndexedStack is not a Stack: it wraps each child in a Visibility
        // (a render object) before handing them to an internal Stack, so a
        // Positioned here throws "Incorrect use of ParentDataWidget".
        IndexedStack(children: [Positioned(top: 0, child: Text('bad indexed stack'))]),
      ],
    );
  }

  Widget _ohlColumn() {
    return Expanded(child: Text('ok helper'));
  }
}
