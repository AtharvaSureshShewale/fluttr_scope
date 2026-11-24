import 'package:args/args.dart';

/// The `--seconds` time limit used with `--flow` when none is given.
///
/// With a flow, recording stops as soon as the flow calls
/// `fluttrScopeDone()`, so this is only a safety limit for a flow that
/// hangs. It has to be generous: a run whose flow hits the limit is
/// discarded, and real flows (taps, scrolls, screens loading in debug mode)
/// often take longer than the 10-15s fixed-window defaults.
const defaultFlowTimeLimitSeconds = 300;

/// Adds the `--seconds` option. It has no parser default, so [captureSeconds]
/// can tell "not given" apart from "given" and pick a default by mode.
void addSecondsOption(ArgParser parser, {required int fixedDefault}) {
  parser.addOption(
    'seconds',
    help:
        'How long to capture each run for (default: ${fixedDefault}s). With '
        '--flow, the time limit for the flow instead (default: '
        '${defaultFlowTimeLimitSeconds}s); recording stops when the flow '
        'finishes, and a run whose flow takes longer is discarded.',
  );
}

/// The `--seconds` value: what the user gave, otherwise
/// [defaultFlowTimeLimitSeconds] with `--flow` or [fixedDefault] without.
int captureSeconds(ArgResults args, {required int fixedDefault}) {
  final given = args['seconds'] as String?;
  if (given != null) return int.parse(given);
  return args['flow'] != null ? defaultFlowTimeLimitSeconds : fixedDefault;
}
