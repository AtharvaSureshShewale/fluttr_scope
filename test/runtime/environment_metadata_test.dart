import 'dart:io';

import 'package:fluttr_scope/src/runtime/environment_metadata.dart';
import 'package:test/test.dart';

void main() {
  group('detectEnvironment', () {
    test('a device id containing "emulator" is heuristically classified as an emulator', () {
      final env = detectEnvironment(device: 'emulator-5554');
      expect(env.looksLikeEmulator, isTrue);
    });

    test('a device id containing "simulator" is heuristically classified as an emulator', () {
      final env = detectEnvironment(device: 'iPhone 15 Simulator');
      expect(env.looksLikeEmulator, isTrue);
    });

    test('an unrelated device id is not classified as an emulator', () {
      final env = detectEnvironment(device: 'windows');
      expect(env.looksLikeEmulator, isFalse);
    });

    test('the raw device string is preserved verbatim', () {
      final env = detectEnvironment(device: 'emulator-5554');
      expect(env.device, 'emulator-5554');
    });

    test('hostPlatform describes the host machine running fluttr_scope, '
        'matching Platform.operatingSystem', () {
      final env = detectEnvironment(device: 'windows');
      expect(env.hostPlatform, contains(Platform.operatingSystem));
    });

    test('buildMode is always debug -- a hardcoded fact of RuntimeDriver, not detected', () {
      final env = detectEnvironment(device: 'emulator-5554');
      expect(env.buildMode, 'debug');
    });

    test('dartVmVersion passes through when supplied, and is null when not '
        '(never fabricated)', () {
      final withVersion = detectEnvironment(device: 'emulator-5554', dartVmVersion: '3.5.0');
      expect(withVersion.dartVmVersion, '3.5.0');

      final withoutVersion = detectEnvironment(device: 'emulator-5554');
      expect(withoutVersion.dartVmVersion, isNull);
    });

    test('round-trips through toJson without throwing, including a null dartVmVersion', () {
      final env = detectEnvironment(device: 'windows');
      final json = env.toJson();
      expect(json['device'], 'windows');
      expect(json['looksLikeEmulator'], isFalse);
      expect(json['buildMode'], 'debug');
      expect(json['dartVmVersion'], isNull);
    });
  });
}
