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
      'dry-run',
      aliases: ['keep-temp'],
      help: "Don't create a PR or delete the temporary repo clone.",
      negatable: false,
    )
    ..addMultiOption('tweaks',
        help: 'Optionally list the specific tweaks to run (defaults to all '
            'applicable tweaks).',
        allowed: allTweaks.map((t) => t.id),
        valueHelp: 'tweak1,tweak2')
    ..addOption(
      'reviewer',
      aliases: ['pr-reviewer'],
      valueHelp: 'github-id',
      help: 'Specify the GitHub handle for the desired reviewer.',
    )
    ..addMultiOption(
      'labels',
      help: 'Specify labels to apply to the PR.',
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
      print('  ${tweak.id}: ${tweak.description}');
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

  if (argResults.flag('help') || argResults.rest.isEmpty) {
    printUsage();
    return;
  }

  final slug = argResults.rest.single;

  final dryRun = argResults.flag('dry-run');

  final reviewer = argResults.option('reviewer');
  final explicitTweakIds = argResults.multiOption('tweaks');
  final explicitTweaks = explicitTweakIds.isEmpty
      ? null
      : explicitTweakIds
          .map((id) => allTweaks.firstWhere((t) => t.id == id))
          .toList();

  final labels = argResults.multiOption('labels');

  try {
    await runFix(
      slug: slug,
      deleteTemp: !dryRun,
      tweaks: explicitTweaks,
      reviewer: reviewer,
      labels: labels,
      dryRun: dryRun,
    );
  } catch (error, stack) {
    final chain = Chain.forTrace(stack);
    print('Error type: ${error.runtimeType}');
    print(error);
    print(chain.terse.toString().trim());
    exitCode = 1;
  }
}
