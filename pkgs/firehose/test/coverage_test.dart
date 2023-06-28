import 'package:firehose/health.dart';
import 'package:test/test.dart';

void main() {
  test('Parse lcov', () {
    // Health(Directory.current).compareCoverages([
    //   GitFile('pkgs/firehose/lib/src/changelog.dart', FileStatus.modified),
    // ]);
    var parseLCOV = Health.parseLCOV('test/testfiles/lcov.info');
    expect(parseLCOV.coveragePerFile, {
      '/home/mosum/projects/ecosystem/pkgs/firehose/lib/src/changelog.dart':
          1.0,
      '/home/mosum/projects/ecosystem/pkgs/firehose/lib/src/github.dart':
          0.02857142857142857,
      '/home/mosum/projects/ecosystem/pkgs/firehose/lib/src/repo.dart': 0.8,
      '/home/mosum/projects/ecosystem/pkgs/firehose/lib/src/pubspec.dart':
          0.8333333333333334,
      '/home/mosum/projects/ecosystem/pkgs/firehose/lib/src/utils.dart':
          0.40625,
      '/home/mosum/projects/ecosystem/pkgs/firehose/lib/src/pub.dart': 1.0
    });
  });
}
