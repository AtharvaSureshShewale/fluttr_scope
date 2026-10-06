import 'package:flutter/material.dart';

class BuildSetStateWidget extends StatefulWidget {
  const BuildSetStateWidget({super.key});

  @override
  State<BuildSetStateWidget> createState() => _BuildSetStateWidgetState();
}

class _BuildSetStateWidgetState extends State<BuildSetStateWidget> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    setState(() => _count++);
    return Text('$_count');
  }
}

class AsyncLoadWidget extends StatefulWidget {
  const AsyncLoadWidget({super.key});

  @override
  State<AsyncLoadWidget> createState() => _AsyncLoadWidgetState();
}

class _AsyncLoadWidgetState extends State<AsyncLoadWidget> {
  String _data = '';

  Future<void> _loadUnguarded() async {
    final result = await Future.value('loaded');
    setState(() => _data = result);
  }

  Future<void> _loadGuarded() async {
    final result = await Future.value('loaded');
    if (!mounted) return;
    setState(() => _data = result);
  }

  @override
  void initState() {
    super.initState();
    _loadUnguarded();
    _loadGuarded();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_data);
  }
}
