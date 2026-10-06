import 'package:flutter/material.dart';

class ListBuilderExamples extends StatefulWidget {
  const ListBuilderExamples({super.key});

  @override
  State<ListBuilderExamples> createState() => _ListBuilderExamplesState();
}

class _ListBuilderExamplesState extends State<ListBuilderExamples> {
  int _selectedIndex = 0;
  bool _toggled = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // setState nested two closures deep inside itemBuilder (a tap
        // handler) -- the real-world shape: tapping one item rebuilds
        // every item in the list, not just the tapped one.
        ListView.builder(
          itemCount: 10,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedIndex = index;
                });
              },
              child: Text('$index / $_selectedIndex'),
            );
          },
        ),

        // A setState call outside any builder callback -- normal, expected,
        // and not what this rule is about.
        ElevatedButton(
          onPressed: () {
            setState(() {
              _toggled = !_toggled;
            });
          },
          child: Text(_toggled ? 'On' : 'Off'),
        ),
      ],
    );
  }
}
