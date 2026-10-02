// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_util/cli_util.dart';
import 'package:dash_fuzz/dash_fuzz.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'dash_fuzz',
          'Coverage-guided libFuzzer + dart:ffi AST instrumentor and pure-Dart '
              'parser fuzzing tool.',
        )
        ..addCommand(_InstrumentCommand())
        ..addCommand(_RunCommand());

  try {
    final code = await runner.run(args);
    exitCode = code ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on ToolchainMissingException catch (e) {
    stderr.writeln(e);
    exitCode = 69;
  } on Object catch (e) {
    stderr.writeln('ERROR: $e');
    exitCode = 1;
  }
}

class _InstrumentCommand extends Command<int> {
  @override
  String get name => 'instrument';

  @override
  String get description =>
      'Instruments a file or a package lib/ directory into .dart_tool/dash_fuzz/.';

  _InstrumentCommand() {
    argParser
      ..addOption(
        'package-root',
        help: 'Path to the target package root directory.',
        defaultsTo: '.',
      )
      ..addOption(
        'input',
        help: 'Single .dart source file to instrument (optional).',
      )
      ..addOption(
        'output',
        help: 'Output file path when --input is specified.',
      );
  }

  @override
  Future<int> run() async {
    final opts = argResults!;
    final input = opts['input'] as String?;
    final output = opts['output'] as String?;

    if (input != null) {
      if (output == null) {
        usageException('--output is required when --input is provided.');
      }
      final source = File(input).readAsStringSync();
      final instrumentor = AstInstrumentor();
      final out = instrumentor.instrumentSource(source);
      File(output).writeAsStringSync(out);
      stdout.writeln(
        'Instrumented $input -> $output '
        '(edges: ${instrumentor.edgesInserted}, '
        'compares: ${instrumentor.comparesInserted}, '
        'switches: ${instrumentor.switchesInserted})',
      );
      return 0;
    }

    final pkgRoot = opts['package-root'] as String;
    final res = await PackageOverlayInstrumentor.instrumentPackage(
      packageRoot: pkgRoot,
    );
    stdout.writeln(
      'Instrumented package:${res.packageName} '
      '(${res.filesInstrumented} files -> ${res.instrumentedLibDir}; '
      'edges: ${res.edgesInserted}, compares: ${res.comparesInserted}, '
      'switches: ${res.switchesInserted})\n'
      'Overlay config: ${res.overlayPackageConfigPath}',
    );
    return 0;
  }
}

class _RunCommand extends Command<int> {
  @override
  String get name => 'run';

  @override
  String get description =>
      'Instruments the target package and runs a fuzz target harness.';

  _RunCommand() {
    argParser
      ..addOption(
        'target',
        help: 'Path to the Dart fuzz harness script.',
        mandatory: true,
      )
      ..addOption(
        'package-root',
        help: 'Target package directory whose lib/ will be instrumented.',
        defaultsTo: '.',
      )
      ..addOption(
        'mode',
        help: 'Fuzzing execution mode.',
        allowed: const ['cgf', 'pure-dart'],
        defaultsTo: 'cgf',
      )
      ..addOption(
        'runs',
        help: 'Maximum number of fuzzing iterations (-runs=<N>).',
        defaultsTo: '200000',
      )
      ..addOption(
        'max-len',
        help: 'Maximum input length in bytes (-max_len=<N>).',
        defaultsTo: '64',
      )
      ..addOption(
        'max-total-time',
        help: 'Maximum total fuzzing time in seconds (-max_total_time=<S>).',
        defaultsTo: '0',
      )
      ..addOption(
        'rss-limit-mb',
        help: 'Process RSS memory ceiling in MB (-rss_limit_mb=<MB>).',
        defaultsTo: '2048',
      )
      ..addOption(
        'heap-limit-mb',
        help: 'Dart VM old-generation heap ceiling in MB.',
        defaultsTo: '1024',
      )
      ..addOption(
        'timeout',
        help: 'Per-input timeout in seconds (-timeout=<S>).',
        defaultsTo: '5',
      );
  }

  @override
  Future<int> run() async {
    final opts = argResults!;
    final targetPath = p.normalize(p.absolute(opts['target'] as String));
    if (!File(targetPath).existsSync()) {
      usageException('Target script not found: $targetPath');
    }

    final pkgRoot = p.normalize(p.absolute(opts['package-root'] as String));
    final modeStr = opts['mode'] as String;
    final isPureDart = modeStr == 'pure-dart';

    final overlay = await PackageOverlayInstrumentor.instrumentPackage(
      packageRoot: pkgRoot,
    );
    stdout.writeln(
      'Prepared AST overlay for package:${overlay.packageName} '
      '(${overlay.filesInstrumented} files, ${overlay.edgesInserted} edges, '
      '${overlay.comparesInserted} compares, '
      '${overlay.switchesInserted} switches).',
    );

    String? libPath;
    if (!isPureDart) {
      final dashFuzzDir = p.join(pkgRoot, '.dart_tool', 'dash_fuzz');
      libPath = await NativeFuzzerBuilder.buildSharedLibrary(
        outputDir: dashFuzzDir,
      );
    }

    final heapLimitMb = opts['heap-limit-mb'] as String;
    final fuzzerFlags = <String>[
      '-use_value_profile=1',
      '-runs=${opts['runs']}',
      '-max_len=${opts['max-len']}',
      '-rss_limit_mb=${opts['rss-limit-mb']}',
      '-timeout=${opts['timeout']}',
      if ((opts['max-total-time'] as String) != '0')
        '-max_total_time=${opts['max-total-time']}',
      ...opts.rest,
    ];

    final dartBin =
        dartExecutable ??
        (throw StateError('Could not locate the `dart` executable.'));
    final proc = await Process.start(
      dartBin,
      [
        '--old_gen_heap_size=$heapLimitMb',
        '--packages=${overlay.overlayPackageConfigPath}',
        targetPath,
        ...fuzzerFlags,
      ],
      workingDirectory: pkgRoot,
      environment: {
        ...Platform.environment,
        'DASH_FUZZ_MODE': modeStr,
        'DASH_FUZZ_LIB_PATH': ?libPath,
      },
      mode: ProcessStartMode.inheritStdio,
    );
    return proc.exitCode;
  }
}
