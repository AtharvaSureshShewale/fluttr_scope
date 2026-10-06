import 'dart:convert';
import 'dart:io';

/// One device from `flutter devices --machine`.
class FlutterDevice {
  final String id;
  final String name;
  final bool isSupported;

  const FlutterDevice({required this.id, required this.name, required this.isSupported});
}

/// Parses `flutter devices --machine` output. Tolerates non-JSON lines
/// before the array (flutter sometimes prints status text first).
List<FlutterDevice> parseFlutterDevices(String output) {
  final start = output.indexOf('[');
  if (start == -1) return const [];
  final decoded = jsonDecode(output.substring(start));
  if (decoded is! List) return const [];
  return [
    for (final d in decoded.cast<Map<String, Object?>>())
      FlutterDevice(
        id: d['id'] as String,
        name: d['name'] as String? ?? d['id'] as String,
        isSupported: d['isSupported'] as bool? ?? true,
      ),
  ];
}

/// Picks the device to measure on when `--device` wasn't given: the only
/// supported connected device. Throws a [StateError] explaining what to
/// pass when there are zero or several -- guessing between an emulator and
/// a desktop target would silently measure the wrong thing.
Future<String> detectDevice() async {
  final result = await Process.run('flutter', ['devices', '--machine'], runInShell: true);
  if (result.exitCode != 0) {
    throw StateError('`flutter devices` failed: ${result.stderr}');
  }
  return chooseDevice(parseFlutterDevices(result.stdout as String));
}

String chooseDevice(List<FlutterDevice> devices) {
  final supported = devices.where((d) => d.isSupported).toList();
  if (supported.length == 1) return supported.single.id;

  if (supported.isEmpty) {
    throw StateError('No connected device found. Start an emulator or connect a device, '
        'then pass --device=<id> (see `flutter devices`).');
  }
  final list = supported.map((d) => '  ${d.id}  (${d.name})').join('\n');
  throw StateError('Several devices are connected; pass --device=<id> to pick one:\n$list');
}
