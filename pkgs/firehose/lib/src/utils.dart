// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Execute the given CLI command asynchronously, streaming stdout and stderr to
/// the console.
///
/// This will also echo the command being run to stdout and indent the processes
/// output slightly.
Future<CommandResult> runCommand(
  String command, {
  List<String> args = const [],
  Directory? cwd,
}) async {
  print('$command ${args.join(' ')}');

  final process = await Process.start(
    command,
    args,
    workingDirectory: cwd?.path,
  );

  final buffer = StringBuffer();

  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    buffer.writeln(line);
    stdout
      ..write('  ')
      ..writeln(line);
  }).asFuture<void>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr
        ..write('  ')
        ..writeln(line))
      .asFuture<void>();

  final code = await process.exitCode;
  // Wait for all output to be written so that it isn't interleaved with any
  // output from the caller after this returns.
  await Future.wait([stdoutDone, stderrDone]);

  return CommandResult(
    code: code,
    stdout: buffer.toString(),
  );
}

/// Runs [body] with any output it prints inside a collapsible group in the
/// GitHub Actions log.
///
/// The group is shown with [title], and is collapsed by default. GitHub
/// Actions does not support nested groups, so [body] should not call
/// [inLogGroup].
///
/// See https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#grouping-log-lines.
Future<T> inLogGroup<T>(String title, FutureOr<T> Function() body) async {
  print('::group::${title.replaceAll('\n', ' ')}');
  try {
    return await body();
  } finally {
    print('::endgroup::');
  }
}

class CommandResult {
  final int code;
  final String stdout;

  CommandResult({required this.code, required this.stdout});
}

class Tag {
  /// RegExp matching a version tag at the start of a line.
  ///
  /// A version tag is an optional starting sequence of non-whitespace, which
  /// is the package name, followed by [prefix] (defaulting to `'v'`) and a
  /// simplified SemVer version number.
  ///
  /// The version number accepted is:
  ///
  /// > digits '.' digits '.' digits
  ///
  /// and if followed by a `+` or `-`, then it includes the remaining
  /// non-whitespace characters.
  static RegExp packageVersionTag({String prefix = 'v'}) => RegExp(
      '^(?:(\\S+)-)?${RegExp.escape(prefix)}(\\d+\\.\\d+\\.\\d+(?:[+\\-]\\S*)?)');

  /// A package version tag.
  ///
  /// Is expected to have the format:
  ///
  /// > (package-name)? prefix SemVer-version
  ///
  /// If not, the tag is not [valid], and the [package] and [version] will both
  /// be `null`.
  final String tag;
  final String prefix;

  Tag(this.tag, {this.prefix = 'v'});

  late final Match? _match = packageVersionTag(prefix: prefix).firstMatch(tag);

  bool get valid => version != null;

  /// The package name before the prefix in the version [tag], if any.
  ///
  /// Is `null` if there is no package name before the prefix,
  /// or if the tag is not [valid].
  String? get package => _match?[1];

  /// The SemVer version string of the version [tag], if any.
  ///
  /// This is the part after the prefix of the [tag] string,
  /// of the form, which is a major/minor/patch version string
  /// optionally followed by a `+` and more characters.
  ///
  /// Is `null` if the tag is not [valid].
  String? get version => _match?[2];

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

typedef Logger = void Function(String message);

const Logger printLogger = print;

enum Severity {
  success(':heavy_check_mark:'),
  info(':heavy_check_mark:'),
  warning(':warning:'),
  error(':exclamation:');

  final String emoji;

  const Severity(this.emoji);
}
