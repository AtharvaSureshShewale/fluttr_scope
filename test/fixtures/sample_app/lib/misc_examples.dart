import 'package:flutter/material.dart';

// TODO: replace this placeholder before shipping.
class ScaffoldMissingBodyExample extends StatelessWidget {
  const ScaffoldMissingBodyExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Misc')),
    );
  }
}

class ContainerConflictExample extends StatelessWidget {
  const ContainerConflictExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.red,
      decoration: const BoxDecoration(color: Colors.blue),
      child: const Text('conflict'),
    );
  }
}

class DeeplyNestedExample extends StatelessWidget {
  const DeeplyNestedExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Align(
          child: SizedBox(
            child: DecoratedBox(
              decoration: const BoxDecoration(),
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Text('deep'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
