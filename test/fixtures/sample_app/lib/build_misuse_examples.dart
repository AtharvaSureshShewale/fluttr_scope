import 'package:flutter/material.dart';

class KeyInBuildExample extends StatelessWidget {
  const KeyInBuildExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(key: GlobalKey(), child: const Text('x'));
  }
}

class ThemeInInitStateExample extends StatefulWidget {
  const ThemeInInitStateExample({super.key});

  @override
  State<ThemeInInitStateExample> createState() =>
      _ThemeInInitStateExampleState();
}

class _ThemeInInitStateExampleState extends State<ThemeInInitStateExample> {
  ThemeData? _theme;

  @override
  void initState() {
    super.initState();
    _theme = Theme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    return Text(_theme?.toString() ?? '');
  }
}

class ContextStoredInFieldExample extends StatefulWidget {
  const ContextStoredInFieldExample({super.key});

  @override
  State<ContextStoredInFieldExample> createState() =>
      _ContextStoredInFieldExampleState();
}

class _ContextStoredInFieldExampleState
    extends State<ContextStoredInFieldExample> {
  BuildContext? _savedContext;

  @override
  Widget build(BuildContext context) {
    _savedContext = context;
    return const SizedBox.shrink();
  }
}
