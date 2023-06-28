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
      .transform(const LineSplitter())
      .listen((line) => stdout
        ..write('  ')
        ..writeln(line));
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr
        ..write('  ')
        ..writeln(line));

  return process.exitCode;
}

class Tag {
  /// RegExp matching a version tag at the start of a line.
  ///
  /// A version tag is an optional starting seqeuence
  /// of non-whitespace, which is the package name,
  /// followed by a `v` and a simplified SemVer version
  /// number.
  /// The version number accepted is
  /// > digits '.' digits '.' digits
  ///
  /// and if followed by a `+`, then it includes the
  /// rest of the line.
  static final RegExp packageVersionTag =
      RegExp(r'^(?:(\S+)-)?v(\d+\.\d+\.\d+(?:\+.*)?)');

  /// A package version tag.
  ///
  /// Is expected to have the format:
  /// > (package-name)? 'v' SemVer-version
  ///
  /// If not, the tag is not [valid], and the [package] and [version]
  /// will both be `null`.
  final String tag;

  Tag(this.tag);

  bool get valid => version != null;

  /// The package name before the `v` in the version [tag], if any.
  ///
  /// Is `null` if there is no package name before the `v`,
  /// or if the tag is not [valid].
  String? get package => packageVersionTag.firstMatch(tag)?[1];

  /// The SemVer version string of the version [tag], if any.
  ///
  /// This is the part after the `v` of the [tag] string,
  /// of the form, which is a major/minor/patch version string
  /// optionally followed by a `+` and more characters.
  ///
  /// Is `null` if the tag is not [valid].
  String? get version => packageVersionTag.firstMatch(tag)?[2];

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
