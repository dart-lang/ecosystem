// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart' as yaml;

import 'changelog.dart';
import 'github.dart';

class Repository {
  final Directory baseDirectory;

  Repository([Directory? base]) : baseDirectory = base ?? Directory.current;

  /// Returns true if this repository hosts only a single package, and that
  /// package lives at the top level of the repo.
  bool get isSinglePackageRepo {
    var packages = locatePackages();
    if (packages.length != 1) {
      return false;
    }

    var dir = packages.single.directory;
    return dir.absolute.path == baseDirectory.absolute.path;
  }

  /// Returns all the potentially publishable packages for the current
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
    return _recurseAndGather(baseDirectory, []);
  }

  List<Package> _recurseAndGather(Directory directory, List<Package> packages) {
    var pubspecFile = File(path.join(directory.path, 'pubspec.yaml'));

    if (pubspecFile.existsSync()) {
      var pubspec = yaml.loadYaml(pubspecFile.readAsStringSync()) as Map;
      var publishTo = pubspec['publish_to'] as String?;
      if (publishTo != 'none') {
        packages.add(Package(directory, this));
      }
    } else {
      if (directory.existsSync()) {
        for (var child in directory.listSync().whereType<Directory>()) {
          var name = path.basename(child.path);
          if (!name.startsWith('.')) {
            _recurseAndGather(child, packages);
          }
        }
      }
    }

    return packages;
  }

  String calculateRepoTag(Package package) {
    if (isSinglePackageRepo) {
      return 'v${package.pubspec.version}';
    } else {
      return '${package.name}-v${package.pubspec.version}';
    }
  }

  Uri calculateReleaseUri(Package package, Github github) {
    final tag = calculateRepoTag(package);
    final title = 'package:${package.name} v${package.pubspec.version}';
    final body = package.changelog.describeLatestChanges;
    return Uri.https('github.com', '/${github.repoSlug}/releases/new',
        {'tag': tag, 'title': title, 'body': body});
  }
}

class Package {
  final Directory directory;
  final Repository repository;

  late final Pubspec pubspec;
  late final Changelog changelog;

  Package(this.directory, this.repository) {
    pubspec = Pubspec.parse(_getPackageFile('pubspec.yaml').readAsStringSync());
    changelog = Changelog(_getPackageFile('CHANGELOG.md'));
  }

  File _getPackageFile(String fileName) =>
      File(path.join(directory.path, fileName));

  String get name => pubspec.name;

  Version? get version => pubspec.version;

  @override
  String toString() {
    return 'package:${pubspec.name} ${pubspec.version} (dir=${directory.path})';
  }
}
