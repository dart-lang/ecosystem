// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_cli_annotations/build_cli_annotations.dart';
import 'package:io/ansi.dart';

import 'constants.dart';
import 'utils.dart';

part 'run_command.g.dart';

class RunCommand extends _$RunArgsCommand<void> {
  @override
  String get description =>
      'Run the provided command in each subdirectory containing '
      '`pubspec.yaml`.';

  @override
  String get name => 'map';

  @override
  Future<void>? run() async {
    await _doMap(_options);
  }
}

@CliOptions(createCommand: true)
class RunArgs {
  @CliOption(abbr: 'd', help: 'Keep looking for "nested" pubspec files.')
  final bool deep;

  final List<String> rest;

  RunArgs({
    this.deep = false,
    required this.rest,
  }) {
    if (rest.isEmpty) {
      throw UsageException(
        'Missing command to invoke!',
        '$cmdName map [--deep] <command to invoke>',
      );
    }
  }
}

Future<void> _doMap(RunArgs args) async {
  final exe = args.rest.first;
  final extraArgs = args.rest.skip(1).toList();

  final packages = findPackages(Directory.current, deep: args.deep);
  final exits = <String, int>{};

  for (final packageDir in packages) {
    print(green.wrap(packageDir.path));
    final proc = await Process.start(
      exe,
      extraArgs,
      mode: ProcessStartMode.inheritStdio,
      workingDirectory: packageDir.path,
    );

    // TODO(kevmoo): display a summary of results on completion
    exits[packageDir.path] = await proc.exitCode;

    print('');
  }
}
