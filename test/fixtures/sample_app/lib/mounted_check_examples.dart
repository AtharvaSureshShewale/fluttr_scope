import 'package:flutter/material.dart';

// missing_mounted_check cases. Each setState stores a label: 'ok ...' must
// not be flagged, 'bad ...' must be.

class MountedCheckExamples extends StatefulWidget {
  const MountedCheckExamples({super.key});

  @override
  State<MountedCheckExamples> createState() => _MountedCheckExamplesState();
}

class _MountedCheckExamplesState extends State<MountedCheckExamples> {
  String _label = '';

  Future<void> _ifMountedBlock() async {
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      setState(() => _label = 'ok if mounted block');
    }
  }

  Future<void> _ifMountedAnd(bool ready) async {
    await Future<void>.delayed(Duration.zero);
    if (mounted && ready) setState(() => _label = 'ok mounted and');
  }

  Future<void> _contextMounted() async {
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    setState(() => _label = 'ok context.mounted return guard');
  }

  Future<void> _orReturnGuard(bool cancelled) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted || cancelled) return;
    setState(() => _label = 'ok or return guard');
  }

  Future<void> _nullCheckOnly() async {
    final picked = await Future<String?>.value('x');
    if (picked != null) {
      setState(() => _label = 'bad null check is not a mounted check');
    }
  }

  Future<void> _wrongWayGuard() async {
    await Future<void>.delayed(Duration.zero);
    if (mounted) return;
    setState(() => _label = 'bad returns only when mounted');
  }

  Future<void> _negatedIf() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      setState(() => _label = 'bad inside if not mounted');
    }
  }

  Future<void> _elseOfMounted() async {
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      _label = '';
    } else {
      setState(() => _label = 'bad else branch of mounted');
    }
  }

  Future<void> _guardNestedInTry() async {
    await Future<void>.delayed(Duration.zero);
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      setState(() => _label = 'ok guard nested in try');
    } finally {}
  }

  Future<void> _guardBeforeSecondAwait() async {
    try {
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      setState(() => _label = 'bad guard came before the await');
    } finally {}
  }

  Future<void> _awaitOnlyInExitingBranch(bool paused) async {
    if (paused) {
      await Future<void>.delayed(Duration.zero);
      return;
    }
    setState(() => _label = 'ok await only in a branch that returns');
  }

  Future<void> _awaitInNonExitingBranch(bool paused) async {
    if (paused) {
      await Future<void>.delayed(Duration.zero);
    }
    setState(() => _label = 'bad await in a branch that falls through');
  }

  Future<void> _setStateInCatch() async {
    try {
      await Future<void>.delayed(Duration.zero);
    } catch (_) {
      setState(() => _label = 'bad catch after awaiting try body');
    }
  }

  // A setState inside a callback runs when the callback fires, not right
  // after the await -- out of this rule's scope, so not flagged.
  Future<void> _setStateInCallback() async {
    await Future<void>.delayed(Duration.zero);
    Future<void>.delayed(Duration.zero, () => setState(() => _label = 'ok callback'));
  }

  @override
  Widget build(BuildContext context) => Text(_label);
}
