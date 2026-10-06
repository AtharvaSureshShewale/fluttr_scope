import 'package:flutter/material.dart';

// widget_returning_method cases, the 'ok' shapes taken from a real app.
// 'ok ...' must not be flagged, 'bad ...' must -- on the method's name
// line, not its doc comment.

class LogoHelper {
  /// Builds a brand logo icon widget.
  static Widget buildLogo() => const Text('ok static helper on a utility class');

  Widget instanceOnUtility() => const Text('ok utility class instance method');
}

class WidgetMethodExamples extends StatefulWidget {
  const WidgetMethodExamples({super.key});

  static Widget placeholder() => const Text('ok static factory on a widget');

  @override
  State<WidgetMethodExamples> createState() => _WidgetMethodExamplesState();
}

class _WidgetMethodExamplesState extends State<WidgetMethodExamples> {
  /// Builds the header row.
  Widget _buildHeader() => const Text('bad documented helper on a State');

  Widget get _footer => const Text('bad getter on a State');

  @override
  Widget build(BuildContext context) => Column(children: [_buildHeader(), _footer]);
}
