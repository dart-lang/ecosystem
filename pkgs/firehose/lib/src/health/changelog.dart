// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

import '../github.dart';
import '../repo.dart';
import '../utils.dart';

Future<Map<Package, List<GitFile>>> packagesWithoutChangelog(
    GithubApi github, List<Glob> ignoredFiles) async {
  final repo = Repository();
  final packages = repo.locatePackages(ignoredFiles);

  final files = await github.listFilesForPR(ignoredFiles);

  var packagesWithoutChangedChangelog =
      collectPackagesWithoutChangelogChanges(packages, files);

  print('Collecting files without license headers in those packages:');
  var packagesWithChanges = <Package, List<GitFile>>{};
  for (final file in files) {
    for (final package in packagesWithoutChangedChangelog) {
      if (fileNeedsEntryInChangelog(package, file.relativePath)) {
        print(file);
        packagesWithChanges.update(
          package,
          (changedFiles) => [...changedFiles, file],
          ifAbsent: () => [file],
        );
      }
    }
  }
  print('''
Done, found ${packagesWithChanges.length} packages with a need for a changelog.''');
  return packagesWithChanges;
}

List<Package> collectPackagesWithoutChangelogChanges(
    List<Package> packages, List<GitFile> files) {
  print('Collecting packages without changed changelogs:');
  final packagesWithoutChangedChangelog = packages
      .where((package) => package.changelog.exists)
      .where((package) => !files
          .map((e) => e.relativePath)
          .contains(package.changelog.file.relativePath))
      .toList();
  print('Done, found ${packagesWithoutChangedChangelog.length} packages.');
  return packagesWithoutChangedChangelog;
}

bool fileNeedsEntryInChangelog(Package package, String file) {
  final directoryPath = package.directory.path;
  final directory = path.relative(directoryPath, from: Directory.current.path);
  final isInPackage = path.isWithin(directory, file);
  final isInLib = path.isWithin(path.join(directory, 'lib'), file);
  final isInBin = path.isWithin(path.join(directory, 'bin'), file);
  final isPubspec = file.endsWith('pubspec.yaml');
  final isReadme = file.endsWith('README.md');
  return isInPackage && (isInLib || isInBin || isPubspec || isReadme);
}
