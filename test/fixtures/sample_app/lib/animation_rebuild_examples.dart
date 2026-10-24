import 'package:flutter/material.dart';

// media_query_of_single_property, setstate_in_animation_listener and
// opacity_in_animation cases. 'ok ...' must not be flagged, 'bad ...' must
// be; each label sits on the line the finding points to.

class AnimationRebuildExamples extends StatefulWidget {
  const AnimationRebuildExamples({super.key});

  @override
  State<AnimationRebuildExamples> createState() => _AnimationRebuildExamplesState();
}

class _AnimationRebuildExamplesState extends State<AnimationRebuildExamples>
    with TickerProviderStateMixin {
  String _label = '';
  bool _half = false;
  late final AnimationController _controller = AnimationController(vsync: this);
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.ease);
  late final AnimationController _cascade = AnimationController(vsync: this)..addListener(() => setState(() => _label = 'bad cascade listener'));
  final ValueNotifier<double> _notifier = ValueNotifier(0);
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _label = 'bad closure listener'));
    _curve.addListener(_onTick); _label = 'bad method tear-off listener';
    _controller.addListener(() { if (mounted) setState(() {}); }); _label = 'bad if mounted listener';
    _controller.addListener(() { if (_controller.value > 0.5 && !_half) setState(() => _half = true); }); _label = 'ok threshold listener';
    _notifier.addListener(() => setState(() => _label = 'ok value notifier listener'));
    _scroll.addListener(() => setState(() => _label = 'ok scroll listener'));
    _controller.addStatusListener((status) => setState(() => _label = 'ok status listener'));
    _controller.addListener(_noSetState); _label = 'ok listener without setState';
  }

  void _onTick() => setState(() {});

  void _noSetState() => _half = _controller.value > 0.5;

  @override
  void dispose() {
    _controller.dispose();
    _cascade.dispose();
    _notifier.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return Column(
      children: [
        Text('bad size ${MediaQuery.of(context).size}'),
        Text('bad size width ${MediaQuery.of(context).size.width}'),
        Text('bad padding ${MediaQuery.of(context).padding.top}'),
        Text('bad view insets ${MediaQuery.of(context).viewInsets.bottom}'),
        Text('bad maybeOf ${MediaQuery.maybeOf(context)?.size}'),
        Text('ok sizeOf ${MediaQuery.sizeOf(context)}'),
        Text('ok whole data in a variable ${data.size} ${data.padding}'),
        Text('ok no lookup for this field ${MediaQuery.of(context).displayFeatures}'),
        Text('ok copyWith ${MediaQuery.of(context).copyWith()}'),

        Opacity(opacity: _controller.value, child: Text('bad controller value $_label')),
        Opacity(opacity: 1 - _curve.value, child: Text('bad one minus curve value')),
        Opacity(opacity: _controller.value.clamp(0.0, 1.0), child: Text('bad clamped value')),
        Opacity(opacity: 0.5, child: Text('ok constant opacity')),
        Opacity(opacity: _notifier.value, child: Text('ok value notifier opacity')),
        FadeTransition(opacity: _controller, child: Text('ok fade transition')),
        AnimatedOpacity(opacity: _half ? 1 : 0, duration: Durations.short2, child: Text('ok animated opacity')),
      ],
    );
  }
}
