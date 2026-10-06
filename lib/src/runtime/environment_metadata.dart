import 'dart:io';

import 'frame_budget.dart';

/// What's known about the environment a measurement ran in.
///
/// Deliberately narrow: only fields this tool can actually observe today.
/// [hostPlatform] describes the machine *running fluttr_scope's CLI*, not
/// the target device -- conflating the two would be a fabricated claim
/// about the device under test. Target-device OS/Flutter-SDK version
/// aren't captured (would need parsing `flutter devices --machine` or
/// launch stdout, not implemented) and are surfaced as `null` rather than
/// guessed.
class EnvironmentMetadata {
  /// The raw `--device` value passed to `flutter run` (e.g.
  /// `emulator-5554`, `windows`, `chrome`).
  final String device;

  /// Heuristic only: true when [device] matches a common emulator/
  /// simulator naming pattern. Not a certainty -- a physical device with
  /// an unusual id could be misclassified, and this is stated as a
  /// heuristic everywhere it's surfaced, never asserted as fact.
  final bool looksLikeEmulator;

  /// The host machine running fluttr_scope itself (`Platform.operatingSystem`
  /// / `Platform.operatingSystemVersion`) -- not the target device.
  final String hostPlatform;

  /// Always `'debug'` currently: `RuntimeDriver` only ever launches
  /// `flutter run` without `--profile`/`--release`. A hardcoded fact about
  /// this tool's current implementation, not a detected value.
  final String buildMode;

  /// The frame-budget assumption in use (see [defaultFrameBudget]) --
  /// assumed, not measured from the device's actual refresh rate.
  final Duration assumedFrameBudget;

  /// The target process's own Dart VM version string, read from
  /// `vmService.getVM().version` -- genuine data about the device under
  /// test, not the host. `null` if unavailable (e.g. an older captured
  /// JSON file that predates this field).
  final String? dartVmVersion;

  const EnvironmentMetadata({
    required this.device,
    required this.looksLikeEmulator,
    required this.hostPlatform,
    required this.buildMode,
    required this.assumedFrameBudget,
    required this.dartVmVersion,
  });

  Map<String, Object?> toJson() => {
        'device': device,
        'looksLikeEmulator': looksLikeEmulator,
        'hostPlatform': hostPlatform,
        'buildMode': buildMode,
        'assumedFrameBudgetMicros': assumedFrameBudget.inMicroseconds,
        'dartVmVersion': dartVmVersion,
      };
}

final _emulatorPattern = RegExp(r'emulator|simulator', caseSensitive: false);

/// Builds [EnvironmentMetadata] for a measurement against [device].
/// [dartVmVersion], if available, should come from the connected VM
/// Service (`(await service.getVM()).version`) -- pass `null` rather than
/// fabricating a value when it wasn't captured.
EnvironmentMetadata detectEnvironment({
  required String device,
  String? dartVmVersion,
  Duration assumedFrameBudget = defaultFrameBudget,
}) =>
    EnvironmentMetadata(
      device: device,
      looksLikeEmulator: _emulatorPattern.hasMatch(device),
      hostPlatform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      buildMode: 'debug',
      assumedFrameBudget: assumedFrameBudget,
      dartVmVersion: dartVmVersion,
    );
