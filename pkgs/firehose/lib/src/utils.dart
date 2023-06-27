// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

/// Execute the given CLI command asynchronously, streaming stdout and stderr to
/// the console.
///
/// This will also echo the command being run to stdout and indent the processes
/// output slightly.
Future<int> runCommand(
  String command, {
  List<String> args = const [],
  Directory? cwd,
}) async {
  print('$command ${args.join(' ')}');

  var process = await Process.start(
    command,
    args,
    workingDirectory: cwd?.path,
  );

  process.stdout
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) => stdout.writeln('  $line'));
  process.stderr
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) => stderr.writeln('  $line'));

  return process.exitCode;
}

class Tag {
  static final RegExp packageVersionTag =
      RegExp(r'^(\S+)-v(\d+\.\d+\.\d+(\+.*)?)');

  static final RegExp versionTag = RegExp(r'^v(\d+\.\d+\.\d+(\+.*)?)');

  final String tag;

  Tag(this.tag);

  bool get valid => version != null;

  String? get package {
    var match = packageVersionTag.firstMatch(tag);
    return match?.group(1);
  }

  String? get version {
    var match = packageVersionTag.firstMatch(tag);
    if (match != null) {
      return match.group(2);
    }
    match = versionTag.firstMatch(tag);
    return match?.group(1);
  }

  @override
  String toString() => tag;
}

/// Await the given [operation]; if there's a exception from the future, we
/// ignore the exception and return `null`.
Future<T?> allowFailure<T>(
  Future<T> operation, {
  required void Function(Object) logError,
}) async {
  try {
    return await operation;
  } catch (e) {
    logError(e);
    return null;
  }
}

bool expectEnv(String? value, String name) {
  if (value == null) {
    print("Expected environment variable not found: '$name'");
    return false;
  } else {
    return true;
  }
}
