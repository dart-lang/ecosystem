// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:blast_repo/src/top_level.dart';
import 'package:blast_repo/src/utils.dart';
import 'package:io/io.dart';
import 'package:stack_trace/stack_trace.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'keep-temp',
      help: "Don't delete the temporary repo clone.",
      negatable: false,
    )
    ..addMultiOption('tweaks',
        help: 'Optionally list the specific tweaks to run (defaults to all '
            'stable tweaks).',
        allowed: allTweaks.map((t) => t.id),
        valueHelp: 'tweak1,tweak2')
    ..addFlag(
      'include-unstable',
      help: 'Run tweaks that are not stable.',
      negatable: false,
    )
    ..addOption(
      'pr-reviewer',
      valueHelp: 'github-id',
      help: 'Specify the GitHub handle for the desired reviewer.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Prints out usage and exits.',
    );

  void printUsage() {
    print('Usage: $packageName <options> [org/repo]\n');
    print(parser.usage);
    print('\navailable tweaks:');
    for (var tweak in allTweaks) {
      var unstable = tweak.stable ? '' : ' (unstable)';
      print('  ${tweak.id}: ${tweak.description}$unstable');
    }
  }

  final ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    printError(e.message);
    printUsage();
    exitCode = ExitCode.usage.code;
    return;
  }

  if (argResults['help'] as bool || argResults.rest.isEmpty) {
    printUsage();
    return;
  }

  final slug = argResults.rest.single;

  final keepTemp = argResults['keep-temp'] as bool;

  final includeUnstable = argResults['include-unstable'] as bool;
  final prReviewer = argResults['pr-reviewer'] as String?;
  final explicitTweakIds = argResults['tweaks'] as List<String>;
  final explicitTweaks = explicitTweakIds.isEmpty
      ? null
      : explicitTweakIds
          .map((id) => allTweaks.firstWhere((t) => t.id == id))
          .toList();

  try {
    await runFix(
      slug: slug,
      deleteTemp: !keepTemp,
      tweaks: explicitTweaks,
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
