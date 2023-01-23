// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:cli_util/cli_logging.dart';

String percent(int val, int count) {
  return '${(val * 100 / count).round()}%';
}

String pluralize(int count, String word, {String? plural}) {
  return count == 1 ? word : (plural ?? '${word}s');
}

Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool verbose = false,
  Logger? logger,
}) async {
  if (verbose) {
    print('$executable ${arguments.join(' ')}');
  }

  var result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    var out = result.stdout as String;
    if (out.isNotEmpty) {
      logger == null ? print(out.trimRight()) : logger.stdout(out.trimRight());
    }
    out = result.stderr as String;
    if (out.isNotEmpty) {
      logger == null ? print(out.trimRight()) : logger.stderr(out.trimRight());
    }
  }
  return result;
}
