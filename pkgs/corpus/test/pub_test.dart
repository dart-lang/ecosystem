// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:checks/context.dart';
import 'package:corpus/pub.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  group('PackageInfo', () {
    test('parse pub.dev results', () {
      var packageInfo = PackageInfo.from(
        jsonDecode(_pubSampleData) as Map<String, dynamic>,
      );

      check(packageInfo.name).equals('usage');
      check(packageInfo.version).equals('4.0.2');
      check(packageInfo.archiveUrl).isNotNull();
      check(packageInfo.publishedDate).isNotNull();

      check(packageInfo.constraintFor('path')).isNotNull().allows('1.8.0');
      check(packageInfo.constraintFor('test')).isNotNull().allows('1.16.0');
    });
  });
}

extension VersionConstraintChecks on Subject<VersionConstraint> {
  void allows(String version) {
    context.expect(() => const ['allows'], (VersionConstraint actual) {
      final ver = Version.parse(version);
      if (!actual.allows(ver)) return Rejection(actual: ['$actual']);
      return null;
    });
  }
}

final String _pubSampleData = '''
{
  "name": "usage",
  "latest": {
    "version": "4.0.2",
    "pubspec": {
      "name": "usage",
      "version": "4.0.2",
      "description": "A Google Analytics wrapper for command-line, web, and Flutter apps.",
      "repository": "https://github.com/dart-lang/wasm",
      "environment": {
        "sdk":">=2.12.0-0 <3.0.0"
      },
      "dependencies": {
        "path":"^1.8.0"
      },
      "dev_dependencies": {
        "pedantic":"^1.9.0",
        "test":"^1.16.0"
      }
    },
    "archive_url": "https://pub.dartlang.org/packages/usage/versions/4.0.2.tar.gz",
    "published": "2021-03-30T17:44:54.093423Z"
  }
}
''';
