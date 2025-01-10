// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_cli_annotations/build_cli_annotations.dart';
import 'package:io/ansi.dart';

part 'map_command.g.dart';

class MapCommand extends _$MapArgsCommand<void> {
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
class MapArgs {
  @CliOption(abbr: 'd', help: 'Keep looking for "nested" pubspec files.')
  final bool deep;

  final List<String> rest;

  MapArgs({
    this.deep = false,
    required this.rest,
  }) {
    if (rest.isEmpty) {
      throw UsageException(
        'Missing command to invoke!',
        'puppy map [--deep] <command to invoke>',
      );
    }
  }
}

Future<void> _doMap(MapArgs args) async {
  final exe = args.rest.first;
  final extraArgs = args.rest.skip(1).toList();

  final exits = <String, int>{};

  Future<void> inspectDirectory(Directory dir, {required bool deep}) async {
    final pubspecs = dir
        .listSync()
        .whereType<File>()
        .where((element) => element.uri.pathSegments.last == 'pubspec.yaml')
        .toList();

    final pubspecHere = pubspecs.isNotEmpty;
    if (pubspecHere) {
      print(green.wrap(dir.path));
      final proc = await Process.start(
        exe,
        extraArgs,
        mode: ProcessStartMode.inheritStdio,
        workingDirectory: dir.path,
      );

      // TODO(kevmoo): display a summary of results on completion
      exits[dir.path] = await proc.exitCode;
    }

    if (!pubspecHere || deep) {
      for (var subDir in dir.listSync().whereType<Directory>().where(
          (element) => !element.uri.pathSegments
              .any((element) => element.startsWith('.')))) {
        await inspectDirectory(subDir, deep: deep);
      }
    }
  }

  await inspectDirectory(Directory.current, deep: args.deep);
}
