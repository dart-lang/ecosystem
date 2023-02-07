// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:corpus/api.dart';
import 'package:corpus/pub.dart';
import 'package:corpus/report.dart';
import 'package:corpus/surveyor.dart';
import 'package:test/test.dart';

void main() {
  group('ApiUseCollector - packages', () {
    var targetPackage = PackageInfo.from({
      'name': 'path',
      'latest': {
        'version': '0.1.2',
        'pubspec': <String, dynamic>{},
      }
    });
    ReportTarget reportTarget = PackageTarget.fromPackage(targetPackage);
    var referencingPackage = PackageInfo.from({'name': 'foo'});
    var packageDir = Directory('test/data');

    late ApiUseCollector apiUsageCollector;

    setUp(() {
      apiUsageCollector = ApiUseCollector(
        reportTarget,
        referencingPackage,
        packageDir,
      );
    });

    test('libraries references', () async {
      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/library_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      check(apiUsageCollector.referringPackages.sortedLibraryReferences)
          .containsKey('package:path/path.dart');
      check(apiUsageCollector.referringLibraries.sortedLibraryReferences)
          .containsKey('package:path/path.dart');
    });

    test('class references', () async {
      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/class_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      // class constructor invocation
      check(apiUsageCollector.referringPackages.sortedClassReferences)
          .containsKey('PosixStyle');
      check(apiUsageCollector.referringLibraries.sortedClassReferences)
          .containsKey('PosixStyle');

      // class static variable reference
      check(apiUsageCollector.referringPackages.sortedClassReferences)
          .containsKey('Style');
      check(apiUsageCollector.referringLibraries.sortedClassReferences)
          .containsKey('Style');
    });

    test('extension references', () async {
      apiUsageCollector = ApiUseCollector(
        PackageTarget.fromPackage(PackageInfo.from({
          'name': 'collection',
          'latest': {
            'version': '0.1.2',
            'pubspec': <String, dynamic>{},
          }
        })),
        referencingPackage,
        packageDir,
      );

      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/extension_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      check(apiUsageCollector.referringPackages.sortedExtensionReferences)
          .containsKey('IterableExtension');
      check(apiUsageCollector.referringLibraries.sortedExtensionReferences)
          .containsKey('IterableExtension');
    });

    test('top-level symbol references', () async {
      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/top_level_symbol_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      // check for a top level function invokation
      check(apiUsageCollector.referringPackages.sortedTopLevelReferences)
          .containsKey('join');
      check(apiUsageCollector.referringLibraries.sortedTopLevelReferences)
          .containsKey('join');

      // check for a top level getter reference
      check(apiUsageCollector.referringPackages.sortedTopLevelReferences)
          .containsKey('basename');
      check(apiUsageCollector.referringLibraries.sortedTopLevelReferences)
          .containsKey('basename');
    });
  });

  group('ApiUseCollector - dart:', () {
    ReportTarget reportTarget = DartLibraryTarget(
      name: 'collection',
      version: _sdkVersion,
    );
    var referencingPackage = PackageInfo.from({'name': 'foo'});
    var packageDir = Directory('test/data');

    late ApiUseCollector apiUsageCollector;

    setUp(() {
      apiUsageCollector = ApiUseCollector(
        reportTarget,
        referencingPackage,
        packageDir,
      );
    });

    test('libraries references', () async {
      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/dart_library_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      check(apiUsageCollector.referringPackages.sortedLibraryReferences)
          .containsKey('dart:collection');
      check(apiUsageCollector.referringLibraries.sortedLibraryReferences)
          .containsKey('dart:collection');
    });

    test('class references', () async {
      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/dart_library_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      // class constructor invocation
      check(apiUsageCollector.referringPackages.sortedClassReferences)
          .containsKey('SplayTreeMap');
      check(apiUsageCollector.referringLibraries.sortedClassReferences)
          .containsKey('SplayTreeMap');

      // class static method reference
      check(apiUsageCollector.referringPackages.sortedClassReferences)
          .containsKey('Queue');
      check(apiUsageCollector.referringLibraries.sortedClassReferences)
          .containsKey('Queue');
    });

    test('top-level symbol references', () async {
      apiUsageCollector = ApiUseCollector(
        DartLibraryTarget(name: 'convert', version: _sdkVersion),
        referencingPackage,
        packageDir,
      );

      var surveyor = Surveyor.fromDirs(
        directories: [
          Directory('test/data/dart_top_level_symbol_references.dart')
        ],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      // check for a top level function invokation
      check(apiUsageCollector.referringPackages.sortedTopLevelReferences)
          .containsKey('jsonDecode');
      check(apiUsageCollector.referringLibraries.sortedTopLevelReferences)
          .containsKey('jsonDecode');

      // check for a top level getter reference
      check(apiUsageCollector.referringPackages.sortedTopLevelReferences)
          .containsKey('base64');
      check(apiUsageCollector.referringLibraries.sortedTopLevelReferences)
          .containsKey('base64');
    });

    test('extension references', () async {
      apiUsageCollector = ApiUseCollector(
        DartLibraryTarget(name: 'async', version: _sdkVersion),
        referencingPackage,
        packageDir,
      );

      var surveyor = Surveyor.fromDirs(
        directories: [Directory('test/data/dart_extension_references.dart')],
        visitor: apiUsageCollector,
      );

      await surveyor.analyze();

      check(apiUsageCollector.referringPackages.sortedExtensionReferences)
          .containsKey('FutureExtensions');
      check(apiUsageCollector.referringLibraries.sortedExtensionReferences)
          .containsKey('FutureExtensions');
    });
  });
}

String get _sdkVersion {
  var version = Platform.version;
  if (version.contains('-')) {
    version = version.substring(0, version.indexOf('-'));
  }
  return version;
}
