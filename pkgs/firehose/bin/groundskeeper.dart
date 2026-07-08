// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:firehose/firehose.dart';
import 'package:path/path.dart' as path;

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('format', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption('fix', defaultsTo: 'true', allowed: ['true', 'false']);

  final argResults = parser.parse(args);

  final targetDirectory = Directory.current;
  final pkgPath = targetDirectory.path;
  final runFormat = argResults['format'] != 'false';
  final runFix = argResults['fix'] != 'false';

  print('Target Directory: ${targetDirectory.absolute.path}');
  print('Run format: $runFormat');
  print('Run fix: $runFix');

  final pubspecFile = File(path.join(targetDirectory.path, 'pubspec.yaml'));
  final isPackage = pubspecFile.existsSync();

  if (runFix && !isPackage) {
    print('''
Error: Run fix is enabled, but no pubspec.yaml found in ${targetDirectory.path}''');
    exit(1);
  }

  if (isPackage) {
    final repo = Repository(targetDirectory);
    final pkg = Package(targetDirectory, repo);

    // Detect if it is a Flutter package
    final isFlutter = pkg.pubspec.dependencies.containsKey('flutter') ||
        pkg.pubspec.devDependencies.containsKey('flutter');
    final tool = isFlutter ? 'flutter' : 'dart';

    print('Tidying package in $pkgPath (${isFlutter ? 'Flutter' : 'Dart'})...');

    print('  Running $tool pub get...');
    final pubGetResult =
        await Process.run(tool, ['pub', 'get'], workingDirectory: pkgPath);
    stdout.write(pubGetResult.stdout);
    stderr.write(pubGetResult.stderr);
    if (pubGetResult.exitCode != 0) {
      print('Error: $tool pub get failed in $pkgPath');
      exit(pubGetResult.exitCode);
    }
  }

  if (runFormat) {
    print('Running dart format...');
    final result = await Process.run(
      'dart',
      ['format', pkgPath],
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      exit(result.exitCode);
    }
  }

  if (runFix) {
    print('  Running dart fix --apply...');
    final fixResult = await Process.run('dart', ['fix', '--apply'],
        workingDirectory: pkgPath);
    stdout.write(fixResult.stdout);
    stderr.write(fixResult.stderr);
    if (fixResult.exitCode != 0) {
      print('Error: dart fix failed in $pkgPath');
      exit(fixResult.exitCode);
    }
  }
}
