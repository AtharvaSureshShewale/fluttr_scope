import 'package:flutter/material.dart';

class AsyncWidgetExamples extends StatelessWidget {
  const AsyncWidgetExamples({super.key});

  Future<String> _fetchData() async => 'data';
  Stream<int> _tickStream() async* {
    yield 1;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<String>(
          future: _fetchData(),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? '');
          },
        ),
        StreamBuilder<int>(
          stream: _tickStream(),
          builder: (context, snapshot) {
            return Text('${snapshot.data}');
          },
        ),
      ],
    );
  }
}
