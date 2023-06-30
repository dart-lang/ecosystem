// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:firehose/src/github.dart';
import 'package:firehose/src/health/coverage.dart';
import 'package:firehose/src/health/lcov.dart';
import 'package:firehose/src/repo.dart';
import 'package:test/test.dart';

void main() {
  test('LCOV parser', () {
    var parsed =
        parseLCOV('test/lcov.info', relativeTo: Directory.current.path);
    expect(
      parsed.values,
      orderedEquals([
        1.0,
        0.02857142857142857,
        0.8,
        0.8333333333333334,
        0.40625,
        0.0,
        1.0,
        0.0,
      ]),
    );
  });
  test('Compare coverage', () async {
    var coverages = FakeHealth().compareCoveragesFor(
      [
        GitFile('testfile.dart', FileStatus.modified),
      ],
      'base_path_does_not_exist',
    );

    expect(coverages.coveragePerFile, {
      'testfile.dart': Change(
        value: (0.7 - 0.5) / 0.5,
        existedBefore: true,
        existsNow: true,
      )
    });
  });
}

class FakeHealth extends Coverage {
  @override
  Map<String, double> getCoverage(Package? package) {
    Map<String, double> result;
    if (package == null) {
      // as 'base_path_does_not_exist'
      result = {'testfile.dart': 0.5};
    } else {
      result = {'testfile.dart': 0.7};
    }
    return result;
  }
}
