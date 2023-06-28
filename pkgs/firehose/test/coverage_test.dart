import 'dart:io';

import 'package:firehose/health.dart';
import 'package:test/test.dart';

void main() {
  test('Parse lcov', () {
    // Health(Directory.current).compareCoverages([
    //   GitFile('pkgs/firehose/lib/src/changelog.dart', FileStatus.modified),
    // ]);
    var parseLCOV =
        Health.parseLCOV('test/testfiles/lcov.info', Directory.current.path);
    expect(parseLCOV.coveragePerFile, {
      'lib/src/changelog.dart': 1.0,
      'lib/src/github.dart': 0.02857142857142857,
      'lib/src/repo.dart': 0.8,
      'lib/src/pubspec.dart': 0.8333333333333334,
      'lib/src/utils.dart': 0.40625,
      'lib/src/pub.dart': 1.0
    });
  });
}
