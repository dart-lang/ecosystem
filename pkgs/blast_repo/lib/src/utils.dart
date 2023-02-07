// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:git/git.dart';
import 'package:io/ansi.dart';
import 'package:path/path.dart' as p;

const packageName = 'blast_repo';

Future<void> cloneGitHubRepoToPath(String slug, String path) {
  printHeader('Cloning repo $slug');
  return runGit(
    [
      'clone',
      '--depth',
      '1',
      'https://github.com/$slug',
      path,
    ],
    echoOutput: true,
  );
}

extension GitDirExtension on GitDir {
  Future<ProcessResult> exec(String description, List<String> args) async {
    printHeader(description);

    printDim(
      [
        'git',
        ...args,
      ].join(' '),
    );

    return await runCommand(args, echoOutput: true);
  }
}

Future<void> runProc(
  String description,
  String proc,
  List<String> args, {
  required String workingDirectory,
}) async {
  printHeader(description);

  printDim(
    [
      proc,
      ...args,
    ].join(' '),
  );
  final ghProc = await Process.start(
    proc,
    args,
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
  );

  final exitCode = await ghProc.exitCode;

  if (exitCode != 0) {
    throw ProcessException(proc, args, 'Process failed', exitCode);
  }
}

Future<void> withSystemTemp(
  Future<void> Function(Directory directory, String runKey) action, {
  bool deleteTemp = true,
}) async {
  final runKey = '$packageName-${_fileDate()}';
  final tempDir = Directory.systemTemp.createTempSync(runKey);
  try {
    await action(tempDir, runKey);
  } finally {
    if (deleteTemp) {
      tempDir.deleteSync(recursive: true);
    } else {
      printHeader('Temp directory retained at: ${tempDir.path}');
    }
  }
}

void printHeader(Object? value) {
  print(styleBold.wrap(value.toString()));
}

void printDim(Object? value) {
  print(styleDim.wrap(value.toString()));
}

void printError(Object? value) {
  print(wrapWith(value.toString(), [red, styleBold]));
}

final _dateSeparators = RegExp('[-:.]');

String _fileDate() => DateTime.now()
    .toUtc()
    .toIso8601String()
    .split(_dateSeparators)
    .take(5)
    .join('_');

/// This makes a best effort to find the default branch of the given repo.
String? gitDefaultBranch(Directory repoDir) {
  const branchNames = {'main', 'master'};

  var configFile = File(p.join(repoDir.path, '.git', 'config'));
  if (!configFile.existsSync()) return null;

  var lines = configFile.readAsLinesSync();

  for (var name in branchNames) {
    if (lines.contains('[branch "$name"]')) {
      return name;
    }
  }

  return null;
}

/// Returns whether this repo is a single package repo (or a mono-repo).
bool singlePackageRepo(Directory repoDir) {
  // Here, we assume that having a pubspec at the top level of a repo implies
  // a single package repo.
  var pubspec = File(p.join(repoDir.path, 'pubspec.yaml'));
  return pubspec.existsSync();
}
