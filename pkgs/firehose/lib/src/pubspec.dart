// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart' as yaml;

class Pubspec {
  final Directory directory;
  late final Map _yaml;

  Pubspec(this.directory) {
    var file = File(path.join(directory.path, 'pubspec.yaml'));
    _yaml = yaml.loadYaml(file.readAsStringSync()) as Map;
  }

  /// Return the package name.
  String get name => _yaml['name'] as String;

  /// Return the package version.
  ///
  /// Returns null if no version is specified.
  String? get version => _yaml['version'] as String?;

  /// Returns whether the pubspec semver version is a pre-release version
  /// (`'1.2.3-foo'`).
  bool get isPreRelease => Version.parse(version!).isPreRelease;
}
