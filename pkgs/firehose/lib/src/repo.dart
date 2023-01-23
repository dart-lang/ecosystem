// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/changelog.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

import 'pubspec.dart';

class Repo {
  /// Returns true if this repository hosts only a single package, and that
  /// package lives at the top level of the repo.
  bool get singlePackageRepo {
    var packages = locatePackages();
    if (packages.length != 1) {
      return false;
    }

    var dir = packages.single.directory;
    return dir.absolute.path == Directory.current.absolute.path;
  }

  /// This will return all the potentially publishable packages for the current
  /// repository.
  ///
  /// This could be one package - if this is a single package repository - or
  /// multiple packages, if this is a monorepo.
  ///
  /// Packages will be returned if their pubspec doesn't contain a
  /// `publish_to: none` key.
  ///
  /// Once we find a package, we don't look for packages in sub-directories.
  List<Package> locatePackages() {
    return _recurseAndGather(Directory.current, []);
  }

  List<Package> _recurseAndGather(Directory directory, List<Package> packages) {
    var pubspecFile = File(path.join(directory.path, 'pubspec.yaml'));

    if (pubspecFile.existsSync()) {
      var pubspec = yaml.loadYaml(pubspecFile.readAsStringSync()) as Map;
      var publishTo = pubspec['publish_to'] as String?;
      if (publishTo != 'none') {
        packages.add(Package(directory));
      }
    } else {
      for (var child in directory.listSync().whereType<Directory>()) {
        var name = path.basename(child.path);
        if (!name.startsWith('.')) {
          _recurseAndGather(child, packages);
        }
      }
    }

    return packages;
  }

  String calculateRepoTag(Package package) {
    if (singlePackageRepo) {
      return 'v${package.pubspec.version}';
    } else {
      return '${package.name}-v${package.pubspec.version}';
    }
  }
}

class Package {
  final Directory directory;

  late final Pubspec pubspec;
  late final Changelog changelog;

  Package(this.directory) {
    pubspec = Pubspec(directory);
    changelog = Changelog(File(path.join(directory.path, 'CHANGELOG.md')));
  }

  String get name => pubspec.name;

  bool containsFile(String file) {
    return path.isWithin(directory.path, file);
  }

  List<String> matchingFiles(List<String> changedFiles) {
    var fullPath = directory.absolute.path;
    return changedFiles.where(containsFile).map((file) {
      return File(file).absolute.path.substring(fullPath.length + 1);
    }).toList();
  }

  @override
  String toString() {
    return 'package:${pubspec.name} ${pubspec.version} (dir=${directory.path})';
  }
}
