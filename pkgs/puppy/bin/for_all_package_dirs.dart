// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:io/ansi.dart';
import 'package:io/io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Need something to execute!');
    exitCode = ExitCode.usage.code;
    return;
  }

  final exe = args.first;
  final extraArgs = args.skip(1).toList();

  final exits = <String, int>{};

  Future<void> inspectDirectory(Directory dir) async {
    final pubspecs = dir
        .listSync()
        .whereType<File>()
        .where((element) => element.uri.pathSegments.last == 'pubspec.yaml')
        .toList();

    if (pubspecs.isNotEmpty) {
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

    for (var subDir in dir.listSync().whereType<Directory>().where((element) =>
        !element.uri.pathSegments.any((element) => element.startsWith('.')))) {
      await inspectDirectory(subDir);
    }
  }

  await inspectDirectory(Directory.current);
}
