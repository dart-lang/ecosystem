// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;

import '../github.dart';
import '../repo.dart';
import '../utils.dart';
import 'lcov.dart';

class Coverage {
  Future<CoverageResult> compareCoverages() async {
    var files = await Github().listFilesForPR();
    var basePath = '../base_repo/';

    return compareCoveragesFor(files, basePath);
  }

  CoverageResult compareCoveragesFor(List<GitFile> files, String basePath) {
    var repository = Repository();
    var packages = repository.locatePackages();
    print('Found packages $packages at ${Directory.current}');

    var filesOfInterest = files
        .where((file) => path.extension(file.filename) == '.dart')
        .where((file) => isInSomePackage(packages, file.relativePath))
        .where((file) => isNotATest(packages, file.relativePath))
        .toList();

    var base = Directory(basePath);

    var baseRepository = Repository(base);
    var basePackages = baseRepository.locatePackages();
    print('Found packages $basePackages at $base');

    var changedPackages = packages
        .where((package) =>
            filesOfInterest.any((file) => file.isInPackage(package)))
        .toList();

    var coverageResult = CoverageResult({});
    for (var package in changedPackages) {
      final newCoverages = getCoverage(package);

      final basePackage = basePackages
          .where((element) => element.name == package.name)
          .firstOrNull;
      final oldCoverages = getCoverage(basePackage);
      for (var file in filesOfInterest.map((file) => file.relativePath)) {
        var oldCoverage = oldCoverages[file];
        var newCoverage = newCoverages[file];
        Change change;
        if (oldCoverage == null && newCoverage == null) {
          change = Change(existedBefore: false, existsNow: false);
        } else if (oldCoverage == null) {
          change = Change(
            value: newCoverage!,
            existedBefore: false,
            existsNow: true,
          );
        } else {
          change = Change(
            value: ((newCoverage ?? 0) - oldCoverage) / oldCoverage.abs(),
          );
        }
        coverageResult[file] = change;
      }
    }
    return coverageResult;
  }

  bool isNotATest(List<Package> packages, String file) {
    return packages.every((package) =>
        !path.isWithin(path.join(package.directory.path, 'test'), file));
  }

  bool isInSomePackage(List<Package> packages, String file) {
    return packages
        .any((package) => path.isWithin(package.directory.path, file));
  }

  Map<String, double> getCoverage(Package? package) {
    if (package != null) {
      var hasTests =
          Directory(path.join(package.directory.path, 'test')).existsSync();
      if (hasTests) {
        print('''
Get coverage for ${package.name} by running coverage in ${package.directory.path}''');
        var result = Process.runSync(
          'dart',
          ['dart', 'pub', 'global', 'run', 'coverage:test_with_coverage'],
          workingDirectory: package.directory.path,
        );
        print(result.stdout);
        print(result.stderr);
        return parseLCOV(
          path.join(package.directory.path, 'coverage/lcov.info'),
          relativeTo: package.repository.baseDirectory.path,
        );
      }
    }
    return {};
  }
}

class CoverageResult {
  final Map<String, Change> coveragePerFile;

  CoverageResult(this.coveragePerFile);

  CoverageResult operator +(CoverageResult other) {
    return CoverageResult({...coveragePerFile, ...other.coveragePerFile});
  }

  Change? operator [](String s) => coveragePerFile[s];
  void operator []=(String s, Change d) => coveragePerFile[s] = d;
}

class Change {
  final double? value;
  final bool existedBefore;
  final bool existsNow;

  Change({this.value, this.existedBefore = true, this.existsNow = true});

  Severity get severity => _severityWithMessage().$1;

  String toMarkdown() => _severityWithMessage().$2;

  (Severity, String) _severityWithMessage() {
    if (existedBefore || existsNow) {
      var valueAsPercentage = '${(value! * 100).abs().toStringAsFixed(1)} %';
      if (existedBefore) {
        if (value! > 0) {
          return (
            Severity.success,
            ':green_heart: Increased by $valueAsPercentage'
          );
        } else {
          return (
            Severity.warning,
            ':broken_heart: Decreased by $valueAsPercentage'
          );
        }
      } else {
        if (value! > 0) {
          return (
            Severity.success,
            ':green_heart: Total coverage $valueAsPercentage'
          );
        } else {
          // As the file did not exist before, there cannot be coverage...
          return (Severity.warning, ':broken_heart: No coverage for this file');
        }
      }
    } else {
      return (Severity.warning, ':broken_heart: No coverage for this file');
    }
  }

  @override
  bool operator ==(covariant Change other) {
    if (identical(this, other)) return true;

    return other.value == value &&
        other.existedBefore == existedBefore &&
        other.existsNow == existsNow;
  }

  @override
  int get hashCode =>
      value.hashCode ^ existedBefore.hashCode ^ existsNow.hashCode;

  @override
  String toString() => '''
Change(value: $value, existedBefore: $existedBefore, existsNow: $existsNow)''';
}
