import 'dart:io';

import 'package:firehose/health.dart';
import 'package:firehose/src/github.dart';
import 'package:test/test.dart';

void main() {
  test('LCOV parser', () {
    var parseLCOV = Health(Directory.current)
        .parseLCOV('test/lcov.info', relativeTo: Directory.current.path);
    expect(
      parseLCOV.coveragePerFile.values.map((e) => e.value),
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
    var coverages = await FakeHealth(Directory.current).compareCoverages([
      GitFile('testfile.dart', FileStatus.modified),
    ]);

    expect(coverages.coveragePerFile, {
      'testfile.dart': Change(
        value: (0.7 - 0.5) / 0.5,
        existedBefore: true,
        existsNow: true,
      )
    });
  });
}

class FakeHealth extends Health {
  FakeHealth(super.directory);

  @override
  CoverageResult parseLCOV(String lcovPath, {required String relativeTo}) {
    CoverageResult result;
    if (lcovPath.contains('.coverage_base')) {
      result = CoverageResult({'testfile.dart': Change(value: 0.5)});
    } else {
      result = CoverageResult({'testfile.dart': Change(value: 0.7)});
    }
    return result;
  }
}
