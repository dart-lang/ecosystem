// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:firehose/src/groundskeeper.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('format', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption('fix', defaultsTo: 'true', allowed: ['true', 'false'])
    ..addOption(
      'use-flutter',
      defaultsTo: 'false',
      allowed: ['true', 'false'],
    )
    ..addOption('github-output');

  final argResults = parser.parse(args);
  final githubOutputPath = argResults['github-output'] as String?;

  final code = await runGroundskeeper(
    runFormat: argResults['format'] != 'false',
    runFix: argResults['fix'] != 'false',
    useFlutter: argResults['use-flutter'] == 'true',
    githubOutputFile: githubOutputPath != null && githubOutputPath.isNotEmpty
        ? File(githubOutputPath)
        : null,
  );
  if (code != 0) {
    exit(code);
  }
}
