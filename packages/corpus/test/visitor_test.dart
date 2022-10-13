// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:corpus/api.dart';
import 'package:corpus/pub.dart';
import 'package:surveyor/src/driver.dart';
import 'package:test/test.dart';

void main() {
  group('ApiUseCollector', () {
    PackageInfo targetPackage = PackageInfo.from({'name': 'path'});
    PackageInfo referencingPackage = PackageInfo.from({'name': 'foo'});
    Directory packageDir = Directory('test/data');

    late ApiUseCollector apiUsageCollector;

    setUp(() {
      apiUsageCollector = ApiUseCollector(
        targetPackage,
        referencingPackage,
        packageDir,
      );
    });

    test('libraries references', () async {
      var driver = Driver.forArgs(['test/data/library_references.dart']);
      driver.forceSkipInstall = true;
      driver.silent = true;
      driver.showErrors = false;
      driver.visitor = apiUsageCollector;
      await driver.analyze();

      checkThat(apiUsageCollector.referringPackages.sortedLibraryReferences)
          .containsKey('package:path/path.dart');
      checkThat(apiUsageCollector.referringLibraries.sortedLibraryReferences)
          .containsKey('package:path/path.dart');
    });

    test('class references', () async {
      var driver = Driver.forArgs(['test/data/class_references.dart']);
      driver.forceSkipInstall = true;
      driver.silent = true;
      driver.showErrors = false;
      driver.visitor = apiUsageCollector;
      await driver.analyze();

      // class constructor invocation
      checkThat(apiUsageCollector.referringPackages.sortedClassReferences)
          .containsKey('PosixStyle');
      checkThat(apiUsageCollector.referringLibraries.sortedClassReferences)
          .containsKey('PosixStyle');

      // class static variable reference
      checkThat(apiUsageCollector.referringPackages.sortedClassReferences)
          .containsKey('Style');
      checkThat(apiUsageCollector.referringLibraries.sortedClassReferences)
          .containsKey('Style');
    });

    test('extension references', () async {
      apiUsageCollector = ApiUseCollector(
        PackageInfo.from({'name': 'collection'}),
        referencingPackage,
        packageDir,
      );

      var driver = Driver.forArgs(['test/data/extension_references.dart']);
      driver.forceSkipInstall = true;
      driver.silent = true;
      driver.showErrors = false;
      driver.visitor = apiUsageCollector;
      await driver.analyze();

      checkThat(apiUsageCollector.referringPackages.sortedExtensionReferences)
          .containsKey('IterableExtension');
      checkThat(apiUsageCollector.referringLibraries.sortedExtensionReferences)
          .containsKey('IterableExtension');
    });

    test('top-level symbol references', () async {
      var driver =
          Driver.forArgs(['test/data/top_level_symbol_references.dart']);
      driver.forceSkipInstall = true;
      driver.silent = true;
      driver.showErrors = false;
      driver.visitor = apiUsageCollector;
      await driver.analyze();

      // check for a top level function invokation
      checkThat(apiUsageCollector.referringPackages.sortedTopLevelReferences)
          .containsKey('join');
      checkThat(apiUsageCollector.referringLibraries.sortedTopLevelReferences)
          .containsKey('join');

      // check for a top level getter reference
      checkThat(apiUsageCollector.referringPackages.sortedTopLevelReferences)
          .containsKey('basename');
      checkThat(apiUsageCollector.referringLibraries.sortedTopLevelReferences)
          .containsKey('basename');
    });
  });
}
