import 'package:flutter/material.dart';

// unbounded_scrollable_in_flex cases, checked against the framework's own
// viewport assertions (debugCheckHasBoundedAxis and
// RenderShrinkWrappingViewport._debugCheckHasBoundedCrossAxis):
//   - a non-shrink-wrapping viewport needs BOTH axes bounded, so inside a
//     Column/Row it throws whichever way it scrolls;
//   - a shrink-wrapping one only needs its CROSS axis bounded, so it
//     throws only when it scrolls across the flex's direction;
//   - SingleChildScrollView sizes itself to its child and never throws.
// 'ok ...' must not be flagged, 'bad ...' must be.

class ScrollableRealWorldExamples extends StatelessWidget {
  final bool flag;

  const ScrollableRealWorldExamples({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text('ok scv horizontal')),
        SingleChildScrollView(child: Text('ok scv vertical')),
        ListView(shrinkWrap: true, children: [Text('ok shrinkwrap vertical')]),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, children: [Text('ok grid shrinkwrap')]),
        Expanded(child: ListView(children: [Text('ok expanded')])),
        SizedBox(height: 50, child: ListView(scrollDirection: Axis.horizontal, children: [Text('ok sized')])),
        ListView(shrinkWrap: flag, children: [Text('ok unknown shrinkwrap')]),
        Row(children: [
          Expanded(child: ListView(shrinkWrap: true, scrollDirection: Axis.horizontal, children: [Text('ok in expanded in row')])),
        ]),

        ListView.builder(itemCount: 1, itemBuilder: (c, i) => Text('bad builder')),
        ListView(scrollDirection: Axis.horizontal, children: [Text('bad horizontal in column')]),
        ListView(shrinkWrap: true, scrollDirection: Axis.horizontal, children: [Text('bad shrinkwrap across column')]),
        PageView(children: [Text('bad pageview')]),
        if (flag) CustomScrollView(slivers: [SliverToBoxAdapter(child: Text('bad custom in if'))]),
        Row(children: [ListView(children: [Text('bad listview in row')])]),
      ],
    );
  }
}
