// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:blast_repo/src/top_level.dart';
import 'package:blast_repo/src/utils.dart';
import 'package:stack_trace/stack_trace.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'keep-temp',
      negatable: false,
    )
    ..addFlag(
      'include-unstable',
      help: 'To run tweaks that are not stable.',
      negatable: false,
    )
    ..addOption(
      'pr-reviewer',
      help: 'The GitHub handle for the desired reviewer.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Prints out usage and exits',
    );

  final argResults = parser.parse(args);

  if (argResults['help'] as bool) {
    print('Usage: $packageName <options> [org/repo]\n');
    print(parser.usage);
    return;
  }

  final slug = argResults.rest.single;

  final keepTemp = argResults['keep-temp'] as bool;

  final includeUnstable = argResults['include-unstable'] as bool;
  final prReviewer = argResults['pr-reviewer'] as String?;

  try {
    await runFix(
      slug: slug,
      deleteTemp: !keepTemp,
      onlyStable: !includeUnstable,
      prReviewer: prReviewer,
    );
  } catch (error, stack) {
    final chain = Chain.forTrace(stack);
    print('Error type: ${error.runtimeType}');
    print(error);
    print(chain.terse.toString().trim());
    exitCode = 1;
  }
}
