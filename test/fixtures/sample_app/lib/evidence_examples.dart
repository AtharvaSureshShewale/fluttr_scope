import 'package:flutter/material.dart';

// Which widgets' rebuilds count as runtime evidence for a finding whose own
// location Flutter doesn't track (Finding.evidenceLocations). Shapes from
// Wonderous's WonderIllustrationBuilder.build and AppBtn.build.

class EvidenceExamples extends StatelessWidget {
  final bool flag;
  final Widget? child;

  const EvidenceExamples({super.key, required this.flag, this.child});

  @override
  Widget build(BuildContext context) {
    final key = GlobalKey(); // unconditional: any widget built here counts
    if (flag) return SizedBox.expand(); // only on this branch: nothing counts
    final Widget content = child ?? SizedBox.shrink(); // behind ??: nothing counts
    return Column(key: key, children: [content]);
  }
}
