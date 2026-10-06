import 'package:flutter/material.dart';

// missing_list_key cases, the 'ok' shapes taken from real apps where the
// rule used to fire. 'ok ...' must not be flagged, 'bad ...' must.

class _Counter extends StatefulWidget {
  final String label;

  const _Counter(this.label);

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => Text(widget.label);
}

class ListKeyExamples extends StatelessWidget {
  final List<String> items;

  const ListKeyExamples({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(children: items.map((t) => Padding(padding: EdgeInsets.zero, child: Text('ok stateless padding $t'))).toList()),
        Wrap(children: items.map((t) => ActionChip(label: Text('ok action chip $t'), onPressed: () {})).toList()),
        Column(children: items.map((t) => Image.network(t, semanticLabel: 'ok framework image')).toList()),

        Column(children: items.map((t) => _Counter('bad app stateful widget $t')).toList()),
        Column(children: items.map((t) => Padding(padding: EdgeInsets.zero, child: TextField(decoration: InputDecoration(hintText: 'bad textfield inside padding')))).toList()),
        Column(children: items.map((t) => ExpansionTile(title: Text('bad expansion tile $t'))).toList()),
      ],
    );
  }
}
