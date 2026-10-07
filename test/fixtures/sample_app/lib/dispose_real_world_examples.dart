import 'package:flutter/material.dart';

// dispose_missing cases, shapes taken from a real showcase app. Field
// declarations are labelled: 'ok ...' must not be flagged, 'bad ...' must.

class DisposeExamples extends StatefulWidget {
  final FocusNode? focusNode;

  const DisposeExamples({super.key, this.focusNode});

  @override
  State<DisposeExamples> createState() => _DisposeExamplesState();
}

class _DisposeExamplesState extends State<DisposeExamples> with SingleTickerProviderStateMixin {
  late ScrollController _handedIn; // 'ok handed in by a builder, not owned here'
  AnimationController? _neverCreated; // 'ok never assigned, nothing to dispose'
  final ScrollController _inline = ScrollController(); // 'bad created inline, never disposed'
  late final PageController _inInitState; // 'bad created in initState, dispose() forgets it'
  late final FocusNode _focusNode; // 'bad may hold its own node, never disposed'
  late final TextEditingController _disposed; // 'ok created and disposed'

  @override
  void initState() {
    super.initState();
    _inInitState = PageController(viewportFraction: 1);
    _focusNode = widget.focusNode ?? FocusNode();
    _disposed = TextEditingController();
  }

  @override
  void dispose() {
    _disposed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _neverCreated?.forward(from: 0);
    return Builder(builder: (context) {
      _handedIn = PrimaryScrollController.of(context);
      return ListView(controller: _inline, children: [Focus(focusNode: _focusNode, child: const SizedBox())]);
    });
  }
}
