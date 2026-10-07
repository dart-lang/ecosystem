// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('format', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption('fix', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption(
      'use-flutter',
      defaultsTo: 'false',
      allowed: ['true', 'false'],
    );

  final argResults = parser.parse(args);

  final targetDirectory = Directory.current;
  final pkgPath = targetDirectory.path;
  final runFormat = argResults['format'] != 'false';
  final runFix = argResults['fix'] != 'false';
  final useFlutter = argResults['use-flutter'] == 'true';

  print('Target Directory: ${targetDirectory.absolute.path}');
  print('Run format: $runFormat');
  print('Run fix: $runFix');
  print('Use Flutter: $useFlutter');

  final pubspecFile = File(path.join(targetDirectory.path, 'pubspec.yaml'));
  final isPackage = pubspecFile.existsSync();

  if (runFix && !isPackage) {
    print('''
Error: Run fix is enabled, but no pubspec.yaml found in ${targetDirectory.path}''');
    exit(1);
  }

  if (isPackage) {
    final tool = useFlutter ? 'flutter' : 'dart';

    print(
        'Tidying package in $pkgPath (${useFlutter ? 'Flutter' : 'Dart'})...');

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
