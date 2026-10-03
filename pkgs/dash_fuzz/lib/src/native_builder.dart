// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Thrown when `--mode=cgf` is requested but `clang++` or LLVM `compiler-rt`
/// (`libclang_rt.fuzzer_no_main`) is unavailable on the host machine.
class ToolchainMissingException implements Exception {
  final String details;

  const ToolchainMissingException(this.details);

  @override
  String toString() =>
      'ERROR: Coverage-guided fuzzing (--mode=cgf) requires clang++ with '
      'LLVM libFuzzer (compiler-rt).\n'
      'Details: $details\n\n'
      'Install clang/LLVM:\n'
      '  • Ubuntu/Debian: sudo apt-get install -y clang llvm\n'
      '  • macOS (Homebrew): brew install llvm && '
      'export PATH="\$(brew --prefix llvm)/bin:\$PATH"\n\n'
      'Or explicitly re-run using the pure-Dart engine without clang++:\n'
      '  dart run dash_fuzz run --mode=pure-dart <target.dart>';
}

/// Locates `clang++` and compiles `fuzzer.cc` into a shared library linked
/// against LLVM's `libclang_rt.fuzzer_no_main`.
class NativeFuzzerBuilder {
  static const List<String> _clangCandidates = [
    'clang++',
    'clang++-20',
    'clang++-19',
    'clang++-18',
    'clang++-17',
    'clang++-16',
    'clang++-15',
  ];

  static const List<String> _fuzzerArchiveCandidates = [
    'libclang_rt.fuzzer_no_main-x86_64.a',
    'libclang_rt.fuzzer_no_main-aarch64.a',
    'libclang_rt.fuzzer_no_main.a',
    'libclang_rt.fuzzer_no_main_osx.a',
  ];

  /// Resolves the `clang++` executable from `CLANG_CXX` or `PATH`, or returns
  /// `null` if none is installed.
  static String? findClangExecutable({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final explicit = env['CLANG_CXX'];
    if (explicit != null && explicit.isNotEmpty) {
      return _isRunnableCompiler(explicit) ? explicit : null;
    }
    for (final candidate in _clangCandidates) {
      if (_isRunnableCompiler(candidate)) return candidate;
    }
    return null;
  }

  static bool _isRunnableCompiler(String executable) {
    try {
      final result = Process.runSync(executable, const ['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Resolves the path to `lib/src/native/fuzzer.cc` inside `package:dash_fuzz`.
  static Future<String> resolveFuzzerCcPath() async {
    final packageUri = Uri.parse('package:dash_fuzz/src/native/fuzzer.cc');
    final resolved = await Isolate.resolvePackageUri(packageUri);
    if (resolved != null) {
      final path = resolved.toFilePath();
      if (File(path).existsSync()) return path;
    }
    final fallback = p.join('lib', 'src', 'native', 'fuzzer.cc');
    if (File(fallback).existsSync()) return p.normalize(p.absolute(fallback));
    throw StateError('Unable to locate package:dash_fuzz/src/native/fuzzer.cc');
  }

  /// Compiles `fuzzer.cc` into [outputDir] and returns the absolute path to the
  /// resulting shared library (`libfuzzer_poc.so` or `libfuzzer_poc.dylib`).
  ///
  /// Throws [ToolchainMissingException] if `clang++` or `compiler-rt` is not
  /// available.
  static Future<String> buildSharedLibrary({
    required String outputDir,
    String? clangExecutable,
    bool forceRebuild = false,
  }) async {
    final clang = clangExecutable ?? findClangExecutable();
    if (clang == null || !_isRunnableCompiler(clang)) {
      final label = clang ?? 'PATH / CLANG_CXX';
      throw ToolchainMissingException(
        'No runnable clang++ executable found ($label).',
      );
    }

    final ext = Platform.isMacOS ? 'dylib' : 'so';
    final outPath = p.normalize(
      p.absolute(p.join(outputDir, 'libfuzzer_poc.$ext')),
    );
    final srcPath = await resolveFuzzerCcPath();
    if (!forceRebuild && _isUpToDate(srcPath, outPath)) {
      return outPath;
    }

    Directory(outputDir).createSync(recursive: true);
    final archive = _locateFuzzerNoMainArchive(clang);
    final args = _buildCompileArgs(
      srcPath: srcPath,
      outPath: outPath,
      archivePath: archive,
    );

    final res = Process.runSync(clang, args);
    if (res.exitCode != 0) {
      throw ToolchainMissingException(
        'Command `$clang ${args.join(' ')}` exited with ${res.exitCode}:\n'
        '${res.stderr}',
      );
    }
    return outPath;
  }

  static bool _isUpToDate(String srcPath, String outPath) {
    final outFile = File(outPath);
    if (!outFile.existsSync()) return false;
    final srcTime = File(srcPath).lastModifiedSync();
    return !outFile.lastModifiedSync().isBefore(srcTime);
  }

  static String? _locateFuzzerNoMainArchive(String clang) {
    for (final name in _fuzzerArchiveCandidates) {
      final res = Process.runSync(clang, ['-print-file-name=$name']);
      if (res.exitCode != 0) continue;
      final candidate = (res.stdout as String).trim();
      if (candidate.isNotEmpty &&
          candidate != name &&
          File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static List<String> _buildCompileArgs({
    required String srcPath,
    required String outPath,
    required String? archivePath,
  }) {
    if (Platform.isMacOS) {
      return [
        '-O2',
        '-std=c++17',
        '-dynamiclib',
        '-fPIC',
        srcPath,
        if (archivePath != null) archivePath else '-fsanitize=fuzzer-no-main',
        '-o',
        outPath,
      ];
    }
    if (archivePath == null) {
      throw const ToolchainMissingException(
        'Could not locate libclang_rt.fuzzer_no_main archive via '
        '`clang++ -print-file-name`.',
      );
    }
    return [
      '-O2',
      '-std=c++17',
      '-shared',
      '-fPIC',
      srcPath,
      archivePath,
      '-o',
      outPath,
    ];
  }
}
