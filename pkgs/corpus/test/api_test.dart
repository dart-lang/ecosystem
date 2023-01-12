// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:corpus/api.dart';
import 'package:corpus/pub.dart';
import 'package:path/path.dart' as path;
import 'package:test/scaffolding.dart';
import 'package:test_descriptor/test_descriptor.dart';

void main() {
  group('ApiUsage', () {
    late ApiUsage sampleUsage;

    setUp(() {
      var json =
          JsonDecoder().convert(_sampleUsageJson) as Map<String, dynamic>;
      sampleUsage = ApiUsage(
        PackageInfo.from(JsonDecoder().convert(_packageInfoJson)),
        References.fromJson(json['packages']),
        References.fromJson(json['libraries']),
      );
    });

    test('toFile', () {
      var tempFile = File(path.join(sandbox, 'temp.json'));
      sampleUsage.toFile(tempFile);

      checkThat(tempFile.existsSync()).isTrue();

      // we have a reference to the main package entry-point
      checkThat(tempFile.readAsStringSync()).contains('package:path/path.dart');
    });

    test('fromFile', () {
      var tempFile = File(path.join(sandbox, 'temp.json'));
      sampleUsage.toFile(tempFile);

      var result = ApiUsage.fromFile(
          PackageInfo.from(JsonDecoder().convert(_packageInfoJson)), tempFile);

      checkThat(result).isNotNull();

      var fromPackages = result.fromPackages;

      // we have a library reference from package:build
      checkThat(
        fromPackages.getLibraryReferences('package:path/path.dart'),
      ).contains(PackageEntity('build'));

      // there are no references to classes
      checkThat(fromPackages.sortedClassReferences).isEmpty();

      // there are references to top-level symbols
      checkThat(fromPackages.sortedTopLevelReferences).isNotEmpty();

      var fromLibraries = result.fromLibraries;

      // we have a library reference from package:build
      checkThat(
        fromLibraries.getLibraryReferences('package:path/path.dart'),
      ).isNotEmpty();

      // there are no references to classes
      checkThat(fromLibraries.sortedClassReferences).isEmpty();

      // there are references to top-level symbols
      checkThat(fromLibraries.sortedTopLevelReferences).isNotEmpty();
    });
  });
}

const String _sampleUsageJson = '''
{
  "packages": {
    "library": {
      "package:path/path.dart": [
        "package:build"
      ]
    },
    "class": {},
    "extension": {},
    "topLevel": {
      "url": [
        "package:build"
      ],
      "posix": [
        "package:build"
      ]
    }
  },
  "libraries": {
    "library": {
      "package:path/path.dart": [
        "library:build:lib/src/asset/id.dart"
      ]
    },
    "class": {},
    "extension": {},
    "topLevel": {
      "url": [
        "library:build:lib/src/asset/id.dart"
      ],
      "posix": [
        "library:build:lib/src/asset/id.dart"
      ]
    }
  }
}
''';

final String _packageInfoJson = '''
{
  "name": "path",
  "latest": {
    "version": "1.8.2",
    "pubspec": {
      "name": "path",
      "version": "1.8.2",
      "description": "A string-based path manipulation library.",
      "repository": "https://github.com/dart-lang/path",
      "environment": {
        "sdk": ">=2.12.0 <3.0.0"
      }
    },
    "archive_url": "https://pub.dartlang.org/packages/path/versions/1.8.2.tar.gz",
    "published": "2021-03-30T17:44:54.093423Z"
  }
}
''';
