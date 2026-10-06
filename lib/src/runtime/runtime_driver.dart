import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'executed_lines.dart';
import 'frame_metrics.dart';
import 'frame_rebuild_accumulator.dart';
import 'measurement_result.dart';
import 'rebuild_stats_accumulator.dart';
import 'vm_service_uri.dart';

const _trackRebuildsExtension = 'ext.flutter.inspector.trackRebuildDirtyWidgets';

/// Launches a Flutter app in debug mode, measures widget rebuild counts by
/// creation location, per-frame build/raster timing, and retained-heap
/// growth over a fixed window, then shuts it down.
///
/// Debug mode specifically — not profile — because the mechanism the
/// rebuild count relies on (`WidgetInspectorService`'s rebuild tracking)
/// fires from inside an `assert()` in the framework's `Element.rebuild()`,
/// which is compiled out entirely in profile and release builds. Verified
/// by reading the framework source directly, not assumed. Frame timing
/// (`Flutter.Frame` events, posted by `SchedulerBinding` whenever
/// `!kReleaseMode`) would actually work in profile mode too, but debug is
/// kept as the one mode for both, since rebuild tracking is the harder
/// constraint.
class RuntimeDriver {
  Future<MeasurementResult> measure(
    String targetPath, {
    Duration duration = const Duration(seconds: 10),
    String device = 'windows',
    Duration launchTimeout = const Duration(minutes: 5),
    void Function(String line)? onLaunchOutput,
  }) async {
    final launchedAt = DateTime.now();
    final root = p.normalize(p.absolute(targetPath));
    final process = await Process.start(
      'flutter',
      ['run', '-d', device, '--no-devtools'],
      workingDirectory: root,
      runInShell: true,
    );

    final vmServiceUri = Completer<Uri>();
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      onLaunchOutput?.call(line);
      if (!vmServiceUri.isCompleted) {
        final uri = parseVmServiceUri(line);
        if (uri != null) vmServiceUri.complete(uri);
      }
    });
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLaunchOutput);

    try {
      final httpUri = await vmServiceUri.future.timeout(
        launchTimeout,
        onTimeout: () => throw StateError(
          'flutter run never printed a VM Service URI within '
          '${launchTimeout.inSeconds}s. A first build (Gradle/CMake '
          'fetching dependencies) can be slow — rerunning is often faster '
          'once the build cache is warm.',
        ),
      );

      final service = await vmServiceConnectUri(toWebSocketUri(httpUri).toString());
      try {
        return await _measure(service, root, duration, launchedAt);
      } finally {
        await service.dispose();
      }
    } finally {
      await stdoutSub.cancel();
      await stderrSub.cancel();
      await _quit(process);
    }
  }

  Future<MeasurementResult> _measure(
    VmService service,
    String root,
    Duration duration,
    DateTime launchedAt,
  ) async {
    final vm = await service.getVM();
    final isolateId = vm.isolates!.first.id!;

    // The isolate registers its service extensions asynchronously during
    // startup (WidgetsFlutterBinding.initServiceExtensions()). Calling
    // trackRebuildDirtyWidgets before that finishes throws "Unknown
    // method" — a real race that a fast/warm build reliably hits (a cold
    // build happens to be slow enough elsewhere to mask it).
    await _waitForExtension(service, isolateId, _trackRebuildsExtension);

    // `gc: true` forces a collection first, so this reads retained heap —
    // garbage not yet swept wouldn't tell us anything about growth.
    final beforeBytes = await _heapUsageBytes(service, isolateId);

    final accumulator = RebuildStatsAccumulator(root: root);
    final frameRebuildAccumulator = FrameRebuildAccumulator(root: root);
    final frames = <FrameMetrics>[];
    await service.streamListen(EventStreams.kExtension);
    final eventSub = service.onExtensionEvent.listen((event) {
      switch (event.extensionKind) {
        case 'Flutter.RebuiltWidgets':
          accumulator.addEvent(event.extensionData!.data);
          frameRebuildAccumulator.addEvent(event.extensionData!.data);
        case 'Flutter.Frame':
          frames.add(FrameMetrics.fromExtensionData(event.extensionData!.data));
      }
    });

    try {
      await service.callServiceExtension(
        _trackRebuildsExtension,
        isolateId: isolateId,
        args: {'enabled': 'true'},
      );

      await Future<void>.delayed(duration);

      await service.callServiceExtension(
        _trackRebuildsExtension,
        isolateId: isolateId,
        args: {'enabled': 'false'},
      );
    } finally {
      await eventSub.cancel();
    }

    final afterBytes = await _heapUsageBytes(service, isolateId);

    // Collected last: forceCompile compiles every app function, which
    // would otherwise land inside the measured window as jank.
    final packageName = readPackageName(root);
    final executedLines = packageName == null
        ? null
        : await collectExecutedLines(service, isolateId, packageName: packageName);

    return MeasurementResult(
      rebuilds: accumulator.records,
      heapUsage: HeapUsage(beforeBytes: beforeBytes, afterBytes: afterBytes),
      frames: frames,
      launchedAt: launchedAt,
      dartVmVersion: vm.version,
      perFrameRebuilds: frameRebuildAccumulator.records,
      executedLines: executedLines,
    );
  }

  Future<int> _heapUsageBytes(VmService service, String isolateId) async {
    final profile = await service.getAllocationProfile(isolateId, gc: true);
    return profile.memoryUsage?.heapUsage ?? 0;
  }

  Future<void> _waitForExtension(
    VmService service,
    String isolateId,
    String extensionName,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      final isolate = await service.getIsolate(isolateId);
      if (isolate.extensionRPCs?.contains(extensionName) ?? false) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Isolate never registered $extensionName within 15s — is the app '
      'running in debug mode with widget creation tracking enabled '
      '(the default)?',
    );
  }

  Future<void> _quit(Process process) async {
    // `flutter run`, spawned with runInShell (cmd.exe on Windows), owns a
    // process tree — Process.kill() only signals the immediate cmd.exe
    // child, leaving dart/gradle/java grandchildren running. taskkill's
    // /T kills the whole tree; Process.kill() is the fallback elsewhere.
    Future<void> killTree() async {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
      } else {
        process.kill();
      }
    }

    process.stdin.writeln('q');
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () async {
        await killTree();
        return -1;
      },
    );
  }
}
