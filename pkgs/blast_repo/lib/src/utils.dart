// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:git/git.dart';
import 'package:io/ansi.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

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

Future<int> runProc(
  String description,
  String proc,
  List<String> args, {
  required String workingDirectory,
  bool throwOnFailure = true,
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

  if (throwOnFailure && exitCode != 0) {
    throw ProcessException(proc, args, 'Process failed', exitCode);
  }

  return exitCode;
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

/// Returns whether the given repo follows some conventions for our monorepos.
///
/// Currently this checks for either the presense of a `mono_repo.yaml` file or
/// of a top-level `pkgs/` directory.
bool monoRepo(Directory dir, String repoSlug) {
  if (File(p.join(dir.path, 'mono_repo.yaml')).existsSync()) {
    return true;
  }

  if (Directory(p.join(dir.path, 'pkgs')).existsSync()) {
    return true;
  }

  return false;
}

Version? latestStableVersion(List<Version> versions) {
  final sorted = versions.toList()..sort();
  return sorted.whereNot((version) => version.preRelease.isNotEmpty).lastOrNull;
}
