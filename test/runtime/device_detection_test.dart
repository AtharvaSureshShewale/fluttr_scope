import 'package:fluttr_scope/src/runtime/device_detection.dart';
import 'package:test/test.dart';

void main() {
  const output = '''
Some status text flutter printed first
[
  {"name": "sdk gphone64 x86 64", "id": "emulator-5554", "isSupported": true, "emulator": true},
  {"name": "Windows", "id": "windows", "isSupported": false}
]
''';

  test('parses `flutter devices --machine`, skipping leading non-JSON text', () {
    final devices = parseFlutterDevices(output);
    expect(devices.map((d) => d.id), ['emulator-5554', 'windows']);
    expect(devices.last.isSupported, isFalse);
  });

  test('picks the only supported device', () {
    expect(chooseDevice(parseFlutterDevices(output)), 'emulator-5554');
  });

  test('refuses to guess between several supported devices', () {
    expect(
      () => chooseDevice(const [
        FlutterDevice(id: 'a', name: 'A', isSupported: true),
        FlutterDevice(id: 'b', name: 'B', isSupported: true),
      ]),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('--device'))),
    );
  });

  test('explains what to do when nothing is connected', () {
    expect(() => chooseDevice(const []), throwsStateError);
  });
}
