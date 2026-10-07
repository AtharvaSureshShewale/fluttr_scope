import 'package:flutter/material.dart' as m;

// scaffold_missing_body cases. A UI library's own `Scaffold` (shape taken
// from a real app built on one) must not be flagged; Flutter's must.

class Scaffold extends m.StatelessWidget {
  final List<m.Widget> headers;
  final m.Widget child;

  const Scaffold({super.key, this.headers = const [], required this.child});

  @override
  m.Widget build(m.BuildContext context) => child;
}

m.Widget scaffoldExamples() => m.Column(children: [
      Scaffold(headers: const [], child: m.Text('ok library scaffold')),
      m.Scaffold(appBar: m.AppBar(title: m.Text('bad material scaffold without body'))),
    ]);
