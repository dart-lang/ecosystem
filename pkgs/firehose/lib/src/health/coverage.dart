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
  Future<CoverageResult> compareCoverages(List<GitFile> files) async {
    var coverageResult = CoverageResult({});
    for (var package in Repository().locatePackages()) {
      var currentPath = Directory.current.path;
      var relative = path.join(Directory.current.path, '.coverage_base');
      var oldPackageDirectory = path.join(
        relative,
        path.relative(package.directory.path, from: currentPath),
      );
      var oldCoverages = parseLcov(oldPackageDirectory, relative);
      var newCoverages = parseLcov(package.directory.path, currentPath);
      print('Old coverage: $oldCoverages');
      print('New coverage: $newCoverages');
      for (var file in files
          .map((file) => file.relativePath)
          .where((file) => path.extension(file) == '.dart')
          .where((file) =>
              !path.isWithin(path.join(package.directory.path, 'test'), file))
          .where((file) => path.isWithin(package.directory.path, file))) {
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

  Map<String, double> parseLcov(String packageDirectory, String relativeTo) {
    return parseLCOV(
      path.join(packageDirectory, 'coverage/lcov.info'),
      relativeTo: relativeTo,
    );
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
